import ARKit
import AVFoundation
import Foundation
import Observation
import RealityKit
import SwiftUI

/// The intentionally qualitative brightness scale shown to people collecting light.
enum LightLevel: Int, CaseIterable, Codable, Sendable {
    case dark = 1
    case soft
    case bright
    case strong
    case veryStrong

    var label: String {
        switch self {
        case .dark: "暗い"
        case .soft: "柔らかな光"
        case .bright: "明るい"
        case .strong: "強い光"
        case .veryStrong: "とても強い光"
        }
    }
}

enum CameraAuthorization: String, Codable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

enum DeviceThermalLevel: Int, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    var label: String {
        switch self {
        case .nominal: "正常"
        case .fair: "やや高温"
        case .serious: "高温"
        case .critical: "非常に高温"
        }
    }

    var shouldShowWarning: Bool { self == .serious || self == .critical }
    var shouldStopMeasurement: Bool { self == .serious || self == .critical }
}

enum LightMeterState: Equatable, Sendable {
    case idle
    case requestingPermission
    case running
    case interrupted
    case completed
    case permissionDenied
    case unavailable
    case failed(String)
}

enum LightMeasurementEndReason: String, Codable, Sendable {
    case manual
    case maximumDuration
    case thermalProtection
}

/// A value-only summary. No camera frame or image data is retained by this component.
struct LightMeasurement: Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    /// Wall-clock time while the meter was actively running. This is always capped at 30 seconds.
    let elapsedDuration: TimeInterval
    /// Only intervals continuously backed by accepted light samples. Points are based on this value.
    let duration: TimeInterval
    let averageIntensity: Double
    let maximumIntensity: Double
    let averageColorTemperature: Double
    let acceptedSampleCount: Int
    let rejectedSampleCount: Int
    let firstAcceptedSampleAt: Date?
    let lastAcceptedSampleAt: Date?
    let sampleDensity: Double
    let thermalLevel: DeviceThermalLevel
    let endReason: LightMeasurementEndReason
}

/// A compact, value-only checkpoint. Camera frames never leave ARKit and are never persisted.
struct LightMeasurementDraft: Codable, Equatable, Sendable {
    let id: UUID
    let projectID: UUID
    let startedAt: Date
    var updatedAt: Date
    var endedAt: Date?
    var elapsedDuration: TimeInterval
    var validSampleDuration: TimeInterval
    var intensityTotal: Double
    var temperatureTotal: Double
    var maximumIntensity: Double
    var ambientIntensity: Double
    var colorTemperature: Double
    var acceptedSampleCount: Int
    var rejectedSampleCount: Int
    var firstAcceptedSampleAt: Date?
    var lastAcceptedSampleAt: Date?
    var thermalLevel: DeviceThermalLevel
    var endReason: LightMeasurementEndReason?

    var isCompleted: Bool { endedAt != nil && endReason != nil }

    var isStructurallyValid: Bool {
        let finiteValues = [
            elapsedDuration,
            validSampleDuration,
            intensityTotal,
            temperatureTotal,
            maximumIntensity,
            ambientIntensity,
            colorTemperature
        ]
        guard finiteValues.allSatisfy(\.isFinite),
              (0...30.05).contains(elapsedDuration),
              (0...elapsedDuration).contains(validSampleDuration),
              acceptedSampleCount >= 0,
              rejectedSampleCount >= 0,
              intensityTotal >= 0,
              temperatureTotal >= 0,
              maximumIntensity >= 0,
              updatedAt >= startedAt else { return false }
        return acceptedSampleCount > 0 || (intensityTotal == 0 && temperatureTotal == 0)
    }
}

/// Drafts are stored separately from project data so frequent checkpoints cannot endanger the gallery file.
@MainActor
enum LightMeasurementDraftStore {
    private static let maximumDraftAge: TimeInterval = 12 * 60 * 60

