@preconcurrency import ARKit
@preconcurrency import AVFoundation
import Combine
@preconcurrency import ReplayKit
import RealityKit
import SwiftUI
import UIKit

enum ARPlacementStatus: Equatable {
    case preparing
    case unsupported
    case cameraPermissionDenied
    case searchingPlane
    case planeNotFound
    case placed
    case simulatorPreview
    case interrupted
    case failed(String)

    var canCapture: Bool {
        self == .placed || self == .simulatorPreview
    }
}

struct ARShareSnapshot: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ARUserNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Shared state and user actions for the SwiftUI chrome around RealityKit.
@MainActor
final class ARExperienceController: NSObject, ObservableObject, RPPreviewViewControllerDelegate {
    @Published fileprivate(set) var status: ARPlacementStatus = .preparing
    @Published fileprivate(set) var isRecording = false
    @Published var shareSnapshot: ARShareSnapshot?
    @Published var notice: ARUserNotice?

    fileprivate weak var arView: ARView?
    fileprivate var placeInFrontHandler: (() -> Void)?
    fileprivate var addAnotherHandler: (() -> Void)?
    fileprivate var retrySessionHandler: (() -> Void)?

    var canCapture: Bool { status.canCapture }

    func captureSnapshot() {
        guard let arView, canCapture else {
            notice = ARUserNotice(title: "まだ撮影できません", message: "作品を配置してから撮影してください。")
            return
        }
        arView.snapshot(saveToHDR: false) { [weak self] image in
            guard let self else { return }
            guard let image else {
                self.notice = ARUserNotice(title: "撮影できませんでした", message: "少し待ってから、もう一度お試しください。")
                return
            }
            self.shareSnapshot = ARShareSnapshot(image: image)
        }
    }

    func placeInFront() {
        placeInFrontHandler?()
    }

    func addAnother() {
        addAnotherHandler?()
    }

    func retrySession() {
        retrySessionHandler?()
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard canCapture else {
            notice = ARUserNotice(title: "まだ録画できません", message: "作品を配置してから録画してください。")
            return
        }
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            notice = ARUserNotice(
                title: "録画を利用できません",
                message: "画面収録中、AirPlay使用中、またはSimulatorではAR動画を録画できません。"
            )
            return
        }
        recorder.isMicrophoneEnabled = false
        recorder.startRecording { [weak self] error in
            guard let self else { return }
            if let error {
                self.notice = ARUserNotice(title: "録画を開始できませんでした", message: error.localizedDescription)
            } else {
                self.isRecording = true
            }
        }
    }

    private func stopRecording() {
        let recorder = RPScreenRecorder.shared()
        recorder.stopRecording { [weak self] preview, error in
            guard let self else { return }
            self.isRecording = false
            if let error {
                self.notice = ARUserNotice(title: "録画を保存できませんでした", message: error.localizedDescription)
                return
            }
            guard let preview else {
                self.notice = ARUserNotice(title: "録画がありません", message: "短すぎる録画はプレビューを作成できないことがあります。")
                return
            }
            preview.previewControllerDelegate = self
            self.present(preview)
        }
    }

    private func present(_ preview: RPPreviewViewController) {
        guard let root = arView?.window?.rootViewController else {
            notice = ARUserNotice(title: "プレビューを開けませんでした", message: "もう一度録画をお試しください。")
            return
        }
        topViewController(from: root).present(preview, animated: true)
    }

    private func topViewController(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigation = controller as? UINavigationController, let visible = navigation.visibleViewController {
            return topViewController(from: visible)
        }
        if let tab = controller as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(from: selected)
        }
        return controller
    }

    func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        previewController.dismiss(animated: true)
    }
}

/// Places the project's actual recorded fragments on a detected plane.
/// Theme geometry is only added as a deterministic fallback while a project has
/// too few recorded fragments to read as a complete panel.
struct ARPlacementView: UIViewRepresentable {
    var themeColors: [Color]
    var recordedFacets: [RecordedLightFacet] = []
    var artworkSeed = 0
    var progress: Double
    var automaticallyPlacesOnFirstPlane = true
    var controller: ARExperienceController

