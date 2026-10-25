import Foundation

struct DailyForecast: Identifiable {
    let date: Date
    let timeZoneOffset: Int
    let minimumTemperature: Int
    let maximumTemperature: Int
    let precipitationProbability: Int
    let weatherIcon: String

    var id: Date { date }
}

struct HourlyForecast: Identifiable {
    let date: Date
    let temperature: Int
    let precipitationProbability: Int
    let weatherIcon: String

    var id: Date { date }
}

struct HourlyWeatherData {
    let timeZoneOffset: Int
    let currentUVIndex: Double?
    let forecast: [HourlyForecast]
}

struct AirQualityData {
    let usAQI: Int?
    let pm25: Double?
    let pm10: Double?
    let pollenReadings: [PollenReading]
}

struct PollenReading: Identifiable {
    let name: String
    let concentration: Double

    var id: String { name }
}

struct CitySuggestion: Decodable, Identifiable {
    let name: String
    let country: String
    let lat: Double
    let lon: Double

    enum CodingKeys: String, CodingKey {
        case name
        case country
        case lat
        case lon
    }

    var id: String {
        "\(name)-\(country)-\(lat)-\(lon)"
    }

    var displayName: String {
        "\(name), \(country)"
    }
}

enum WeatherService {
    private static var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "OPENWEATHERMAP_API_KEY") as? String ?? ""
    }
    private static let endpoint = URL(string: "https://api.openweathermap.org/data/2.5/weather")!
    private static let geocodingEndpoint = URL(string: "https://api.openweathermap.org/geo/1.0/direct")!
    private static let sevenDayForecastEndpoint = URL(string: "https://api.open-meteo.com/v1/forecast")!
    private static let airQualityEndpoint = URL(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!

    static func searchCities(query: String) async throws -> [CitySuggestion] {
        guard !apiKey.isEmpty else {
            throw WeatherServiceError.missingAPIKey
        }

        guard var components = URLComponents(url: geocodingEndpoint, resolvingAgainstBaseURL: false) else {
            throw WeatherServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "appid", value: apiKey)
        ]
        guard let url = components.url else {
            throw WeatherServiceError.invalidURL
        }

        let data = try await fetchData(from: url)
        return try JSONDecoder().decode([CitySuggestion].self, from: data)
    }

    static func fetchWeather(city: String) async throws -> WeatherData {
        let data = try await fetchData(from: makeURL(endpoint: endpoint, city: city))
        return try decodeWeather(from: data)
    }

    static func fetchWeather(latitude: Double, longitude: Double) async throws -> WeatherData {
        guard !apiKey.isEmpty else {
            throw WeatherServiceError.missingAPIKey
        }

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw WeatherServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "appid", value: apiKey),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "lang", value: "ru")
        ]
        guard let url = components.url else {
            throw WeatherServiceError.invalidURL
        }
        let data = try await fetchData(from: url)
        return try decodeWeather(from: data)
    }

    private static func decodeWeather(from data: Data) throws -> WeatherData {
        let payload = try JSONDecoder().decode(OpenWeatherResponse.self, from: data)
        let condition = payload.weather.first
        let sunriseDate = Date(timeIntervalSince1970: TimeInterval(payload.system.sunrise))
        let sunsetDate = Date(timeIntervalSince1970: TimeInterval(payload.system.sunset))

        return WeatherData(
            city: payload.name,
            temperature: Int(payload.main.temperature.rounded()),
            feelsLike: Int(payload.main.feelsLike.rounded()),
            humidity: payload.main.humidity,
            windSpeed: payload.wind.speed,
            windDirection: payload.wind.direction,
            windGust: payload.wind.gust,
            pressure: Int((Double(payload.main.pressure) * 0.750_062).rounded()),
            sunrise: sunriseDate,
            sunset: sunsetDate,
            timeZoneOffset: payload.timeZoneOffset,
            visibility: Double(payload.visibility) / 1_000,
            weatherIcon: condition.map { Self.symbol(for: $0) } ?? "cloud.fill",
            isNight: payload.isNight,
            latitude: payload.coordinates.latitude,
            longitude: payload.coordinates.longitude
        )
    }

    static func fetchForecast(latitude: Double, longitude: Double) async throws -> [DailyForecast] {
        guard var components = URLComponents(
            url: sevenDayForecastEndpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw WeatherServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_min,temperature_2m_max,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: "celsius")
        ]
        guard let url = components.url else {
            throw WeatherServiceError.invalidURL
        }

        let data = try await fetchData(from: url, usesOpenWeatherMap: false)
        let payload = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)
        let timeZone = TimeZone(secondsFromGMT: payload.timeZoneOffset) ?? .current
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let daily = payload.daily
        let count = [
            daily.dates.count,
            daily.minimumTemperatures.count,
            daily.maximumTemperatures.count,
            daily.precipitationProbabilities.count,
            daily.weatherCodes.count,
            7
        ].min() ?? 0

        return (0..<count).compactMap { index in
            guard let date = dateFormatter.date(from: daily.dates[index]) else {
                return nil
            }
            return DailyForecast(
                date: date,
                timeZoneOffset: payload.timeZoneOffset,
                minimumTemperature: Int(daily.minimumTemperatures[index].rounded()),
                maximumTemperature: Int(daily.maximumTemperatures[index].rounded()),
                precipitationProbability: daily.precipitationProbabilities[index],
                weatherIcon: Self.symbol(forWeatherCode: daily.weatherCodes[index])
            )
        }
    }

    static func fetchHourlyForecast(latitude: Double, longitude: Double) async throws -> HourlyWeatherData {
        guard var components = URLComponents(
            url: sevenDayForecastEndpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw WeatherServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "uv_index"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: "celsius")
        ]
        guard let url = components.url else {
            throw WeatherServiceError.invalidURL
        }

        let data = try await fetchData(from: url, usesOpenWeatherMap: false)
        let payload = try JSONDecoder().decode(OpenMeteoHourlyResponse.self, from: data)
        let timeZone = TimeZone(secondsFromGMT: payload.timeZoneOffset) ?? .current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let hourly = payload.hourly
        let count = [
            hourly.times.count,
            hourly.temperatures.count,
            hourly.precipitationProbabilities.count,
            hourly.weatherCodes.count
        ].min() ?? 0
        let now = Date()
        let forecast = (0..<count).compactMap { index -> HourlyForecast? in
            guard let date = formatter.date(from: hourly.times[index]),
                  date >= now else {
                return nil
            }
            return HourlyForecast(
                date: date,
                temperature: Int(hourly.temperatures[index].rounded()),
                precipitationProbability: hourly.precipitationProbabilities[index],
                weatherIcon: Self.symbol(forWeatherCode: hourly.weatherCodes[index])
            )
        }

        return HourlyWeatherData(
            timeZoneOffset: payload.timeZoneOffset,
            currentUVIndex: payload.current.uvIndex,
            forecast: Array(forecast.prefix(12))
        )
    }

    static func fetchAirQuality(latitude: Double, longitude: Double) async throws -> AirQualityData {
        guard var components = URLComponents(
            url: airQualityEndpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw WeatherServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "us_aqi,pm2_5,pm10"),
            URLQueryItem(name: "hourly", value: "birch_pollen,grass_pollen,ragweed_pollen"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else {
            throw WeatherServiceError.invalidURL
        }

        let data = try await fetchData(from: url, usesOpenWeatherMap: false)
        let payload = try JSONDecoder().decode(OpenMeteoAirQualityResponse.self, from: data)
        return AirQualityData(
            usAQI: payload.current.usAQI,
            pm25: payload.current.pm25,
            pm10: payload.current.pm10,
            pollenReadings: payload.pollenReadings
        )
    }

    private static func makeURL(endpoint: URL, city: String) throws -> URL {
        guard !apiKey.isEmpty else {
            throw WeatherServiceError.missingAPIKey
        }

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw WeatherServiceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: city),
            URLQueryItem(name: "appid", value: apiKey),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "lang", value: "ru")
        ]

        guard let url = components.url else {
            throw WeatherServiceError.invalidURL
        }
        return url
    }

    private static func fetchData(from url: URL, usesOpenWeatherMap: Bool = true) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw WeatherServiceError.invalidResponse
        }

        guard (200..<300).contains(response.statusCode) else {
            switch response.statusCode {
            case 401 where usesOpenWeatherMap:
                throw WeatherServiceError.invalidAPIKey
            case 404 where usesOpenWeatherMap:
                throw WeatherServiceError.cityNotFound
            case 429:
                throw WeatherServiceError.rateLimitExceeded
            default:
                throw WeatherServiceError.serverError(response.statusCode)
            }
        }
        return data
    }

    private static func symbol(for condition: OpenWeatherCondition) -> String {
        switch condition.id {
        case 200..<300:
            return "cloud.bolt.rain.fill"
        case 300..<400:
            return "cloud.drizzle.fill"
        case 500..<600:
            return "cloud.rain.fill"
        case 600..<700:
            return "cloud.snow.fill"
        case 700..<800:
            return "cloud.fog.fill"
        case 800:
            return condition.icon.hasSuffix("n") ? "moon.stars.fill" : "sun.max.fill"
        case 801:
            return condition.icon.hasSuffix("n") ? "cloud.moon.fill" : "cloud.sun.fill"
        default:
            return "cloud.fill"
        }
    }

    private static func symbol(forWeatherCode code: Int) -> String {
        switch code {
        case 0:
            return "sun.max.fill"
        case 1:
            return "cloud.sun.fill"
        case 2:
            return "cloud.sun.fill"
        case 3:
            return "cloud.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51...57:
            return "cloud.drizzle.fill"
        case 61...67, 80...82:
            return "cloud.rain.fill"
        case 71...77, 85, 86:
            return "cloud.snow.fill"
        case 95...99:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.fill"
        }
    }
}