    static func load(projectID: UUID, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> LightMeasurementDraft? {
        let url = fileURL(projectID: projectID)
        guard let data = try? Data(contentsOf: url),
              let draft = try? JSONDecoder().decode(LightMeasurementDraft.self, from: data),
              draft.projectID == projectID,
              draft.isStructurallyValid,
              calendar.isDate(draft.startedAt, inSameDayAs: now),
              now.timeIntervalSince(draft.updatedAt) >= -300,
              now.timeIntervalSince(draft.updatedAt) <= maximumDraftAge else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return draft
    }

    @discardableResult
    static func save(_ draft: LightMeasurementDraft) -> Bool {
        guard draft.isStructurallyValid else { return false }
        do {
            let url = fileURL(projectID: draft.projectID)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(draft)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func remove(projectID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(projectID: projectID))
    }

    private static func fileURL(projectID: UUID) -> URL {
        let fileManager = FileManager.default
        let root = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let bundleDirectory = root.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "SunGlass",
            isDirectory: true
        )
        return bundleDirectory
            .appendingPathComponent("LightMeasurementDrafts", isDirectory: true)
            .appendingPathComponent("\(projectID.uuidString).json")
    }
}

@MainActor
@Observable
final class LightMeterController: NSObject, ARSessionDelegate {
    private struct Sample {
        let timestamp: TimeInterval
        let intensity: Double
        let colorTemperature: Double
    }

    let session = ARSession()
    let maximumDuration: TimeInterval
    let movingAverageWindow: TimeInterval
    let intensityCalibrationScale: Double
    let draftProjectID: UUID?

    private(set) var state: LightMeterState = .idle
    private(set) var cameraAuthorization: CameraAuthorization
    private(set) var ambientIntensity: Double = 0
    private(set) var colorTemperature: Double = 6_500
    private(set) var averageIntensity: Double = 0
    private(set) var maximumIntensity: Double = 0
    private(set) var averageColorTemperature: Double = 6_500
    /// Wall-clock time spent actively measuring. Used only for the safety timeout and UI.
    private(set) var duration: TimeInterval = 0
    /// Accepted, continuous sample intervals. This is the only duration eligible for points.
    private(set) var validSampleDuration: TimeInterval = 0
    private(set) var acceptedSampleCount = 0
    private(set) var rejectedSampleCount = 0
    private(set) var firstAcceptedSampleAt: Date?
    private(set) var lastAcceptedSampleAt: Date?
    private(set) var recoveredDraft = false
    private(set) var thermalLevel: DeviceThermalLevel
    private(set) var latestMeasurement: LightMeasurement?

    @ObservationIgnored private var measurementID = UUID()
    @ObservationIgnored private var windowSamples: [Sample] = []
    @ObservationIgnored private var intensityTotal: Double = 0
    @ObservationIgnored private var temperatureTotal: Double = 0
    @ObservationIgnored private var consecutiveOutliers = 0
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var segmentStartedAt: Date?
    @ObservationIgnored private var accumulatedElapsedDuration: TimeInterval = 0
    @ObservationIgnored private var lastAcceptedSampleTimestamp: TimeInterval?
    @ObservationIgnored private var lastDraftWriteAt: Date?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var demoTask: Task<Void, Never>?

    var isRunning: Bool { state == .running || state == .interrupted }
    var lightLevel: LightLevel { Self.level(for: ambientIntensity) }
    var lightLevelValue: Int { lightLevel.rawValue }
    var lightLevelLabel: String { lightLevel.label }
    var thermalLabel: String { thermalLevel.label }
    var shouldShowThermalWarning: Bool { thermalLevel.shouldShowWarning }
    var remainingDuration: TimeInterval { max(0, maximumDuration - duration) }
    var estimatedLightPoints: Double { averageIntensity * validSampleDuration }
    var sampleDensity: Double {
        guard duration > 0 else { return 0 }
        return Double(acceptedSampleCount) / duration
    }

    var lightColorLabel: String {
        switch colorTemperature {
        case ..<4_000: "暖かな光"
        case ..<5_700: "自然な光"
        default: "涼やかな光"
        }
    }

