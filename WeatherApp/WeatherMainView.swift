import SwiftUI
import WidgetKit

struct WeatherCardReport: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let symbol: String
    let explanation: String
}

private struct FavoriteCity: Codable, Identifiable, Equatable {
    let city: String
    let latitude: Double
    let longitude: Double

    var id: String {
        "\(city.lowercased())-\(latitude)-\(longitude)"
    }
}

struct WeatherData {
    let city: String
    let temperature: Int
    let feelsLike: Int
    let humidity: Int
    let windSpeed: Double
    let windDirection: Int?
    let windGust: Double?
    let pressure: Int
    let sunrise: Date
    let sunset: Date
    let timeZoneOffset: Int
    let visibility: Double
    let weatherIcon: String
    var isNight = false
    let latitude: Double
    let longitude: Double
}

enum WeatherSymbolColor {
    static func color(for symbol: String) -> Color {
        switch symbol {
        case "sun.max.fill", "cloud.sun.fill", "cloud.bolt.rain.fill":
            return .yellow
        case "moon.stars.fill", "cloud.moon.fill":
            return Color(red: 0.75, green: 0.83, blue: 1)
        case "cloud.rain.fill", "cloud.drizzle.fill":
            return Color(red: 0.55, green: 0.82, blue: 1)
        case "cloud.snow.fill":
            return Color(red: 0.75, green: 0.92, blue: 1)
        case "cloud.fog.fill":
            return Color(red: 0.82, green: 0.87, blue: 0.92)
        default:
            return .white
        }
    }
}

struct WeatherMainView: View {
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
    @State private var weatherData: WeatherData?
    @Binding var cityName: String
    let isActive: Bool
    @State private var forecasts: [DailyForecast] = []
    @State private var hourlyWeather: HourlyWeatherData?
    @State private var airQuality: AirQualityData?
    @State private var isLoadingForecast = false
    @State private var isLoadingHourlyWeather = false
    @State private var isLoadingAirQuality = false
    @State private var forecastError: String?
    @State private var hourlyWeatherError: String?
    @State private var airQualityError: String?
    @State private var selectedWeatherReport: WeatherCardReport?
    @State private var favoriteCities: [FavoriteCity] = []
    @State private var isShowingSettings = false
    @State private var isShowingWeatherMap = false
    @State private var isLoading = false
    @State private var isLocating = false
    @State private var locationService = LocationService()
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var suggestions: [CitySuggestion] = []
    @State private var suggestionsError: String?
    @State private var isLoadingSuggestions = false
    @State private var suggestionTask: Task<Void, Never>?
    @FocusState private var isCityFieldFocused: Bool

