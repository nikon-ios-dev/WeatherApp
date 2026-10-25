import Foundation
import UserNotifications

enum RainNotificationService {
    private static let notificationIdentifier = "weather-rain-alert"

    static func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        )
    }

    static func scheduleIfNeeded(using forecast: HourlyWeatherData) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])

        guard let nextHour = forecast.forecast.first,
              nextHour.precipitationProbability >= 50,
              nextHour.date.timeIntervalSinceNow > 0,
              nextHour.date.timeIntervalSinceNow <= 60 * 60 else {
            return
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Возможны осадки"
        content.body = "В ближайший час вероятность дождя или снега — \(nextHour.precipitationProbability)%."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(nextHour.date.timeIntervalSinceNow, 5),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }

    static func cancelRainAlert() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
    }
}
