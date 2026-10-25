import SwiftUI

struct ContentView: View {
    @State private var cityName = "Москва"

    var body: some View {
        WeatherMainView(cityName: $cityName, isActive: true)
    }
}

#Preview {
    ContentView()
}
