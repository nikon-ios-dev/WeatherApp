import MapKit
import SwiftUI

private enum WeatherMapLayer: String, CaseIterable, Identifiable {
    case precipitation
    case clouds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .precipitation: "Осадки"
        case .clouds: "Облачность"
        }
    }
}

struct WeatherMapSheet: View {
    let cityName: String
    let latitude: Double
    let longitude: Double

    @State private var selectedLayer = WeatherMapLayer.precipitation
    @State private var rainTileTemplate: String?
    @State private var radarError: String?
    @State private var isLoadingRadar = false

    private var cloudTileTemplate: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "OPENWEATHERMAP_API_KEY") as? String,
              !key.isEmpty else {
            return nil
        }
        return "https://tile.openweathermap.org/map/clouds_new/{z}/{x}/{y}.png?appid=\(key)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Слой карты", selection: $selectedLayer) {
                    ForEach(WeatherMapLayer.allCases) { layer in
                        Text(layer.title).tag(layer)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                WeatherTileMap(
                    latitude: latitude,
                    longitude: longitude,
                    cityName: cityName,
                    tileTemplate: selectedLayer == .precipitation
                        ? rainTileTemplate
                        : cloudTileTemplate
                )
                .overlay(alignment: .top) {
                    if isLoadingRadar && selectedLayer == .precipitation {
                        ProgressView("Загружаем радар…")
                            .padding(10)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.top, 12)
                    } else if let radarError, selectedLayer == .precipitation {
                        Text(radarError)
                            .font(.caption)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                            .padding(.top, 12)
                    } else if selectedLayer == .clouds && cloudTileTemplate == nil {
                        Text("Для слоя облачности требуется API-ключ OpenWeatherMap.")
                            .font(.caption)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                            .padding(.top, 12)
                    }
                }

                Text("Радар: RainViewer · Облачность: OpenWeatherMap")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .navigationTitle(cityName)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await loadRadar()
        }
    }

    @MainActor
    private func loadRadar() async {
        isLoadingRadar = true
        defer { isLoadingRadar = false }
        do {
            rainTileTemplate = try await RainViewerService.latestTileTemplate()
            radarError = nil
        } catch {
            radarError = "Не удалось загрузить радар: \(error.localizedDescription)"
        }
    }
}

private struct WeatherTileMap: UIViewRepresentable {
    let latitude: Double
    let longitude: Double
    let cityName: String
    let tileTemplate: String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .mutedStandard
        mapView.pointOfInterestFilter = .excludingAll

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        mapView.setRegion(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6)
            ),
            animated: false
        )
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = cityName
        mapView.addAnnotation(annotation)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        guard context.coordinator.currentTemplate != tileTemplate else { return }
        context.coordinator.currentTemplate = tileTemplate
        mapView.overlays
            .filter { $0 is MKTileOverlay }
            .forEach(mapView.removeOverlay)

        guard let tileTemplate else { return }
        let overlay = MKTileOverlay(urlTemplate: tileTemplate)
        overlay.canReplaceMapContent = false
        overlay.minimumZ = 0
        overlay.maximumZ = 12
        mapView.addOverlay(overlay, level: .aboveLabels)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var currentTemplate: String?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tileOverlay = overlay as? MKTileOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
            renderer.alpha = 0.72
            return renderer
        }
    }
}

private enum RainViewerService {
    private static let endpoint = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!

    static func latestTileTemplate() async throws -> String {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw RainViewerError.invalidResponse
        }
        let payload = try JSONDecoder().decode(Response.self, from: data)
        guard let frame = payload.radar.past.last else {
            throw RainViewerError.noRadarFrames
        }
        return "\(payload.host)\(frame.path)/256/{z}/{x}/{y}/2/1_1.png"
    }

    private struct Response: Decodable {
        let host: String
        let radar: Radar

        struct Radar: Decodable {
            let past: [Frame]
        }

        struct Frame: Decodable {
            let path: String
        }
    }

    private enum RainViewerError: LocalizedError {
        case invalidResponse
        case noRadarFrames

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "Сервер радара вернул некорректный ответ."
            case .noRadarFrames:
                "Сейчас нет доступных радиолокационных кадров."
            }
        }
    }
}