    init(
        maximumDuration: TimeInterval = 30,
        movingAverageWindow: TimeInterval = 3,
        intensityCalibrationScale: Double = 1,
        draftProjectID: UUID? = nil
    ) {
        self.maximumDuration = min(30, max(1, maximumDuration))
        self.movingAverageWindow = max(0.5, movingAverageWindow)
        self.intensityCalibrationScale = min(max(intensityCalibrationScale, 0.25), 4)
        self.draftProjectID = draftProjectID
        self.cameraAuthorization = Self.currentCameraAuthorization
        self.thermalLevel = Self.currentThermalLevel
        super.init()
        session.delegate = self
        session.delegateQueue = .main
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateDidChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Requests camera permission if needed, then starts a maximum 30-second AR session.
    func start(resuming draft: LightMeasurementDraft? = nil) {
        guard state != .running, state != .interrupted, state != .requestingPermission else { return }
        resetMeasurements(discardDraft: draft == nil)
        if let draft, restore(draft) {
            recoveredDraft = true
            if draft.isCompleted {
                state = .completed
                return
            }
        }
        thermalLevel = Self.currentThermalLevel
        guard !thermalLevel.shouldStopMeasurement else {
            state = .failed("端末が熱くなっています。日陰へ移動し、温度が下がってからもう一度お試しください。")
            return
        }

#if targetEnvironment(simulator)
        cameraAuthorization = .authorized
        beginDemoSession()
#else
        cameraAuthorization = Self.currentCameraAuthorization
        switch cameraAuthorization {
        case .authorized:
            beginARSession()
        case .notDetermined:
            guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else {
                state = .failed("Info.plist にカメラ使用目的の説明がありません。")
                return
            }
            state = .requestingPermission
            permissionTask = Task { @MainActor [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard let self, !Task.isCancelled else { return }
                self.cameraAuthorization = granted ? .authorized : .denied
                granted ? self.beginARSession() : (self.state = .permissionDenied)
            }
        case .denied, .restricted:
            state = .permissionDenied
        }
#endif
    }

    func stop() {
        finish(reason: .manual)
    }

    func cancel() {
        clockTask?.cancel()
        permissionTask?.cancel()
        demoTask?.cancel()
        session.pause()
        resetMeasurements(discardDraft: true)
        state = .idle
    }

    func discardDraft() {
        guard let draftProjectID else { return }
        LightMeasurementDraftStore.remove(projectID: draftProjectID)
        lastDraftWriteAt = nil
    }

    private func beginARSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            state = .unavailable
            return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        configuration.worldAlignment = .gravity
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        beginTiming()
    }

    private func beginDemoSession() {
        beginTiming()
        demoTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.isRunning {
                let t = self.duration
                let intensity = 1_050 + sin(t * 0.8) * 520 + sin(t * 2.3) * 90
                let temperature = 5_400 + sin(t * 0.35) * 1_150
                self.consume(intensity: intensity, colorTemperature: temperature, timestamp: t)
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    private func beginTiming() {
        let now = Date()
        if startedAt == nil { startedAt = now }
        accumulatedElapsedDuration = duration
        segmentStartedAt = now
        state = .running
        checkpointDraft(force: true)
        clockTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.isRunning {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                self.updateClock()
            }
        }
    }

    private func updateClock() {
        guard let segmentStartedAt else { return }
        duration = min(
            maximumDuration,
            accumulatedElapsedDuration + Date().timeIntervalSince(segmentStartedAt)
        )
        checkpointDraft()
        if duration >= maximumDuration {
            finish(reason: .maximumDuration)
        }
    }

    private func finish(reason: LightMeasurementEndReason) {
        guard let startedAt, isRunning else {
            if state == .requestingPermission { cancel() }
            return
        }
        updateClockWithoutFinishing()
        clockTask?.cancel()
        permissionTask?.cancel()
        demoTask?.cancel()
        session.pause()

        let endedAt = Date()
        latestMeasurement = LightMeasurement(
            id: measurementID,
            startedAt: startedAt,
            endedAt: endedAt,
            elapsedDuration: duration,
            duration: min(validSampleDuration, duration),
            averageIntensity: averageIntensity,
            maximumIntensity: maximumIntensity,
            averageColorTemperature: averageColorTemperature,
            acceptedSampleCount: acceptedSampleCount,
            rejectedSampleCount: rejectedSampleCount,
            firstAcceptedSampleAt: firstAcceptedSampleAt,
            lastAcceptedSampleAt: lastAcceptedSampleAt,
            sampleDensity: sampleDensity,
            thermalLevel: thermalLevel,
            endReason: reason
        )
        accumulatedElapsedDuration = duration
        segmentStartedAt = nil
        lastAcceptedSampleTimestamp = nil
        checkpointDraft(force: true, endedAt: endedAt, endReason: reason)
        state = .completed
    }

    private func updateClockWithoutFinishing() {
        guard let segmentStartedAt else { return }
        duration = min(
            maximumDuration,
            accumulatedElapsedDuration + Date().timeIntervalSince(segmentStartedAt)
        )
    }

    private func resetMeasurements(discardDraft: Bool) {
        clockTask?.cancel()
        permissionTask?.cancel()
        demoTask?.cancel()
        if discardDraft { self.discardDraft() }
        measurementID = UUID()
        windowSamples.removeAll(keepingCapacity: true)
        intensityTotal = 0
        temperatureTotal = 0
        consecutiveOutliers = 0
        startedAt = nil
        segmentStartedAt = nil
        accumulatedElapsedDuration = 0
        lastAcceptedSampleTimestamp = nil
        lastDraftWriteAt = nil
        ambientIntensity = 0
        colorTemperature = 6_500
        averageIntensity = 0
        maximumIntensity = 0
        averageColorTemperature = 6_500
        duration = 0
        validSampleDuration = 0
        acceptedSampleCount = 0
        rejectedSampleCount = 0
        firstAcceptedSampleAt = nil
        lastAcceptedSampleAt = nil
        recoveredDraft = false
        latestMeasurement = nil
    }

    private func restore(_ draft: LightMeasurementDraft) -> Bool {
        guard let draftProjectID,
              draft.projectID == draftProjectID,
              draft.isStructurallyValid,
              draft.elapsedDuration <= maximumDuration + 0.05 else { return false }

        measurementID = draft.id
        startedAt = draft.startedAt
        duration = min(maximumDuration, draft.elapsedDuration)
        accumulatedElapsedDuration = duration
        validSampleDuration = min(duration, draft.validSampleDuration)
        intensityTotal = draft.intensityTotal
        temperatureTotal = draft.temperatureTotal
        maximumIntensity = draft.maximumIntensity
        ambientIntensity = draft.ambientIntensity
        colorTemperature = draft.colorTemperature
        acceptedSampleCount = draft.acceptedSampleCount
        rejectedSampleCount = draft.rejectedSampleCount
        firstAcceptedSampleAt = draft.firstAcceptedSampleAt
        lastAcceptedSampleAt = draft.lastAcceptedSampleAt
        thermalLevel = draft.thermalLevel
        if acceptedSampleCount > 0 {
            averageIntensity = intensityTotal / Double(acceptedSampleCount)
            averageColorTemperature = temperatureTotal / Double(acceptedSampleCount)
        }

        if let endedAt = draft.endedAt, let endReason = draft.endReason {
            latestMeasurement = LightMeasurement(
                id: measurementID,
                startedAt: draft.startedAt,
                endedAt: endedAt,
                elapsedDuration: duration,
                duration: validSampleDuration,
                averageIntensity: averageIntensity,
                maximumIntensity: maximumIntensity,
                averageColorTemperature: averageColorTemperature,
                acceptedSampleCount: acceptedSampleCount,
                rejectedSampleCount: rejectedSampleCount,
                firstAcceptedSampleAt: firstAcceptedSampleAt,
                lastAcceptedSampleAt: lastAcceptedSampleAt,
                sampleDensity: sampleDensity,
                thermalLevel: thermalLevel,
                endReason: endReason
            )
        }
        return true
    }

    private func checkpointDraft(
        force: Bool = false,
        endedAt: Date? = nil,
        endReason: LightMeasurementEndReason? = nil
    ) {
        guard let draftProjectID, let startedAt else { return }
        let now = Date()
        if !force, let lastDraftWriteAt, now.timeIntervalSince(lastDraftWriteAt) < 0.5 { return }
        let draft = LightMeasurementDraft(
            id: measurementID,
            projectID: draftProjectID,
            startedAt: startedAt,
            updatedAt: now,
            endedAt: endedAt,
            elapsedDuration: duration,
            validSampleDuration: min(validSampleDuration, duration),
            intensityTotal: intensityTotal,
            temperatureTotal: temperatureTotal,
            maximumIntensity: maximumIntensity,
            ambientIntensity: ambientIntensity,
            colorTemperature: colorTemperature,
            acceptedSampleCount: acceptedSampleCount,
            rejectedSampleCount: rejectedSampleCount,
            firstAcceptedSampleAt: firstAcceptedSampleAt,
            lastAcceptedSampleAt: lastAcceptedSampleAt,
            thermalLevel: thermalLevel,
            endReason: endReason
        )
        if LightMeasurementDraftStore.save(draft) { lastDraftWriteAt = now }
    }

    private func consume(intensity rawIntensity: Double, colorTemperature rawTemperature: Double, timestamp: TimeInterval) {
        guard isRunning else { return }
        let intensity = rawIntensity * intensityCalibrationScale
        guard intensity.isFinite, rawTemperature.isFinite,
              (10...120_000).contains(intensity), (1_000...20_000).contains(rawTemperature) else {
            rejectedSampleCount += 1
            return
        }

        if isOutlier(intensity: intensity, temperature: rawTemperature) {
            consecutiveOutliers += 1
            rejectedSampleCount += 1
            // Adapt after a sustained real lighting change while still rejecting isolated spikes.
            if consecutiveOutliers < 8 { return }
            windowSamples.removeAll(keepingCapacity: true)
        }
        consecutiveOutliers = 0

        let sample = Sample(timestamp: timestamp, intensity: intensity, colorTemperature: rawTemperature)
        windowSamples.append(sample)
        let cutoff = timestamp - movingAverageWindow
        windowSamples.removeAll { $0.timestamp < cutoff }
        if windowSamples.count > 180 { windowSamples.removeFirst(windowSamples.count - 180) }

        acceptedSampleCount += 1
        let acceptedAt = Date()
        if firstAcceptedSampleAt == nil { firstAcceptedSampleAt = acceptedAt }
        if let previousTimestamp = lastAcceptedSampleTimestamp {
            let gap = timestamp - previousTimestamp
            // A gap means ARKit was not supplying stable samples; never turn that
            // wall-clock interval into credited measurement time.
            if gap >= 0, gap <= 1 {
                validSampleDuration = min(maximumDuration, validSampleDuration + gap)
            }
        }
        lastAcceptedSampleTimestamp = timestamp
        lastAcceptedSampleAt = acceptedAt
        intensityTotal += intensity
        temperatureTotal += rawTemperature
        maximumIntensity = max(maximumIntensity, intensity)
        averageIntensity = intensityTotal / Double(acceptedSampleCount)
        averageColorTemperature = temperatureTotal / Double(acceptedSampleCount)
        ambientIntensity = windowSamples.map(\.intensity).reduce(0, +) / Double(windowSamples.count)
        colorTemperature = windowSamples.map(\.colorTemperature).reduce(0, +) / Double(windowSamples.count)
    }

    private func isOutlier(intensity: Double, temperature: Double) -> Bool {
        guard windowSamples.count >= 6 else { return false }
        let intensityValues = windowSamples.map(\.intensity)
        let temperatureValues = windowSamples.map(\.colorTemperature)
        let intensityMedian = Self.median(intensityValues)
        let temperatureMedian = Self.median(temperatureValues)
        let intensityMAD = Self.median(intensityValues.map { abs($0 - intensityMedian) })
        let temperatureMAD = Self.median(temperatureValues.map { abs($0 - temperatureMedian) })
        let intensityLimit = max(120, intensityMedian * 0.75, intensityMAD * 6)
        let temperatureLimit = max(1_500, temperatureMAD * 6)
        return abs(intensity - intensityMedian) > intensityLimit
            || abs(temperature - temperatureMedian) > temperatureLimit
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    private static func level(for intensity: Double) -> LightLevel {
        switch intensity {
        case ..<250: .dark
        case ..<650: .soft
        case ..<1_300: .bright
        case ..<2_600: .strong
        default: .veryStrong
        }
    }

    private static var currentCameraAuthorization: CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    private static var currentThermalLevel: DeviceThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .fair
        }
    }

    @objc nonisolated private func thermalStateDidChange() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.thermalLevel = Self.currentThermalLevel
            if self.thermalLevel.shouldStopMeasurement, self.isRunning {
                self.finish(reason: .thermalProtection)
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let estimate = frame.lightEstimate else { return }
        let intensity = Double(estimate.ambientIntensity)
        let temperature = Double(estimate.ambientColorTemperature)
        let timestamp = frame.timestamp
        Task { @MainActor [weak self] in
            self?.consume(intensity: intensity, colorTemperature: temperature, timestamp: timestamp)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.clockTask?.cancel()
            self.demoTask?.cancel()
            self.state = .failed(message)
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in
            guard let self, self.state == .running else { return }
            // Do not let wall-clock time continue to accrue while ARKit provides no
            // light samples. Keep the valid samples gathered up to the interruption.
            self.finish(reason: .manual)
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor [weak self] in
            guard let self, self.state == .interrupted else { return }
            self.state = .running
        }
    }
}

/// Camera/AR background for a light collection screen. It never requests snapshots or records video.
struct LightCaptureCameraView: UIViewRepresentable {
    let controller: LightMeterController

    func makeUIView(context: Context) -> ARView {
#if targetEnvironment(simulator)
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.backgroundColor = UIColor(red: 0.05, green: 0.09, blue: 0.16, alpha: 1)
#else
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = controller.session
#endif
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
#if !targetEnvironment(simulator)
        if uiView.session !== controller.session {
            uiView.session = controller.session
        }
#endif
    }
}
