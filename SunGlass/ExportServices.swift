import AVFoundation
import SwiftUI
import UIKit

enum PosterFormat: String, CaseIterable, Identifiable {
    case square
    case story
    case landscape
    case a4Portrait
    case a4Landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .square: "正方形"
        case .story: "9 : 16"
        case .landscape: "16 : 9"
        case .a4Portrait: "A4 縦"
        case .a4Landscape: "A4 横"
        }
    }

    var symbol: String {
        switch self {
        case .square: "square"
        case .story: "rectangle.portrait"
        case .landscape: "rectangle"
        case .a4Portrait: "doc"
        case .a4Landscape: "doc.landscape"
        }
    }

    var renderSize: CGSize {
        switch self {
        case .square: CGSize(width: 1600, height: 1600)
        case .story: CGSize(width: 1080, height: 1920)
        case .landscape: CGSize(width: 1920, height: 1080)
        case .a4Portrait: CGSize(width: 1240, height: 1754)
        case .a4Landscape: CGSize(width: 1754, height: 1240)
        }
    }
}

enum ImageExportError: LocalizedError {
    case cannotEncodeImage
    case cannotWriteImage

    var errorDescription: String? {
        switch self {
        case .cannotEncodeImage: "PNG画像へ変換できませんでした。"
        case .cannotWriteImage: "画像ファイルを保存できませんでした。"
        }
    }
}

@MainActor
enum ImageExportService {
    static func render<V: View>(_ view: V, size: CGSize, isOpaque: Bool = true) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.proposedSize = .init(width: size.width, height: size.height)
        renderer.scale = 1
        renderer.isOpaque = isOpaque
        return renderer.uiImage
    }

    /// Writes named PNG files into a unique temporary directory so multi-layer
    /// exports keep clear filenames when handed to the system share sheet.
    static func temporaryPNGs(_ images: [(fileName: String, image: UIImage)]) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SUN-GLASS-WALLPAPER-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var urls: [URL] = []
            for item in images {
                guard let data = item.image.pngData() else {
                    throw ImageExportError.cannotEncodeImage
                }
                let url = directory.appendingPathComponent(item.fileName, isDirectory: false)
                try data.write(to: url, options: .atomic)
                urls.append(url)
            }
            return urls
        } catch let error as ImageExportError {
            try? FileManager.default.removeItem(at: directory)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw ImageExportError.cannotWriteImage
        }
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum TimelapseExportError: LocalizedError {
    case cannotCreateWriter
    case cannotStartWriter
    case cannotCreateBuffer
    case cannotRenderFrame
    case appendFailed
    case writerTimedOut

    var errorDescription: String? {
        switch self {
        case .cannotCreateWriter: "動画の書き出し準備ができませんでした。"
        case .cannotStartWriter: "動画の書き出しを開始できませんでした。"
        case .cannotCreateBuffer: "動画フレームを作成できませんでした。"
        case .cannotRenderFrame: "作品を動画フレームへ変換できませんでした。"
        case .appendFailed: "動画フレームを追加できませんでした。"
        case .writerTimedOut: "動画の書き出しが応答しませんでした。もう一度お試しください。"
        }
    }
}

/// AVAssetWriter supports cancellation while finishing, but does not declare
/// Sendable conformance. Keep that narrowly scoped operation behind a holder
/// whose only cross-task responsibility is forwarding `cancelWriting()`.
private nonisolated final class AssetWriterCancellationBox: @unchecked Sendable {
    private let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) {
        self.writer = writer
    }

    func cancel() {
        writer.cancelWriting()
    }
}

@MainActor
enum TimelapseExportService {
    /// Builds a ten-second, silent H.264 movie. Frames are rendered on the main actor
    /// because SwiftUI's ImageRenderer is UI-bound; no camera image is involved.
    static func makeVideo(
        size: CGSize = CGSize(width: 720, height: 1280),
        frameCount: Int = 80,
        framesPerSecond: Int32 = 8,
        frame: (Double) -> UIImage?
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SUN-GLASS-\(UUID().uuidString).mp4")

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            throw TimelapseExportError.cannotCreateWriter
        }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 4_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )

        guard writer.canAdd(input) else { throw TimelapseExportError.cannotCreateWriter }
        writer.add(input)
        guard writer.startWriting() else { throw TimelapseExportError.cannotStartWriter }
        writer.startSession(atSourceTime: .zero)

        // Cancellation and every throwing path after startWriting must release the writer.
        // A completed writer has already left `.writing`, so this is a no-op on success.
        defer {
            if writer.status == .writing {
                writer.cancelWriting()
            }
        }

        for index in 0..<frameCount {
            let readinessDeadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                try validateWriterIsWriting(writer)
                guard ContinuousClock.now < readinessDeadline else {
                    throw TimelapseExportError.writerTimedOut
                }
                try await Task.sleep(for: .milliseconds(8))
            }

            try Task.checkCancellation()
            try validateWriterIsWriting(writer)

            let linear = Double(index) / Double(max(frameCount - 1, 1))
            // Ease out slightly so the finished artwork gets more screen time.
            let progress = 1 - pow(1 - linear, 1.55)
            guard let image = frame(progress), let cgImage = image.cgImage else {
                throw TimelapseExportError.cannotRenderFrame
            }
            guard let pool = adaptor.pixelBufferPool,
                  let buffer = makePixelBuffer(from: cgImage, size: size, pool: pool) else {
                throw TimelapseExportError.cannotCreateBuffer
            }
            let time = CMTime(value: Int64(index), timescale: framesPerSecond)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw writer.error ?? TimelapseExportError.appendFailed
            }
            await Task.yield()
        }

        try Task.checkCancellation()
        input.markAsFinished()
        let cancellationBox = AssetWriterCancellationBox(writer)
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                writer.finishWriting { continuation.resume() }
            }
        } onCancel: {
            cancellationBox.cancel()
        }
        try Task.checkCancellation()
        if writer.status == .failed {
            throw writer.error ?? TimelapseExportError.appendFailed
        }
        guard writer.status == .completed else {
            throw TimelapseExportError.appendFailed
        }
        return url
    }

    private static func validateWriterIsWriting(_ writer: AVAssetWriter) throws {
        switch writer.status {
        case .writing:
            return
        case .failed:
            throw writer.error ?? TimelapseExportError.appendFailed
        case .cancelled:
            throw CancellationError()
        case .unknown:
            throw TimelapseExportError.cannotStartWriter
        case .completed:
            throw TimelapseExportError.appendFailed
        @unknown default:
            throw TimelapseExportError.appendFailed
        }
    }

    private static func makePixelBuffer(
        from image: CGImage,
        size: CGSize,
        pool: CVPixelBufferPool
    ) -> CVPixelBuffer? {
        var optionalBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
              let buffer = optionalBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let address = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let width = Int(size.width)
        let height = Int(size.height)
        guard let context = CGContext(
            data: address,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}