    func makeCoordinator() -> Coordinator {
        Coordinator(
            facets: makeARFacets(),
            progress: progress,
            automaticallyPlacesOnFirstPlane: automaticallyPlacesOnFirstPlane,
            controller: controller
        )
    }

    func makeUIView(context: Context) -> ARView {
#if targetEnvironment(simulator)
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.backgroundColor = UIColor(red: 0.035, green: 0.065, blue: 0.12, alpha: 1)
        context.coordinator.connect(to: arView)
        context.coordinator.placeSimulatorPreview()
#else
        let supportsAR = ARWorldTrackingConfiguration.isSupported
        let arView = ARView(
            frame: .zero,
            cameraMode: supportsAR ? .ar : .nonAR,
            automaticallyConfigureSession: false
        )
        if !supportsAR {
            arView.backgroundColor = UIColor(red: 0.035, green: 0.065, blue: 0.12, alpha: 1)
        }
        context.coordinator.connect(to: arView)
        context.coordinator.prepareSession()
#endif
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.update(
            facets: makeARFacets(),
            progress: progress,
            automaticallyPlacesOnFirstPlane: automaticallyPlacesOnFirstPlane
        )
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.disconnect(from: uiView)
        uiView.session.pause()
    }

    @MainActor
    private func makeARFacets() -> [ARFacet] {
        let actual = recordedFacets.map(ARFacet.init)
        let minimumFacetCount = 28
        guard actual.count < minimumFacetCount else {
            return evenlySampled(actual, limit: 240)
        }

        let palette = themeColors.isEmpty
            ? [UIColor.systemCyan, .systemBlue, .systemYellow, .systemPink]
            : themeColors.map(UIColor.init)
        var result = actual
        result.reserveCapacity(minimumFacetCount)
        for index in actual.count..<minimumFacetCount {
            result.append(ARFacet.fallback(index: index, total: minimumFacetCount, seed: artworkSeed, palette: palette))
        }
        return result
    }

    private func evenlySampled<Element>(_ values: [Element], limit: Int) -> [Element] {
        guard values.count > limit, limit > 1 else { return values }
        return (0..<limit).map { index in
            let position = Double(index) * Double(values.count - 1) / Double(limit - 1)
            return values[Int(position.rounded())]
        }
    }

    @MainActor
    final class Coordinator: NSObject, ARSessionDelegate, UIGestureRecognizerDelegate {
        private weak var arView: ARView?
        private var facets: [ARFacet]
        private var facetSignature: Int
        private var progress: Double
        private var automaticallyPlacesOnFirstPlane: Bool
        private let controller: ARExperienceController
        private var anchor: AnchorEntity?
        private var placedAnchors: [AnchorEntity] = []
        private var panel: Entity?
        private var nodes: [ARFacetNode] = []
        private var hasPlacedPanel = false
        private var scaleAtGestureStart: SIMD3<Float> = .one
        private var orientationAtGestureStart = simd_quatf()
        private var planeSearchTask: Task<Void, Never>?
        private var meshCache: [String: MeshResource] = [:]

        fileprivate init(
            facets: [ARFacet],
            progress: Double,
            automaticallyPlacesOnFirstPlane: Bool,
            controller: ARExperienceController
        ) {
            self.facets = facets
            self.facetSignature = ARFacet.signature(for: facets)
            self.progress = min(max(progress, 0), 1)
            self.automaticallyPlacesOnFirstPlane = automaticallyPlacesOnFirstPlane
            self.controller = controller
        }

        func connect(to arView: ARView) {
            self.arView = arView
            controller.arView = arView
            controller.placeInFrontHandler = { [weak self] in self?.placeInFrontOfCamera() }
            controller.addAnotherHandler = { [weak self] in self?.placeInFrontOfCamera(preservingExisting: true) }
            controller.retrySessionHandler = { [weak self] in self?.prepareSession() }
            arView.session.delegate = self
            arView.session.delegateQueue = .main

            let tap = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(didPinch(_:)))
            let rotation = UIRotationGestureRecognizer(target: self, action: #selector(didRotate(_:)))
            pinch.delegate = self
            rotation.delegate = self
            arView.addGestureRecognizer(tap)
            arView.addGestureRecognizer(pinch)
            arView.addGestureRecognizer(rotation)
        }

