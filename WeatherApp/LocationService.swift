import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var continuation: CheckedContinuation<String, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentCity() async throws -> String {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationServiceError.servicesDisabled
        }
        guard continuation == nil else {
            throw LocationServiceError.requestInProgress
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                finish(throwing: LocationServiceError.permissionDenied)
            @unknown default:
                finish(throwing: LocationServiceError.permissionDenied)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(throwing: LocationServiceError.permissionDenied)
        case .notDetermined:
            break
        @unknown default:
            finish(throwing: LocationServiceError.permissionDenied)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(throwing: LocationServiceError.locationUnavailable)
            return
        }

        Task {
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                guard let placemark = placemarks.first,
                      let city = placemark.locality ?? placemark.subAdministrativeArea else {
                    finish(throwing: LocationServiceError.cityNotFound)
                    return
                }
                finish(returning: city)
            } catch {
                finish(throwing: LocationServiceError.geocodingFailed(error.localizedDescription))
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(throwing: LocationServiceError.locationFailed(error.localizedDescription))
    }

    private func finish(returning city: String) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: city)
    }

    private func finish(throwing error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }
}

private enum LocationServiceError: LocalizedError {
    case servicesDisabled
    case permissionDenied
    case locationUnavailable
    case cityNotFound
    case requestInProgress
    case locationFailed(String)
    case geocodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .servicesDisabled:
            return "Службы геолокации выключены. Включите их в настройках устройства."
        case .permissionDenied:
            return "Нет доступа к геолокации. Разрешите его в настройках приложения."
        case .locationUnavailable:
            return "Не удалось определить местоположение. Попробуйте ещё раз."
        case .cityNotFound:
            return "Не удалось определить город по текущему местоположению."
        case .requestInProgress:
            return "Определение местоположения уже выполняется."
        case .locationFailed(let message):
            return "Не удалось получить геопозицию: \(message)"
        case .geocodingFailed(let message):
            return "Не удалось определить город: \(message)"
        }
    }
}
