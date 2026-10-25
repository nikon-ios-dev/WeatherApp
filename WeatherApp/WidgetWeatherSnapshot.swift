import Foundation
import WidgetKit

struct WidgetWeatherSnapshot: Codable {
    let city: String
    let temperature: Int
    let feelsLike: Int
    let weatherIcon: String
    let updatedAt: Date
    let timeZoneOffset: Int

    static let appGroupIdentifier = "group.com.example.WeatherApp"
    static let storageKey = "widgetWeatherSnapshot"

    static func save(_ snapshot: WidgetWeatherSnapshot) throws {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            throw WidgetSnapshotError.appGroupUnavailable
        }
        let data = try JSONEncoder().encode(snapshot)
        defaults.set(data, forKey: storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func load() -> WidgetWeatherSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    private enum WidgetSnapshotError: LocalizedError {
        case appGroupUnavailable

        var errorDescription: String? {
            "Не удалось открыть общий контейнер виджета. Проверьте App Group group.com.example.WeatherApp."
        }
    }

}

enum WeatherDisplayFormat {
    static func temperature(_ celsius: Int, unit: String) -> String {
        let value = unit == "fahrenheit"
            ? Int((Double(celsius) * 9 / 5 + 32).rounded())
            : celsius
        return "\(value)°"
    }

    static func windSpeed(_ metersPerSecond: Double, unit: String) -> String {
        let value = unit == "kilometersPerHour" ? metersPerSecond * 3.6 : metersPerSecond
        let unitLabel = unit == "kilometersPerHour" ? "км/ч" : "м/с"
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unitLabel)"
    }

    static func time(_ date: Date, timeZoneOffset: Int, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(secondsFromGMT: timeZoneOffset) ?? .current
        formatter.dateFormat = format == "twelveHour" ? "h:mm a" : "HH:mm"
        return formatter.string(from: date)
    }
}
