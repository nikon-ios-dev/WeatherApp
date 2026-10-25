# WeatherApp

SwiftUI weather screen for iOS 17 and later.

## OpenWeatherMap API

The app requests current weather and city suggestions from OpenWeatherMap. Forecasts and environmental data come from Open-Meteo.

To build the project:

1. Get an API key from [OpenWeatherMap](https://openweathermap.org/api).
2. Copy `WeatherApp/Secrets.example.xcconfig` to `WeatherApp/Secrets.xcconfig`.
3. Replace `YOUR_OPENWEATHERMAP_API_KEY` in the copied file with your key.
4. Open `WeatherApp.xcodeproj` in Xcode and run the `WeatherApp` scheme.

`WeatherApp/Secrets.xcconfig` is excluded from version control. Never commit your personal API key. Keys included in a distributed app can be extracted; restrict the key with the provider or use a backend proxy for production.

The main screen shows humidity, wind speed and compass direction with gusts, pressure, sunrise and sunset times, visibility, a 12-hour forecast with hourly and daily precipitation chances, UV index, air-quality index, PM2.5/PM10 and birch/grass/ragweed pollen forecasts, plus a 7-day forecast.

Temperature, wind-speed, and clock-format preferences can be changed from the settings button on the main screen. The settings are shared with the Home Screen widget. Settings also let users enable a local rain/snow alert when precipitation probability reaches 50% in the next hour; iOS notification permission is required.

Favorite cities are stored locally in `UserDefaults`. Tap the star beside the current city to save or remove it, then tap a saved city chip to load its weather.

## Weather widget

The `WeatherWidget` extension provides small and medium Home Screen widgets. It displays the first saved favorite city, or the last viewed city when there are no favorites, and updates whenever the app successfully refreshes the weather. To share that data, the app and widget use the `group.com.example.WeatherApp` App Group; enable this same App Group for both targets in the Apple Developer account when signing for a physical device.

The map opens from the main weather screen and can switch between RainViewer precipitation radar and the OpenWeatherMap cloud layer.

The key is added to the app bundle at build time, so it can be extracted from a distributed app. Do not rely on this as secret storage for a production app; restrict the key with the provider or use a backend proxy. If you share or publish a key, revoke it and create a replacement.

## Open in VS Code

Open `WeatherApp.code-workspace` from this folder. VS Code will show the app source and recommend the Swift extension.

Use **Terminal → Run Build Task…** or press **Cmd+Shift+B** to build for the iOS Simulator with Xcode.

## Open in Xcode

Open `WeatherApp.xcodeproj`, select the `WeatherApp` scheme and an iPhone Simulator, then run the app.