        func disconnect(from arView: ARView) {
            planeSearchTask?.cancel()
            if controller.arView === arView { controller.arView = nil }
            controller.placeInFrontHandler = nil
            controller.addAnotherHandler = nil
            controller.retrySessionHandler = nil
        }

        func prepareSession() {
#if targetEnvironment(simulator)
            return
#else
            guard ARWorldTrackingConfiguration.isSupported else {
                controller.status = .unsupported
                placeSimulatorPreview()
                return
            }

            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                runWorldTrackingSession()
            case .notDetermined:
                controller.status = .preparing
                AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                    Task { @MainActor in
                        guard let self else { return }
                        if allowed {
                            self.runWorldTrackingSession()
                        } else {
                            self.controller.status = .cameraPermissionDenied
                        }
                    }
                }
            case .denied, .restricted:
                controller.status = .cameraPermissionDenied
            @unknown default:
                controller.status = .cameraPermissionDenied
            }
#endif
        }

        private func runWorldTrackingSession() {
            guard let arView else { return }
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal, .vertical]
            configuration.isLightEstimationEnabled = true
            configuration.environmentTexturing = .automatic
            controller.status = .searchingPlane
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            schedulePlaneHint()
        }

        private func schedulePlaneHint() {
            planeSearchTask?.cancel()
            planeSearchTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled, let self, !self.hasPlacedPanel else { return }
                self.controller.status = .planeNotFound
            }
        }

        fileprivate func update(facets: [ARFacet], progress: Double, automaticallyPlacesOnFirstPlane: Bool) {
            let newSignature = ARFacet.signature(for: facets)
            let geometryChanged = newSignature != facetSignature
            self.facets = facets
            facetSignature = newSignature
            self.progress = min(max(progress, 0), 1)
            self.automaticallyPlacesOnFirstPlane = automaticallyPlacesOnFirstPlane

            if geometryChanged, let panel {
                panel.removeFromParent()
                let replacement = makePanel()
                anchor?.addChild(replacement)
                self.panel = replacement
            } else {
                updatePieceMaterials()
            }
        }

        func placeSimulatorPreview() {
            var transform = matrix_identity_float4x4
            transform.columns.3 = SIMD4<Float>(0, -0.12, -1.0, 1)
            transform = transform * simd_float4x4(simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]))
            placePanel(at: transform)
#if targetEnvironment(simulator)
            controller.status = .simulatorPreview
