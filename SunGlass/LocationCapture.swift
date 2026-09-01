import CoreLocation
import Foundation
import Observation

enum LocationCaptureState: Equatable, Sendable {
    case idle
    case requestingAuthorization
    case locating
    case captured
    case permissionDenied
    case restricted
    case failed(String)
}

/// Requests one foreground location and discards Core Location's full-precision
/// coordinate after reducing it to an approximately 100-metre grid.
@MainActor
@Observable
final class LocationCaptureController: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var state: LocationCaptureState = .idle
    private(set) var capturedLocation: LightSessionLocation?

    @ObservationIgnored private let manager: CLLocationManager
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    /// A denied permission can be changed in this app's page in Settings.
    /// Restricted access is deliberately separate because it may be controlled
    /// by Screen Time or device management instead.
    var shouldOfferSettingsLink: Bool { state == .permissionDenied }

    var isRequesting: Bool {
        state == .requestingAuthorization || state == .locating
    }

    override init() {
        let manager = CLLocationManager()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
        self.manager = manager
        super.init()
        manager.delegate = self
    }

    deinit {
        timeoutTask?.cancel()
    }

    /// Starts a single when-in-use request. Calling this again replaces any
    /// previously captured value rather than silently reusing stale location.
    func capture() {
        guard !isRequesting else { return }
        capturedLocation = nil
        timeoutTask?.cancel()

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocation()
        case .notDetermined:
            guard Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil else {
                state = .failed("位置情報の使用目的が設定されていません。")
                return
            }
            state = .requestingAuthorization
            manager.requestWhenInUseAuthorization()
        case .denied:
            state = .permissionDenied
        case .restricted:
            state = .restricted
        @unknown default:
            state = .failed("位置情報の権限状態を確認できませんでした。")
        }
    }

    /// Stops an in-flight request and removes any location not yet committed to
    /// a `LightSession`.
    func cancel() {
        timeoutTask?.cancel()
        timeoutTask = nil
        manager.stopUpdatingLocation()
        capturedLocation = nil
        state = .idle
    }

    /// Clears the controller after a session has been saved.
    func reset() {
        timeoutTask?.cancel()
        timeoutTask = nil
        manager.stopUpdatingLocation()
        capturedLocation = nil
        state = .idle
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if state == .requestingAuthorization {
                requestLocation()
            }
        case .notDetermined:
            break
        case .denied:
            finish(with: .permissionDenied)
        case .restricted:
            finish(with: .restricted)
        @unknown default:
            finish(with: .failed("位置情報の権限状態を確認できませんでした。"))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard state == .locating else { return }
        let validLocations = locations.filter {
            $0.horizontalAccuracy >= 0
                && $0.coordinate.latitude.isFinite
                && $0.coordinate.longitude.isFinite
        }
        guard let location = validLocations.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) else {
            finish(with: .failed("現在地を取得できませんでした。もう一度お試しください。"))
            return
        }

        capturedLocation = Self.coarseLocation(from: location)
        finish(with: .captured, preserveLocation: true)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        guard isRequesting else { return }
        if let locationError = error as? CLError, locationError.code == .denied {
            let deniedState: LocationCaptureState = manager.authorizationStatus == .restricted
                ? .restricted
                : .permissionDenied
            finish(with: deniedState)
        } else {
            finish(with: .failed("現在地を取得できませんでした。通信環境を確認して、もう一度お試しください。"))
        }
    }

    private func requestLocation() {
        state = .locating
        manager.requestLocation()
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled, self.state == .locating else { return }
            self.finish(with: .failed("位置情報の取得に時間がかかっています。場所を変えて、もう一度お試しください。"))
        }
    }

    private func finish(with newState: LocationCaptureState, preserveLocation: Bool = false) {
        timeoutTask?.cancel()
        timeoutTask = nil
        manager.stopUpdatingLocation()
        if !preserveLocation { capturedLocation = nil }
        state = newState
    }

    private static func coarseLocation(from location: CLLocation) -> LightSessionLocation {
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        let metresPerLatitudeDegree = 111_320.0
        let latitudeStep = 100 / metresPerLatitudeDegree
        let roundedLatitude = (latitude / latitudeStep).rounded() * latitudeStep

        let latitudeRadians = roundedLatitude * .pi / 180
        let metresPerLongitudeDegree = max(1, metresPerLatitudeDegree * abs(cos(latitudeRadians)))
        let longitudeStep = 100 / metresPerLongitudeDegree
        let roundedLongitude = (longitude / longitudeStep).rounded() * longitudeStep

        return LightSessionLocation(
            latitude: roundedLatitude,
            longitude: roundedLongitude,
            horizontalAccuracyMeters: max(100, location.horizontalAccuracy),
            capturedAt: location.timestamp
        )
    }
}
