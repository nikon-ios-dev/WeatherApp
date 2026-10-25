import SwiftUI

struct WeatherSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(
        "temperatureUnit",
        store: UserDefaults(suiteName: WidgetWeatherSnapshot.appGroupIdentifier)
    ) private var temperatureUnit = "celsius"
    @AppStorage(
        "windSpeedUnit",
        store: UserDefaults(suiteName: WidgetWeatherSnapshot.appGroupIdentifier)
    ) private var windSpeedUnit = "metersPerSecond"
    @AppStorage(
        "clockFormat",
        store: UserDefaults(suiteName: WidgetWeatherSnapshot.appGroupIdentifier)
    ) private var clockFormat = "twentyFourHour"
    @AppStorage("rainNotificationsEnabled") private var rainNotificationsEnabled = false
    @State private var notificationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Температура") {
                    Picker("Единицы", selection: $temperatureUnit) {
                        Text("Цельсий (°C)").tag("celsius")
                        Text("Фаренгейт (°F)").tag("fahrenheit")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Скорость ветра") {
                    Picker("Единицы", selection: $windSpeedUnit) {
                        Text("Метры в секунду (м/с)").tag("metersPerSecond")
                        Text("Километры в час (км/ч)").tag("kilometersPerHour")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Время") {
                    Picker("Формат", selection: $clockFormat) {
                        Text("24 часа").tag("twentyFourHour")
                        Text("12 часов").tag("twelveHour")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Предупреждения") {
                    Toggle("Дождь или снег в ближайший час", isOn: $rainNotificationsEnabled)
                        .onChange(of: rainNotificationsEnabled) { _, isEnabled in
                            Task {
                                await updateRainNotifications(isEnabled: isEnabled)
                            }
                        }
                    Text("Уведомление запланируется, если вероятность осадков в ближайший час достигнет 50%.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let notificationMessage {
                        Text(notificationMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
    }

    @MainActor
    private func updateRainNotifications(isEnabled: Bool) async {
        guard isEnabled else {
            RainNotificationService.cancelRainAlert()
            notificationMessage = "Уведомления отключены."
            return
        }

        do {
            let granted = try await RainNotificationService.requestPermission()
            rainNotificationsEnabled = granted
            notificationMessage = granted
                ? "Уведомления включены."
                : "Разрешите уведомления для WeatherApp в настройках iOS."
        } catch {
            rainNotificationsEnabled = false
            notificationMessage = "Не удалось запросить разрешение: \(error.localizedDescription)"
        }
    }
}