#endif
        }

        @objc private func didTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView else { return }
            let point = recognizer.location(in: arView)
            let result = arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .any).first
                ?? arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first
            guard let result else {
                controller.status = .planeNotFound
                return
            }
            placePanel(at: result.worldTransform)
        }

        @objc private func didPinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let panel else { return }
            if recognizer.state == .began { scaleAtGestureStart = panel.scale }
            let factor = Float(recognizer.scale)
            let requested = scaleAtGestureStart.x * factor
            let clamped = min(max(requested, 0.3), 2.5)
            panel.scale = SIMD3<Float>(repeating: clamped)
        }

        @objc private func didRotate(_ recognizer: UIRotationGestureRecognizer) {
            guard let panel else { return }
            if recognizer.state == .began { orientationAtGestureStart = panel.orientation }
            let turn = simd_quatf(angle: -Float(recognizer.rotation), axis: [0, 1, 0])
            panel.orientation = orientationAtGestureStart * turn
        }

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private func placeInFrontOfCamera(preservingExisting: Bool = false) {
            guard let arView else { return }
            var offset = matrix_identity_float4x4
            offset.columns.3 = SIMD4<Float>(0, 0, -1.05, 1)
            let faceCamera = simd_float4x4(simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
            placePanel(
                at: arView.cameraTransform.matrix * offset * faceCamera,
                preservingExisting: preservingExisting
            )
        }

        private func placePanel(at transform: simd_float4x4, preservingExisting: Bool = false) {
            guard let arView else { return }
            if !preservingExisting, let anchor {
                arView.scene.removeAnchor(anchor)
                placedAnchors.removeAll { $0 === anchor }
            }
            if !preservingExisting { nodes.removeAll(keepingCapacity: true) }

            let newAnchor = AnchorEntity(world: transform)
            let newPanel = makePanel()
            newAnchor.addChild(newPanel)
            arView.scene.addAnchor(newAnchor)
            placedAnchors.append(newAnchor)
            anchor = newAnchor
            panel = newPanel
            hasPlacedPanel = true
            planeSearchTask?.cancel()
#if !targetEnvironment(simulator)
            controller.status = .placed
#endif
        }

        private func makePanel() -> Entity {
            let root = Entity()
            root.name = "recorded-stained-glass-panel"
            let width: Float = 0.72
            let height: Float = 0.90

            var backingMaterial = SimpleMaterial(
                color: UIColor(red: 0.94, green: 0.97, blue: 1, alpha: 0.07),
                roughness: 0.1,
                isMetallic: false
            )
            backingMaterial.faceCulling = .none
            let backing = ModelEntity(
                mesh: .generateBox(width: width, height: 0.003, depth: height, cornerRadius: 0.018),
                materials: [backingMaterial]
            )
            backing.position.y = -0.009
            root.addChild(backing)

            addOuterFrame(to: root, width: width, height: height)

            let leadMaterial = SimpleMaterial(
                color: UIColor(white: 0.035, alpha: 0.96),
                roughness: 0.38,
                isMetallic: true
            )

            for (index, facet) in facets.enumerated() {
                let mesh = mesh(for: facet.shape)
                let baseScale = 0.085 * min(max(facet.scale, 0.34), 2.15)
                let x = (facet.position.x - 0.5) * (width - 0.07)
                let z = (facet.position.y - 0.5) * (height - 0.07)
                let orientation = simd_quatf(angle: -facet.rotation, axis: [0, 1, 0])

                let lead = ModelEntity(mesh: mesh, materials: [leadMaterial])
                lead.name = "recorded-lead-\(index)"
                lead.position = [x, 0.003, z]
                lead.orientation = orientation
                lead.scale = [baseScale * 1.14, 1, baseScale * 1.14]
                root.addChild(lead)

                let piece = ModelEntity(
                    mesh: mesh,
                    materials: [pieceMaterial(for: facet)]
                )
                piece.name = "recorded-glass-facet-\(index)-\(facet.shape.rawValue)"
                piece.position = [x, 0.008 + Float(index % 4) * 0.0008, z]
                piece.orientation = orientation
                piece.scale = [baseScale, 1, baseScale]
                root.addChild(piece)

                var projection: ModelEntity?
                if index % 2 == 0 {
                    let projected = ModelEntity(
                        mesh: mesh,
                        materials: [projectionMaterial(for: facet)]
                    )
                    projected.name = "light-projection-\(index)"
                    projected.position = [x + 0.018, -0.006, z + 0.022]
                    projected.orientation = orientation
                    let spread = baseScale * (1.22 + min(max(facet.emission, 0), 1) * 0.35)
                    projected.scale = [spread, 1, spread]
                    root.addChild(projected)
                    projection = projected
                }

                nodes.append(ARFacetNode(piece: piece, projection: projection, facet: facet))
            }
            return root
        }

        private func addOuterFrame(to root: Entity, width: Float, height: Float) {
            let material = SimpleMaterial(color: UIColor(white: 0.045, alpha: 0.98), roughness: 0.34, isMetallic: true)
            let thickness: Float = 0.018
            for x in [-width / 2, width / 2] {
                let rail = ModelEntity(
                    mesh: .generateBox(width: thickness, height: 0.018, depth: height + thickness, cornerRadius: 0.004),
                    materials: [material]
                )
                rail.position = [x, 0.008, 0]
                root.addChild(rail)
            }
            for z in [-height / 2, height / 2] {
                let rail = ModelEntity(
                    mesh: .generateBox(width: width + thickness, height: 0.018, depth: thickness, cornerRadius: 0.004),
                    materials: [material]
                )
                rail.position = [0, 0.008, z]
                root.addChild(rail)
            }
        }

        private func mesh(for shape: RecordedLightFacet.Shape) -> MeshResource {
            if let cached = meshCache[shape.rawValue] { return cached }
            let boundary: [SIMD2<Float>] = switch shape {
            case .shard:
                [[-0.48, -0.42], [0.02, -0.50], [0.48, -0.12], [0.22, 0.48], [-0.18, 0.34]]
            case .triangle:
                [[-0.48, 0.42], [0.02, -0.50], [0.48, 0.38]]
            case .quadrilateral:
                [[-0.48, -0.34], [0.34, -0.48], [0.48, 0.30], [-0.28, 0.48]]
            case .arc:
                (0...12).map { index in
                    let angle = Float.pi + Float(index) / 12 * Float.pi
                    return SIMD2<Float>(cos(angle) * 0.5, sin(angle) * 0.5 + 0.2)
                }
            case .circle:
                (0..<20).map { index in
                    let angle = Float(index) / 20 * Float.pi * 2
                    return SIMD2<Float>(cos(angle) * 0.5, sin(angle) * 0.5)
                }
            }

            let center = boundary.reduce(SIMD2<Float>.zero, +) / Float(boundary.count)
            let positions = [SIMD3<Float>(center.x, 0, center.y)] + boundary.map { SIMD3<Float>($0.x, 0, $0.y) }
            var indices: [UInt32] = []
            for index in boundary.indices {
                indices.append(contentsOf: [0, UInt32(index + 1), UInt32((index + 1) % boundary.count + 1)])
            }

            var descriptor = MeshDescriptor(name: "sun-glass-\(shape.rawValue)")
            descriptor.positions = MeshBuffer(positions)
            descriptor.normals = MeshBuffer(Array(repeating: SIMD3<Float>(0, 1, 0), count: positions.count))
            descriptor.primitives = .triangles(indices)
            let resource = (try? MeshResource.generate(from: [descriptor]))
                ?? .generateBox(width: 1, height: 0.005, depth: 1, cornerRadius: 0.04)
            meshCache[shape.rawValue] = resource
            return resource
        }

        private func updatePieceMaterials() {
            for node in nodes {
                node.piece.model?.materials = [pieceMaterial(for: node.facet)]
                node.projection?.model?.materials = [projectionMaterial(for: node.facet)]
            }
        }

        private func pieceMaterial(for facet: ARFacet) -> PhysicallyBasedMaterial {
            let revealed = facet.revealProgress <= Float(progress) + 0.0001
            let alpha = revealed ? min(max(facet.opacity, 0.18), 0.94) : 0.035
            let color = facet.color.withAlphaComponent(1)
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: color)
            material.roughness = 0.07
            material.metallic = 0.02
            material.clearcoat = 0.42
            material.clearcoatRoughness = 0.08
            material.emissiveColor = .init(color: revealed ? facet.color : .black)
            material.emissiveIntensity = revealed ? 0.22 + facet.emission * 1.8 : 0
            material.faceCulling = .none
            material.blending = PhysicallyBasedMaterial.Blending.transparent(
                opacity: PhysicallyBasedMaterial.Opacity(scale: alpha)
            )
            return material
        }

        private func projectionMaterial(for facet: ARFacet) -> UnlitMaterial {
            let revealed = facet.revealProgress <= Float(progress) + 0.0001
            let alpha = revealed ? min(0.22, 0.055 + facet.emission * 0.22) : 0
            var material = UnlitMaterial(color: facet.color.withAlphaComponent(1))
            material.blending = PhysicallyBasedMaterial.Blending.transparent(
                opacity: PhysicallyBasedMaterial.Opacity(scale: alpha)
            )
            material.writesDepth = false
            return material
        }

        nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            guard let plane = anchors.compactMap({ $0 as? ARPlaneAnchor }).first else { return }
            let planeTransform = plane.transform
            let center = plane.center
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.hasPlacedPanel { self.controller.status = .searchingPlane }
                guard self.automaticallyPlacesOnFirstPlane, !self.hasPlacedPanel else { return }
                var centerTransform = matrix_identity_float4x4
                centerTransform.columns.3 = SIMD4<Float>(center.x, center.y, center.z, 1)
                self.placePanel(at: planeTransform * centerTransform)
            }
        }

        nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
            let message = error.localizedDescription
            Task { @MainActor [weak self] in
                self?.controller.status = .failed(message)
            }
        }

        nonisolated func sessionWasInterrupted(_ session: ARSession) {
            Task { @MainActor [weak self] in
                self?.controller.status = .interrupted
            }
        }

        nonisolated func sessionInterruptionEnded(_ session: ARSession) {
            Task { @MainActor [weak self] in
                self?.prepareSession()
            }
        }
    }
}

