import CoreImage
import UIKit

struct PhotoMemoryAnalysis: Equatable, Sendable {
    let representativeColor: String
    let palette: [String]
    let brightness: Double
    let edgeDensity: Double
}

enum PhotoMemoryService {
    private static let directoryName = "SunGlassMemories"

    static func store(_ data: Data, projectID: UUID) throws -> String {
        let directory = try memoryDirectory()
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(fileName)

        guard let image = UIImage(data: data),
              let normalized = image.preparingThumbnail(of: CGSize(width: 1600, height: 1600)),
              let jpeg = normalized.jpegData(compressionQuality: 0.86) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try jpeg.write(to: url, options: .atomic)
        // Persist a container-relative path. The absolute Application Support
        // prefix can change after a device restore or app-container migration.
        return "\(projectID.uuidString)/\(fileName)"
    }

    static func load(path: String?) -> UIImage? {
        guard let url = resolvedURL(for: path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static func remove(path: String?) {
        guard let url = resolvedURL(for: path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Converts paths saved by older builds into a path that survives sandbox
    /// relocation. Invalid or escaping paths are rejected instead of being read.
    static func portablePath(_ path: String?) -> String? {
        guard let raw = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        let normalizedSeparators = raw.replacingOccurrences(of: "\\", with: "/")
        let marker = "/\(directoryName)/"
        let relative: String
        if let markerRange = normalizedSeparators.range(of: marker, options: .backwards) {
            relative = String(normalizedSeparators[markerRange.upperBound...])
        } else if normalizedSeparators.hasPrefix("/") {
            // Absolute paths outside the managed memory directory are never
            // accepted, even if they happen to exist.
            return nil
        } else {
            relative = normalizedSeparators
        }

        let components = relative.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2,
              components.allSatisfy({ $0 != "." && $0 != ".." }) else { return nil }
        return components.map(String.init).joined(separator: "/")
    }

    static func removeAll(projectID: UUID) {
        guard let root = try? memoryDirectory() else { return }
        let projectDirectory = root.appendingPathComponent(projectID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: projectDirectory)
    }

    /// Extracts a small visual signature without uploading or retaining another
    /// copy of the photo. The 64 px working image keeps this inexpensive enough
    /// to run immediately after a PhotosPicker selection.
    static func analyze(_ data: Data) -> PhotoMemoryAnalysis? {
        guard let image = UIImage(data: data),
              let source = CIImage(
                image: image,
                options: [.applyOrientationProperty: true]
              ) else { return nil }

        let extent = source.extent
        guard !extent.isNull,
              !extent.isInfinite,
              extent.width.isFinite,
              extent.height.isFinite,
              extent.width > 0,
              extent.height > 0 else { return nil }

        let normalized = source.transformed(by: CGAffineTransform(
            translationX: -extent.minX,
            y: -extent.minY
        ))
        let opaqueBackground = CIImage(color: CIColor.white)
            .cropped(to: normalized.extent)
        let opaque = normalized.composited(over: opaqueBackground)

        let maximumDimension = 64.0
        let scale = min(1, maximumDimension / max(extent.width, extent.height))
        let width = max(1, Int((extent.width * scale).rounded()))
        let height = max(1, Int((extent.height * scale).rounded()))
        let sampledImage = opaque.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let sampleBounds = CGRect(x: 0, y: 0, width: width, height: height)

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let context = CIContext(options: [
            .workingColorSpace: colorSpace,
            .cacheIntermediates: false
        ])
        context.render(
            sampledImage,
            toBitmap: &rgba,
            rowBytes: width * 4,
            bounds: sampleBounds,
            format: .RGBA8,
            colorSpace: colorSpace
        )

        let pixelCount = width * height
        guard pixelCount > 0 else { return nil }

        var redTotal = 0.0
        var greenTotal = 0.0
        var blueTotal = 0.0
        var luminances = [Double](repeating: 0, count: pixelCount)
        var buckets: [Int: ColorBucket] = [:]

        for pixel in 0..<pixelCount {
            let offset = pixel * 4
            let red = Double(rgba[offset]) / 255
            let green = Double(rgba[offset + 1]) / 255
            let blue = Double(rgba[offset + 2]) / 255
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

            redTotal += red
            greenTotal += green
            blueTotal += blue
            luminances[pixel] = luminance

            let key = (Int(rgba[offset]) >> 5) << 6
                | (Int(rgba[offset + 1]) >> 5) << 3
                | (Int(rgba[offset + 2]) >> 5)
            buckets[key, default: ColorBucket()].add(red: red, green: green, blue: blue)
        }

        let divisor = Double(pixelCount)
        let average = RGB(
            red: redTotal / divisor,
            green: greenTotal / divisor,
            blue: blueTotal / divisor
        )
        let palette = dominantPalette(from: buckets, fallback: average)

        return PhotoMemoryAnalysis(
            representativeColor: average.hex,
            palette: palette.map(\.hex),
            brightness: min(max(luminances.reduce(0, +) / divisor, 0), 1),
            edgeDensity: edgeDensity(in: luminances, width: width, height: height)
        )
    }

    static func representativeHex(from data: Data) -> String? {
        analyze(data)?.representativeColor
    }

    private static func dominantPalette(
        from buckets: [Int: ColorBucket],
        fallback: RGB
    ) -> [RGB] {
        let ranked = buckets.values.sorted { lhs, rhs in
            if lhs.paletteScore == rhs.paletteScore { return lhs.count > rhs.count }
            return lhs.paletteScore > rhs.paletteScore
        }

        var result: [RGB] = []
        for bucket in ranked {
            let candidate = bucket.average
            let isDistinct = result.allSatisfy { $0.squaredDistance(to: candidate) >= 0.025 }
            if isDistinct { result.append(candidate) }
            if result.count == 5 { break }
        }
        if result.isEmpty { result.append(fallback) }
        return result
    }

    private static func edgeDensity(
        in luminances: [Double],
        width: Int,
        height: Int
    ) -> Double {
        guard width >= 3, height >= 3 else { return 0 }
        var edgePixels = 0
        var evaluatedPixels = 0

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let topLeft = luminances[(y - 1) * width + x - 1]
                let top = luminances[(y - 1) * width + x]
                let topRight = luminances[(y - 1) * width + x + 1]
                let left = luminances[y * width + x - 1]
                let right = luminances[y * width + x + 1]
                let bottomLeft = luminances[(y + 1) * width + x - 1]
                let bottom = luminances[(y + 1) * width + x]
                let bottomRight = luminances[(y + 1) * width + x + 1]

                let gradientX = -topLeft + topRight - 2 * left + 2 * right - bottomLeft + bottomRight
                let gradientY = -topLeft - 2 * top - topRight + bottomLeft + 2 * bottom + bottomRight
                let magnitude = hypot(gradientX, gradientY) / 4
                if magnitude >= 0.16 { edgePixels += 1 }
                evaluatedPixels += 1
            }
        }

        guard evaluatedPixels > 0 else { return 0 }
        return min(max(Double(edgePixels) / Double(evaluatedPixels), 0), 1)
    }

    private static func memoryDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func resolvedURL(for path: String?) -> URL? {
        guard let relative = portablePath(path),
              let root = try? memoryDirectory().standardizedFileURL.resolvingSymlinksInPath() else { return nil }
        let candidate = relative
            .split(separator: "/")
            .reduce(root) { partial, component in
                partial.appendingPathComponent(String(component), isDirectory: false)
            }
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else { return nil }
        return candidate
    }
}

private struct RGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    var brightness: Double { (max(red, green, blue) + min(red, green, blue)) / 2 }
    var saturation: Double {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        guard maximum > 0 else { return 0 }
        return (maximum - minimum) / maximum
    }
    var hex: String {
        String(
            format: "#%02X%02X%02X",
            Int((min(max(red, 0), 1) * 255).rounded()),
            Int((min(max(green, 0), 1) * 255).rounded()),
            Int((min(max(blue, 0), 1) * 255).rounded())
        )
    }

    func squaredDistance(to other: RGB) -> Double {
        let redDifference = red - other.red
        let greenDifference = green - other.green
        let blueDifference = blue - other.blue
        return redDifference * redDifference
            + greenDifference * greenDifference
            + blueDifference * blueDifference
    }
}

private struct ColorBucket {
    var count = 0
    var redTotal = 0.0
    var greenTotal = 0.0
    var blueTotal = 0.0

    mutating func add(red: Double, green: Double, blue: Double) {
        count += 1
        redTotal += red
        greenTotal += green
        blueTotal += blue
    }

    var average: RGB {
        let divisor = Double(max(count, 1))
        return RGB(
            red: redTotal / divisor,
            green: greenTotal / divisor,
            blue: blueTotal / divisor
        )
    }

    var paletteScore: Double {
        let color = average
        return Double(count)
            * (0.78 + color.saturation * 0.42)
            * (0.9 + color.brightness * 0.1)
    }
}