    var body: some View {
        ZStack {
            WeatherAnimatedBackground(
                symbol: weatherData?.weatherIcon ?? "cloud.fill",
                isNight: weatherData?.isNight ?? false,
                isActive: isActive
            )

            ScrollView {
                VStack(spacing: 24) {
                    citySearch
                    favoriteCitiesView

                    if let weatherData {
                        weatherSummary(weatherData)
                        weatherDetails(weatherData)
                        hourlyForecastSection
                        environmentalConditions
                        sevenDayForecast
                        weatherMapSection
                    } else if isLoading {
                        ProgressView("Загружаем погоду…")
                            .tint(.white)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ContentUnavailableView(
                            "Нет данных о погоде",
                            systemImage: "cloud",
                            description: Text("Введите город и нажмите «Найти».")
                        )
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .animation(.easeInOut(duration: 0.8), value: weatherData?.weatherIcon)
        }
        .safeAreaInset(edge: .bottom) {
            refreshButton
        }
        .task {
            loadFavoriteCities()
            await loadWeather()
        }
        .alert("Не удалось загрузить погоду", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Попробуйте ещё раз.")
        }
        .sheet(item: $selectedWeatherReport) { report in
            WeatherReportSheet(report: report)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: temperatureUnit) { _, _ in
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: windSpeedUnit) { _, _ in
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: clockFormat) { _, _ in
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @ViewBuilder
    private var favoriteCitiesView: some View {
        if !favoriteCities.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Избранные города", systemImage: "star.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(favoriteCities) { favorite in
                            Button {
                                dismissCitySuggestions()
                                cityName = favorite.city
                                Task {
                                    await loadWeather(
                                        latitude: favorite.latitude,
                                        longitude: favorite.longitude
                                    )
                                }
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.yellow)
                                    Text(favorite.city)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(.white.opacity(0.18), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    removeFavorite(favorite)
                                } label: {
                                    Label("Удалить из избранного", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var citySearch: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button {
                    isShowingSettings = true
                } label: {
                    Label("Настройки", systemImage: "gearshape")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.16), in: Capsule())
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $isShowingSettings) {
                    WeatherSettingsView()
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                }
            }

            HStack(spacing: 10) {
                TextField(
                    "Город",
                    text: $cityName,
                    prompt: Text("Введите город").foregroundColor(.gray)
                )
                .textContentType(.addressCity)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .textFieldStyle(.plain)
                .tint(.blue)
                .foregroundStyle(Color.black)
                .focused($isCityFieldFocused)
                .onChange(of: cityName) { _, newValue in
                    scheduleCitySearch(for: newValue)
                }
                .onChange(of: isCityFieldFocused) { _, isFocused in
                    if isFocused {
                        scheduleCitySearch(for: cityName)
                    } else {
                        dismissCitySuggestions()
                    }
                }
                .onSubmit {
                    dismissCitySuggestions()
                    Task { await loadWeather() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 8) {
                    Button {
                        dismissCitySuggestions()
                        Task { await loadWeather() }
                    } label: {
                        Text("Найти")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isLoading || cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        dismissCitySuggestions()
                        Task { await loadWeatherForCurrentLocation() }
                    } label: {
                        Group {
                            if isLocating {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "location.fill")
                            }
                        }
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isLoading || isLocating)
                    .accessibilityLabel("Определить город по геолокации")
                }
            }

            if isCityFieldFocused && cityName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                if !suggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(suggestions) { suggestion in
                            Button {
                                dismissCitySuggestions()
                                cityName = suggestion.name
                                Task { await loadWeather(latitude: suggestion.lat, longitude: suggestion.lon) }
                            } label: {
                                HStack {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundStyle(Color.blue)
                                    Text(suggestion.displayName)
                                        .foregroundStyle(Color.black)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if suggestion.id != suggestions.last?.id {
                                Divider()
                                    .padding(.leading, 14)
                            }
                        }
                    }
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                    .zIndex(1)
                } else if isLoadingSuggestions {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.blue)
                        Text("Ищем города…")
                            .foregroundStyle(Color.black)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                } else if let suggestionsError {
                    Text(suggestionsError)
                        .font(.subheadline)
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func weatherSummary(_ weather: WeatherData) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Spacer(minLength: 36)
                Text(weather.city)
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity)
                Button {
                    toggleFavorite(weather)
                } label: {
                    Image(systemName: isFavorite(weather) ? "star.fill" : "star")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isFavorite(weather) ? .yellow : .white)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isFavorite(weather) ? "Убрать город из избранного" : "Добавить город в избранное"
                )
                .accessibilityHint("Город будет сохранён на этом устройстве")
            }

            Image(systemName: weather.weatherIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundStyle(WeatherSymbolColor.color(for: weather.weatherIcon))
                .accessibilityHidden(true)

            Text(WeatherDisplayFormat.temperature(weather.temperature, unit: temperatureUnit))
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .accessibilityLabel("Температура \(WeatherDisplayFormat.temperature(weather.temperature, unit: temperatureUnit))")

            Text("Ощущается как \(WeatherDisplayFormat.temperature(weather.feelsLike, unit: temperatureUnit))")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func isFavorite(_ weather: WeatherData) -> Bool {
        favoriteCities.contains {
            abs($0.latitude - weather.latitude) < 0.001
                && abs($0.longitude - weather.longitude) < 0.001
        }
    }

    private func toggleFavorite(_ weather: WeatherData) {
        if let favorite = favoriteCities.first(where: {
            abs($0.latitude - weather.latitude) < 0.001
                && abs($0.longitude - weather.longitude) < 0.001
        }) {
            removeFavorite(favorite)
            return
        }

        favoriteCities.append(
            FavoriteCity(
                city: weather.city,
                latitude: weather.latitude,
                longitude: weather.longitude
            )
        )
        saveFavoriteCities()
    }

    private func removeFavorite(_ favorite: FavoriteCity) {
        favoriteCities.removeAll { $0.id == favorite.id }
        saveFavoriteCities()
    }

    private func loadFavoriteCities() {
        guard let data = UserDefaults.standard.data(forKey: "favoriteCities") else { return }
        do {
            favoriteCities = try JSONDecoder().decode([FavoriteCity].self, from: data)
        } catch {
            errorMessage = "Не удалось загрузить избранные города: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func saveFavoriteCities() {
        do {
            let data = try JSONEncoder().encode(favoriteCities)
            UserDefaults.standard.set(data, forKey: "favoriteCities")
            if let weatherData {
                Task {
                    do {
                        try await refreshWidgetSnapshot(for: weatherData)
                    } catch {
                        errorMessage = "Не удалось обновить виджет избранным городом: \(error.localizedDescription)"
                        showingError = true
                    }
                }
            }
        } catch {
            errorMessage = "Не удалось сохранить избранные города: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func weatherDetails(_ weather: WeatherData) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            WeatherDetailsCard(
                title: "Влажность",
                value: "\(weather.humidity)%",
                symbol: "drop.fill",
                accent: Color(red: 0.42, green: 0.82, blue: 1),
                progress: Double(weather.humidity) / 100,
                explanation: "Относительная влажность показывает, сколько водяного пара содержится в воздухе относительно максимального количества при текущей температуре. Высокая влажность может усиливать ощущение духоты."
            ) { selectedWeatherReport = $0 }

            WindDetailsCard(weather: weather, windSpeedUnit: windSpeedUnit) { selectedWeatherReport = $0 }

            WeatherDetailsCard(
                title: "Давление",
                value: "\(weather.pressure) мм рт.ст.",
                symbol: "gauge",
                accent: Color(red: 0.73, green: 1, blue: 0.84),
                explanation: "Атмосферное давление приведено в миллиметрах ртутного столба. Изменение давления со временем обычно информативнее одного значения; здесь показано текущее измерение."
            ) { selectedWeatherReport = $0 }

            WeatherDetailsCard(
                title: "Рассвет",
                value: WeatherDisplayFormat.time(
                    weather.sunrise,
                    timeZoneOffset: weather.timeZoneOffset,
                    format: clockFormat
                ),
                symbol: "sunrise.fill",
                accent: Color(red: 1, green: 0.84, blue: 0.48),
                explanation: "Время местного восхода солнца для выбранного города."
            ) { selectedWeatherReport = $0 }

            WeatherDetailsCard(
                title: "Закат",
                value: WeatherDisplayFormat.time(
                    weather.sunset,
                    timeZoneOffset: weather.timeZoneOffset,
                    format: clockFormat
                ),
                symbol: "sunset.fill",
                accent: Color(red: 1, green: 0.72, blue: 0.42),
                explanation: "Время местного захода солнца для выбранного города."
            ) { selectedWeatherReport = $0 }

            WeatherDetailsCard(
                title: "Видимость",
                value: "\(weather.visibility.formatted(.number.precision(.fractionLength(0...1)))) км",
                symbol: "eye.fill",
                accent: Color(red: 0.76, green: 0.78, blue: 1),
                explanation: "Видимость — примерное расстояние, на котором объекты различимы в атмосфере. Туман, осадки и дымка могут её уменьшать."
            ) { selectedWeatherReport = $0 }
        }
    }

    @ViewBuilder
    private var hourlyForecastSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Почасовой прогноз")
                        .font(.title2.weight(.bold))
                    Text("Ближайшие часы")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                if isLoadingHourlyWeather {
                    ProgressView()
                        .tint(.white)
                }
            }
            .foregroundStyle(.white)

            if let hourlyWeather, !hourlyWeather.forecast.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(hourlyWeather.forecast) { hour in
                            VStack(spacing: 10) {
                                Text(WeatherDisplayFormat.time(
                                    hour.date,
                                    timeZoneOffset: hourlyWeather.timeZoneOffset,
                                    format: clockFormat
                                ))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.8))

                                Image(systemName: hour.weatherIcon)
                                    .font(.title3)
                                    .foregroundStyle(WeatherSymbolColor.color(for: hour.weatherIcon))
                                    .frame(height: 26)

                                Text(WeatherDisplayFormat.temperature(
                                    hour.temperature,
                                    unit: temperatureUnit
                                ))
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()

                                Label("\(hour.precipitationProbability)%", systemImage: "drop.fill")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Color(red: 0.58, green: 0.84, blue: 1))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 122)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(
                                "\(WeatherDisplayFormat.time(hour.date, timeZoneOffset: hourlyWeather.timeZoneOffset, format: clockFormat)), \(WeatherDisplayFormat.temperature(hour.temperature, unit: temperatureUnit)), вероятность осадков \(hour.precipitationProbability) процентов"
                            )
                        }
                    }
                }
            } else if let hourlyWeatherError {
                retryMessage(hourlyWeatherError) {
                    guard let weatherData else { return }
                    Task {
                        await loadHourlyWeather(
                            latitude: weatherData.latitude,
                            longitude: weatherData.longitude
                        )
                    }
                }
            } else if isLoadingHourlyWeather {
                ProgressView("Загружаем почасовой прогноз…")
                    .tint(.white)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 90)
            }
        }
    }

    @ViewBuilder
    private var environmentalConditions: some View {
        if let hourlyWeather, let uvIndex = hourlyWeather.currentUVIndex {
            let level = uvIndexLevel(uvIndex)
            WeatherDetailsCard(
                title: "УФ-индекс · \(level.title)",
                value: uvIndex.formatted(.number.precision(.fractionLength(0...1))),
                symbol: "sun.max.fill",
                accent: level.color,
                progress: min(uvIndex / 11, 1),
                explanation: "Текущий УФ-индекс: \(uvIndex.formatted(.number.precision(.fractionLength(0...1)))). \(level.description)"
            ) { selectedWeatherReport = $0 }
        } else if let hourlyWeatherError {
            retryMessage(hourlyWeatherError) {
                guard let weatherData else { return }
                Task {
                    await loadHourlyWeather(
                        latitude: weatherData.latitude,
                        longitude: weatherData.longitude
                    )
                }
            }
        }

        if let airQuality {
            let aqi = airQuality.usAQI
            let level = airQualityLevel(aqi)
            let value = aqi.map { "AQI \($0)" } ?? "Нет данных"
            let pollutants = [
                airQuality.pm25.map { "PM2.5: \($0.formatted(.number.precision(.fractionLength(0...1)))) мкг/м³" },
                airQuality.pm10.map { "PM10: \($0.formatted(.number.precision(.fractionLength(0...1)))) мкг/м³" }
            ].compactMap { $0 }.joined(separator: ". ")
            WeatherDetailsCard(
                title: "Качество воздуха · \(level.title)",
                value: value,
                symbol: "aqi.medium",
                accent: level.color,
                progress: aqi.map { min(Double($0) / 300, 1) },
                explanation: "Индекс качества воздуха US AQI: \(aqi.map { String($0) } ?? "нет данных"). \(level.description) \(pollutants)"
            ) { selectedWeatherReport = $0 }

            let highestPollen = airQuality.pollenReadings.map(\.concentration).max()
            let pollenDescription = airQuality.pollenReadings
                .map { "\($0.name): \($0.concentration.formatted(.number.precision(.fractionLength(0...1)))) зёрен/м³" }
                .joined(separator: ". ")
            WeatherDetailsCard(
                title: "Пыльца · прогноз",
                value: highestPollen.map {
                    "\($0.formatted(.number.precision(.fractionLength(0...1)))) зёрен/м³"
                } ?? "Нет данных",
                symbol: "allergens",
                accent: highestPollen.map { $0 > 10 ? Color.orange : Color.green } ?? Color.gray,
                explanation: "Максимальный прогнозируемый уровень пыльцы за ближайшие 48 часов. \(pollenDescription)"
            ) { selectedWeatherReport = $0 }
        } else if let airQualityError {
            retryMessage(airQualityError) {
                guard let weatherData else { return }
                Task {
                    await loadAirQuality(
                        latitude: weatherData.latitude,
                        longitude: weatherData.longitude
                    )
                }
            }
        } else if isLoadingAirQuality {
            ProgressView("Загружаем качество воздуха…")
                .tint(.white)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 60)
        }
    }

    private func retryMessage(_ message: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            Button("Повторить") {
                action()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
    }

    private func uvIndexLevel(_ value: Double) -> (title: String, color: Color, description: String) {
        switch value {
        case ..<3:
            return ("Низкий", Color.green, "Обычно достаточно обычных мер защиты от солнца.")
        case ..<6:
            return ("Умеренный", Color.yellow, "При долгом пребывании на солнце используйте защиту.")
        case ..<8:
            return ("Высокий", Color.orange, "Рекомендуются тень, одежда и солнцезащитное средство.")
        case ..<11:
            return ("Очень высокий", Color.red, "Сократите пребывание под прямым солнцем и используйте защиту.")
        default:
            return ("Экстремальный", Color.purple, "Избегайте прямого солнца в середине дня и используйте усиленную защиту.")
        }
    }

    private func airQualityLevel(_ value: Int?) -> (title: String, color: Color, description: String) {
        guard let value else {
            return ("Нет данных", Color.gray, "Сервис не предоставил индекс качества воздуха.")
        }
        switch value {
        case ...50:
            return ("Хорошее", Color.green, "Качество воздуха считается удовлетворительным.")
        case ...100:
            return ("Умеренное", Color.yellow, "У особо чувствительных людей возможен дискомфорт.")
        case ...150:
            return ("Нездоровое для чувствительных", Color.orange, "Чувствительным людям стоит ограничить длительные нагрузки на улице.")
        case ...200:
            return ("Нездоровое", Color.red, "Рекомендуется сократить длительное пребывание на улице.")
        case ...300:
            return ("Очень нездоровое", Color.purple, "По возможности оставайтесь в помещении.")
        default:
            return ("Опасное", Color(red: 0.5, green: 0.3, blue: 0.2), "Сведите пребывание на улице к минимуму.")
        }
    }

    private var weatherMapSection: some View {
        Button {
            isShowingWeatherMap = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "map.fill")
                    .font(.title2)
                    .foregroundStyle(Color(red: 0.63, green: 0.86, blue: 1))
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Карта погоды")
                        .font(.headline)
                    Text("Осадки и облачность")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isShowingWeatherMap) {
            if let weatherData {
                WeatherMapSheet(
                    cityName: weatherData.city,
                    latitude: weatherData.latitude,
                    longitude: weatherData.longitude
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var sevenDayForecast: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("На 7 дней")
                        .font(.title2.weight(.bold))
                    Text("Прогноз погоды")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                if isLoadingForecast {
                    ProgressView()
                        .tint(.white)
                }
            }
            .foregroundStyle(.white)

            if !forecasts.isEmpty {
                VStack(spacing: 0) {
                    ForEach(forecasts) { forecast in
                        forecastRow(forecast)
                        if forecast.id != forecasts.last?.id {
                            Divider()
                                .overlay(.white.opacity(0.18))
                                .padding(.leading, 16)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
            } else if let forecastError {
                VStack(alignment: .leading, spacing: 10) {
                    Text(forecastError)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                    Button("Попробовать снова") {
                        guard let weatherData else { return }
                        Task {
                            await loadForecast(
                                latitude: weatherData.latitude,
                                longitude: weatherData.longitude
                            )
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
            } else if isLoadingForecast {
                ProgressView("Загружаем прогноз…")
                    .tint(.white)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(.top, 4)
    }

    private func forecastRow(_ forecast: DailyForecast) -> some View {
        HStack(spacing: 12) {
            Text(dayTitle(for: forecast.date, timeZoneOffset: forecast.timeZoneOffset))
                .font(.subheadline.weight(.semibold))
                .frame(width: 82, alignment: .leading)
                .lineLimit(1)

            VStack(spacing: 3) {
                Image(systemName: forecast.weatherIcon)
                    .font(.title3)
                    .foregroundStyle(WeatherSymbolColor.color(for: forecast.weatherIcon))
                Label("\(forecast.precipitationProbability)%", systemImage: "drop.fill")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color(red: 0.58, green: 0.84, blue: 1))
            }
            .frame(width: 34)
            .accessibilityHidden(true)

            Text(WeatherDisplayFormat.temperature(forecast.minimumTemperature, unit: temperatureUnit))
                .foregroundStyle(.white.opacity(0.68))
                .monospacedDigit()

            TemperatureRangeIndicator(
                minimum: forecast.minimumTemperature,
                maximum: forecast.maximumTemperature,
                scaleMinimum: forecastScaleMinimum,
                scaleMaximum: forecastScaleMaximum
            )
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            Text(WeatherDisplayFormat.temperature(forecast.maximumTemperature, unit: temperatureUnit))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(dayTitle(for: forecast.date, timeZoneOffset: forecast.timeZoneOffset)), минимум \(WeatherDisplayFormat.temperature(forecast.minimumTemperature, unit: temperatureUnit)), максимум \(WeatherDisplayFormat.temperature(forecast.maximumTemperature, unit: temperatureUnit)), вероятность осадков \(forecast.precipitationProbability) процентов"
        )
    }

    private var forecastScaleMinimum: Int {
        (forecasts.map(\.minimumTemperature).min() ?? 0) - 2
    }

    private var forecastScaleMaximum: Int {
        (forecasts.map(\.maximumTemperature).max() ?? 1) + 2
    }

    private func dayTitle(for date: Date, timeZoneOffset: Int) -> String {
        let timeZone = TimeZone(secondsFromGMT: timeZoneOffset) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE, d MMM"

        let today = calendar.startOfDay(for: Date())
        if calendar.isDate(date, inSameDayAs: today) {
            return "Сегодня"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Завтра"
        }
        return formatter.string(from: date).capitalized
    }

    private var refreshButton: some View {
        Button {
            Task { await loadWeather() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(isLoading ? 360 : 0))
                    .animation(
                        isLoading
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: isLoading
                    )
                Text("Обновить")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.7 : 1)
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial.opacity(0.35))
    }

    @MainActor
    private func loadWeather() async {
        let city = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else {
            errorMessage = "Введите название города."
            showingError = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await WeatherService.fetchWeather(city: city)
            await applyWeather(result)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    @MainActor
    private func loadWeatherForCurrentLocation() async {
        isLocating = true
        defer { isLocating = false }

        do {
            cityName = try await locationService.currentCity()
            await loadWeather()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func dismissCitySuggestions() {
        isCityFieldFocused = false
        suggestionTask?.cancel()
        suggestionTask = nil
        suggestions = []
        suggestionsError = nil
        isLoadingSuggestions = false
    }

    private func scheduleCitySearch(for value: String) {
        suggestionTask?.cancel()
        suggestions = []
        suggestionsError = nil

        let query = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isCityFieldFocused, query.count >= 2 else {
            isLoadingSuggestions = false
            return
        }

        isLoadingSuggestions = true
        suggestionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled,
                      isCityFieldFocused,
                      cityName.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }

                let results = try await WeatherService.searchCities(query: query)
                guard !Task.isCancelled,
                      isCityFieldFocused,
                      cityName.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                suggestions = results
                suggestionsError = results.isEmpty
                    ? "Совпадений не найдено. Проверьте написание города."
                    : nil
                isLoadingSuggestions = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      isCityFieldFocused,
                      cityName.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                suggestions = []
                suggestionsError = "Не удалось загрузить подсказки: \(error.localizedDescription)"
                isLoadingSuggestions = false
            }
        }
    }

    @MainActor
    private func loadWeather(latitude: Double, longitude: Double) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await WeatherService.fetchWeather(latitude: latitude, longitude: longitude)
            await applyWeather(result)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    @MainActor
    private func applyWeather(_ weather: WeatherData) async {
        withAnimation {
            weatherData = weather
            cityName = weather.city
            forecasts = []
            hourlyWeather = nil
            airQuality = nil
            forecastError = nil
            hourlyWeatherError = nil
            airQualityError = nil
        }
        do {
            try await refreshWidgetSnapshot(for: weather)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        async let forecastLoad = loadForecast(
            latitude: weather.latitude,
            longitude: weather.longitude
        )
        async let hourlyLoad = loadHourlyWeather(
            latitude: weather.latitude,
            longitude: weather.longitude
        )
        async let airQualityLoad = loadAirQuality(
            latitude: weather.latitude,
            longitude: weather.longitude
        )
        _ = await (forecastLoad, hourlyLoad, airQualityLoad)
    }

    @MainActor
    private func refreshWidgetSnapshot(for currentWeather: WeatherData) async throws {
        let preferredFavorite = favoriteCities.first
        let widgetWeather: WeatherData

        if let preferredFavorite,
           abs(preferredFavorite.latitude - currentWeather.latitude) >= 0.001
            || abs(preferredFavorite.longitude - currentWeather.longitude) >= 0.001 {
            widgetWeather = try await WeatherService.fetchWeather(
                latitude: preferredFavorite.latitude,
                longitude: preferredFavorite.longitude
            )
        } else {
            widgetWeather = currentWeather
        }

        try WidgetWeatherSnapshot.save(
            WidgetWeatherSnapshot(
                city: widgetWeather.city,
                temperature: widgetWeather.temperature,
                feelsLike: widgetWeather.feelsLike,
                weatherIcon: widgetWeather.weatherIcon,
                updatedAt: .now,
                timeZoneOffset: widgetWeather.timeZoneOffset
            )
        )
    }

    @MainActor
    private func loadForecast(latitude: Double, longitude: Double) async {
        isLoadingForecast = true
        forecastError = nil
        defer { isLoadingForecast = false }

        do {
            forecasts = try await WeatherService.fetchForecast(
                latitude: latitude,
                longitude: longitude
            )
            if forecasts.isEmpty {
                forecastError = "Сервис не вернул данные для прогноза."
            }
        } catch {
            forecastError = "Не удалось загрузить прогноз: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadHourlyWeather(latitude: Double, longitude: Double) async {
        isLoadingHourlyWeather = true
        hourlyWeatherError = nil
        defer { isLoadingHourlyWeather = false }

        do {
            let result = try await WeatherService.fetchHourlyForecast(
                latitude: latitude,
                longitude: longitude
            )
            hourlyWeather = result
            hourlyWeatherError = nil
            if UserDefaults.standard.bool(forKey: "rainNotificationsEnabled") {
                do {
                    try await RainNotificationService.scheduleIfNeeded(using: result)
                } catch {
                    errorMessage = "Не удалось запланировать уведомление: \(error.localizedDescription)"
                    showingError = true
                }
            }
        } catch {
            hourlyWeatherError = "Почасовой прогноз недоступен: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadAirQuality(latitude: Double, longitude: Double) async {
        isLoadingAirQuality = true
        airQualityError = nil
        defer { isLoadingAirQuality = false }

        do {
            airQuality = try await WeatherService.fetchAirQuality(
                latitude: latitude,
                longitude: longitude
            )
        } catch {
            airQualityError = "Качество воздуха недоступно: \(error.localizedDescription)"
        }
    }
}

private struct TemperatureRangeIndicator: View {
    let minimum: Int
    let maximum: Int
    let scaleMinimum: Int
    let scaleMaximum: Int

    private var scaleRange: Double {
        Double(max(scaleMaximum - scaleMinimum, 1))
    }

    private var leadingFraction: Double {
        min(max(Double(minimum - scaleMinimum) / scaleRange, 0), 1)
    }

    private var rangeFraction: Double {
        min(max(Double(maximum - minimum) / scaleRange, 0.04), 1 - leadingFraction)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            Capsule()
                .fill(.white.opacity(0.2))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.48, green: 0.78, blue: 1),
                                    Color(red: 1, green: 0.78, blue: 0.39)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(width * rangeFraction, 4))
                        .offset(x: width * leadingFraction)
                }
        }
        .frame(height: 6)
    }
}

struct WeatherDetailsCard: View {
    let title: String
    let value: String
    let symbol: String
    let accent: Color
    var progress: Double? = nil
    let explanation: String
    let onReport: (WeatherCardReport) -> Void

    var body: some View {
        Button {
            onReport(
                WeatherCardReport(
                    title: title,
                    value: value,
                    symbol: symbol,
                    explanation: explanation
                )
            )
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 38, height: 38)
                        .background(accent.opacity(0.16), in: Circle())
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                    Text(value)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .monospacedDigit()
                }

                if let progress {
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(accent)
                        .accessibilityLabel("Уровень \(title.lowercased())")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .padding(16)
            .foregroundStyle(.white)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityHint("Нажмите, чтобы открыть подробный отчёт")
    }
}

struct WindDetailsCard: View {
    let weather: WeatherData
    let windSpeedUnit: String
    let onReport: (WeatherCardReport) -> Void

    private let accent = Color(red: 0.73, green: 0.91, blue: 1)
    private let compassPoints = ["С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ"]

    private var directionName: String {
        guard let degrees = weather.windDirection else { return "Направление неизвестно" }
        let index = Int((Double(degrees % 360) / 45).rounded()) % compassPoints.count
        return "Ветер с \(compassPoints[index]) · \(degrees % 360)°"
    }

    var body: some View {
        Button {
            let gustText = weather.windGust.map {
                WeatherDisplayFormat.windSpeed($0, unit: windSpeedUnit)
            } ?? "нет данных"
            let details = [
                directionName,
                "Средняя скорость ветра: \(WeatherDisplayFormat.windSpeed(weather.windSpeed, unit: windSpeedUnit)).",
                "Порывы: \(gustText). Порывы — кратковременные усиления ветра и могут быть сильнее средней скорости."
            ].joined(separator: "\n\n")
            onReport(
                WeatherCardReport(
                    title: "Ветер",
                    value: WeatherDisplayFormat.windSpeed(weather.windSpeed, unit: windSpeedUnit),
                    symbol: "wind",
                    explanation: details
                )
            )
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                Label("Ветер", systemImage: "wind")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))

                HStack(spacing: 10) {
                    CompassDial(degrees: weather.windDirection)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WeatherDisplayFormat.windSpeed(weather.windSpeed, unit: windSpeedUnit))
                            .font(.title3.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .monospacedDigit()
                        Text(directionName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                Text("Порывы: \(weather.windGust.map { WeatherDisplayFormat.windSpeed($0, unit: windSpeedUnit) } ?? "нет данных")")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .padding(16)
            .foregroundStyle(.white)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ветер, \(WeatherDisplayFormat.windSpeed(weather.windSpeed, unit: windSpeedUnit)), \(directionName)")
        .accessibilityHint("Нажмите, чтобы открыть подробный отчёт")
    }
}

private struct WeatherReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let report: WeatherCardReport

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.38, blue: 0.62),
                    Color(red: 0.08, green: 0.22, blue: 0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Image(systemName: report.symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.18), in: Circle())
                    Spacer()
                    Button("Закрыть") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(report.title)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.78))
                    Text(report.value)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(report.explanation)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }
}

private struct CompassDial: View {
    let degrees: Int?

    private let directions = ["С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ"]

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = size / 2
            let labelRadius = size * 0.34

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.25, blue: 0.36),
                                Color(red: 0.06, green: 0.14, blue: 0.23)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .stroke(.white.opacity(0.26), lineWidth: 1)
                    .padding(1)

                ForEach(0..<36, id: \.self) { tick in
                    Capsule()
                        .fill(.white.opacity(tick.isMultiple(of: 3) ? 0.82 : 0.38))
                        .frame(
                            width: tick.isMultiple(of: 3) ? 1.5 : 1,
                            height: tick.isMultiple(of: 3) ? 6 : 3
                        )
                        .offset(y: -(center - 5))
                        .rotationEffect(.degrees(Double(tick) * 10))
                }

                ForEach(0..<directions.count, id: \.self) { index in
                    let angle = Double(index) * .pi / 4
                    Text(directions[index])
                        .font(.system(size: 7, weight: index.isMultiple(of: 2) ? .bold : .medium))
                        .foregroundStyle(index == 0 ? Color(red: 1, green: 0.43, blue: 0.39) : .white.opacity(0.9))
                        .position(
                            x: center + sin(angle) * labelRadius,
                            y: center - cos(angle) * labelRadius
                        )
                }

                if let degrees {
                    ZStack {
                        CompassNeedleNorth()
                            .fill(Color(red: 1, green: 0.34, blue: 0.3))
                        CompassNeedleSouth()
                            .fill(.white.opacity(0.92))
                    }
                    .frame(width: 12, height: 30)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .rotationEffect(.degrees(Double(degrees % 360)))
                } else {
                    Circle()
                        .fill(.white.opacity(0.55))
                        .frame(width: 5, height: 5)
                }
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .frame(width: 78, height: 78)
    }
}

private struct CompassNeedleNorth: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY + 2))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + 2))
            path.closeSubpath()
        }
    }
}

private struct CompassNeedleSouth: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY - 2))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY - 2))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

#Preview {
    WeatherMainView(cityName: .constant("Москва"), isActive: true)
}
