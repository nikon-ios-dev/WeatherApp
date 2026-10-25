import SwiftUI
import WidgetKit

private struct WeatherWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetWeatherSnapshot?
}

private struct WeatherWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherWidgetEntry {
        WeatherWidgetEntry(
            date: .now,
            snapshot: WidgetWeatherSnapshot(
                city: "Москва",
                temperature: 14,
                feelsLike: 12,
                weatherIcon: "sun.max.fill",
                updatedAt: .now,
                timeZoneOffset: 10_800
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherWidgetEntry) -> Void) {
        let snapshot = context.isPreview
            ? placeholder(in: context).snapshot
            : WidgetWeatherSnapshot.load()
        completion(WeatherWidgetEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherWidgetEntry>) -> Void) {
        let entry = WeatherWidgetEntry(date: .now, snapshot: WidgetWeatherSnapshot.load())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

private struct WeatherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @AppStorage(
        "temperatureUnit",
        store: UserDefaults(suiteName: WidgetWeatherSnapshot.appGroupIdentifier)
    ) private var temperatureUnit = "celsius"
    @AppStorage(
        "clockFormat",
        store: UserDefaults(suiteName: WidgetWeatherSnapshot.appGroupIdentifier)
    ) private var clockFormat = "twentyFourHour"
    let entry: WeatherWidgetEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                widgetContent(snapshot)
            } else {
                emptyContent
            }
        }
        .containerBackground(
            LinearGradient(
                colors: [
                    Color(red: 0.22, green: 0.55, blue: 0.88),
                    Color(red: 0.12, green: 0.34, blue: 0.68)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            for: .widget
        )
    }

    private func widgetContent(_ snapshot: WidgetWeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
            HStack(alignment: .top) {
                Text(snapshot.city)
                    .font(family == .systemSmall ? .headline : .title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Image(systemName: snapshot.weatherIcon)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.yellow, .white)
                    .font(family == .systemSmall ? .title2 : .system(size: 32))
            }

            Text(WeatherDisplayFormat.temperature(snapshot.temperature, unit: temperatureUnit))
                .font(.system(size: family == .systemSmall ? 42 : 50, weight: .medium, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text("Ощущается как \(WeatherDisplayFormat.temperature(snapshot.feelsLike, unit: temperatureUnit))")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)

            if family == .systemMedium {
                Spacer(minLength: 0)
                Text("Обновлено \(WeatherDisplayFormat.time(snapshot.updatedAt, timeZoneOffset: snapshot.timeZoneOffset, format: clockFormat))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(family == .systemSmall ? 4 : 6)
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "cloud.sun.fill")
                .font(.title)
                .foregroundStyle(.yellow)
            Text("Погода")
                .font(.headline)
            Text("Откройте приложение, чтобы загрузить данные")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(6)
    }
}

struct WeatherWidget: Widget {
    let kind = "WeatherWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeatherWidgetProvider()) { entry in
            WeatherWidgetView(entry: entry)
        }
        .configurationDisplayName("Погода")
        .description("Текущая погода в первом избранном городе, а если избранного нет — в последнем просмотренном.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct WeatherWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeatherWidget()
    }
}