private struct OpenWeatherResponse: Decodable {
    let name: String
    let timestamp: Int
    let timeZoneOffset: Int
    let system: System
    let coordinates: Coordinates
    let main: Main
    let wind: Wind
    let visibility: Int
    let weather: [OpenWeatherCondition]

    var isNight: Bool {
        timestamp < system.sunrise || timestamp >= system.sunset
    }

    enum CodingKeys: String, CodingKey {
        case name
        case timestamp = "dt"
        case timeZoneOffset = "timezone"
        case system = "sys"
        case coordinates = "coord"
        case main
        case wind
        case visibility
        case weather
    }

    struct Coordinates: Decodable {
        let latitude: Double
        let longitude: Double

        enum CodingKeys: String, CodingKey {
            case latitude = "lat"
            case longitude = "lon"
        }
    }

    struct System: Decodable {
        let sunrise: Int
        let sunset: Int
    }

    struct Main: Decodable {
        let temperature: Double
        let feelsLike: Double
        let humidity: Int
        let pressure: Int

        enum CodingKeys: String, CodingKey {
            case temperature = "temp"
            case feelsLike = "feels_like"
            case humidity
            case pressure
        }
    }

    struct Wind: Decodable {
        let speed: Double
        let direction: Int?
        let gust: Double?