private struct ARFacet {
    let position: SIMD2<Float>
    let rotation: Float
    let scale: Float
    let color: UIColor
    let opacity: Float
    let emission: Float
    let revealProgress: Float
    let shape: RecordedLightFacet.Shape

    @MainActor
    init(_ facet: RecordedLightFacet) {
        position = [Float(facet.position.x), Float(facet.position.y)]
        rotation = Float(facet.rotation)
        scale = Float(facet.scale)
        color = UIColor(facet.color)
        opacity = Float(facet.opacity)
        emission = Float(facet.emission)
        revealProgress = Float(facet.revealProgress)
        shape = facet.shape
    }

    static func fallback(index: Int, total: Int, seed: Int, palette: [UIColor]) -> ARFacet {
        let mixed = UInt64(bitPattern: Int64(seed &* 31 &+ index &* 1_103))
        let phase = Float(mixed % 10_000) / 10_000 * Float.pi * 2
        let fraction = (Float(index) + 0.7) / Float(max(total, 1))
        let radius = sqrt(fraction) * 0.43
        let goldenAngle = Float.pi * (3 - sqrt(5))
        let angle = Float(index) * goldenAngle + phase * 0.12
        let shapes: [RecordedLightFacet.Shape] = [.shard, .triangle, .quadrilateral, .arc, .circle]
        let safePalette = palette.isEmpty ? [UIColor.systemCyan] : palette
        return ARFacet(
            position: [0.5 + cos(angle) * radius, 0.5 + sin(angle) * radius],
            rotation: angle + phase,
            scale: 0.62 + Float((mixed >> 8) % 55) / 100,
            color: safePalette[(index + abs(seed)) % safePalette.count],
            opacity: 0.58 + Float(index % 4) * 0.07,
            emission: 0.08 + Float(index % 5) * 0.035,
            revealProgress: Float(index + 1) / Float(max(total, 1)),
            shape: shapes[(index + abs(seed)) % shapes.count]
        )
    }

    private init(
        position: SIMD2<Float>,
        rotation: Float,
        scale: Float,
        color: UIColor,
        opacity: Float,
        emission: Float,
        revealProgress: Float,
        shape: RecordedLightFacet.Shape
    ) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.color = color
        self.opacity = opacity
        self.emission = emission
        self.revealProgress = revealProgress
        self.shape = shape
    }

    static func signature(for facets: [ARFacet]) -> Int {
        var hasher = Hasher()
        hasher.combine(facets.count)
        for facet in facets {
            hasher.combine(facet.position.x.bitPattern)
            hasher.combine(facet.position.y.bitPattern)
            hasher.combine(facet.rotation.bitPattern)
            hasher.combine(facet.scale.bitPattern)
            hasher.combine(facet.opacity.bitPattern)
            hasher.combine(facet.emission.bitPattern)
            hasher.combine(facet.revealProgress.bitPattern)
            hasher.combine(facet.shape.rawValue)
            hasher.combine(facet.color.description)
        }
        return hasher.finalize()
    }
}

private struct ARFacetNode {
    let piece: ModelEntity
    let projection: ModelEntity?
    let facet: ARFacet
}