        enum CodingKeys: String, CodingKey {
            case speed
            case direction = "deg"
            case gust
        }
    }
}

private struct OpenWeatherCondition: Decodable {
    let id: Int
    let icon: String
}

private struct OpenMeteoForecastResponse: Decodable {
    let timeZoneOffset: Int
    let daily: Daily

    enum CodingKeys: String, CodingKey {
        case timeZoneOffset = "utc_offset_seconds"
        case daily
    }

    struct Daily: Decodable {
        let dates: [String]
        let minimumTemperatures: [Double]
        let maximumTemperatures: [Double]
        let precipitationProbabilities: [Int]
        let weatherCodes: [Int]

        enum CodingKeys: String, CodingKey {
            case dates = "time"
            case minimumTemperatures = "temperature_2m_min"
            case maximumTemperatures = "temperature_2m_max"
            case precipitationProbabilities = "precipitation_probability_max"
            case weatherCodes = "weather_code"
        }
    }
}

private struct OpenMeteoHourlyResponse: Decodable {
    let timeZoneOffset: Int
    let current: Current
    let hourly: Hourly

    enum CodingKeys: String, CodingKey {
        case timeZoneOffset = "utc_offset_seconds"
        case current
        case hourly
    }

    struct Current: Decodable {
        let uvIndex: Double?

        enum CodingKeys: String, CodingKey {
            case uvIndex = "uv_index"
        }
    }

    struct Hourly: Decodable {
        let times: [String]
        let temperatures: [Double]
        let precipitationProbabilities: [Int]
        let weatherCodes: [Int]

        enum CodingKeys: String, CodingKey {
            case times = "time"
            case temperatures = "temperature_2m"
            case precipitationProbabilities = "precipitation_probability"
            case weatherCodes = "weather_code"
        }
    }
}

private struct OpenMeteoAirQualityResponse: Decodable {
    let current: Current
    let hourly: Hourly

    struct Current: Decodable {
        let usAQI: Int?
        let pm25: Double?
        let pm10: Double?

        enum CodingKeys: String, CodingKey {
            case usAQI = "us_aqi"
            case pm25 = "pm2_5"
            case pm10
        }
    }

    struct Hourly: Decodable {
        let birchPollen: [Double?]
        let grassPollen: [Double?]
        let ragweedPollen: [Double?]

        enum CodingKeys: String, CodingKey {
            case birchPollen = "birch_pollen"
            case grassPollen = "grass_pollen"
            case ragweedPollen = "ragweed_pollen"
        }
    }

    var pollenReadings: [PollenReading] {
        [
            ("Берёза", hourly.birchPollen),
            ("Травы", hourly.grassPollen),
            ("Амброзия", hourly.ragweedPollen)
        ].compactMap { name, values in
            guard let maximum = values.compactMap({ $0 }).max() else { return nil }
            return PollenReading(name: name, concentration: maximum)
        }
    }
}

private enum WeatherServiceError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case cityNotFound
    case rateLimitExceeded
    case invalidURL
    case invalidResponse
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Добавьте API-ключ OpenWeatherMap в WeatherApp/Secrets.xcconfig."
        case .invalidAPIKey:
            return "API-ключ недействителен. Проверьте ключ в WeatherApp/Secrets.xcconfig."
        case .cityNotFound:
            return "Город не найден. Проверьте название и попробуйте снова."
        case .rateLimitExceeded:
            return "Слишком много запросов. Попробуйте позже."
        case .invalidURL:
            return "Не удалось сформировать адрес запроса."
        case .invalidResponse:
            return "Сервер вернул некорректный ответ."
        case .serverError(let statusCode):
            return "Ошибка сервера погоды (код \(statusCode)). Попробуйте позже."
        }
    }
}
