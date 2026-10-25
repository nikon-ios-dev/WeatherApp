import SwiftUI

struct WeatherAnimatedBackground: View {
    let symbol: String
    var isNight = false
    var isActive = true

    private var condition: Condition {
        switch symbol {
        case "sun.max.fill", "moon.stars.fill":
            return .clear
        case "cloud.sun.fill", "cloud.moon.fill":
            return .partlyCloudy
        case "cloud.rain.fill", "cloud.drizzle.fill", "cloud.bolt.rain.fill":
            return .rain
        case "cloud.snow.fill":
            return .snow
        case "cloud.fog.fill":
            return .fog
        default:
            return .cloudy
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                LinearGradient(
                    colors: condition.gradient(isNight: isNight),
                    startPoint: .top,
                    endPoint: .bottom
                )

                Canvas { context, size in
                    switch condition {
                    case .clear:
                        if isNight {
                            drawNightSky(in: &context, size: size, time: time)
                        } else {
                            drawSun(in: &context, size: size, time: time)
                        }
                    case .partlyCloudy:
                        if isNight {
                            drawNightSky(in: &context, size: size, time: time)
                        } else {
                            drawSun(in: &context, size: size, time: time)
                        }
                        drawClouds(in: &context, size: size, time: time, isFog: false)
                    case .rain:
                        drawClouds(in: &context, size: size, time: time, isFog: false)
                        drawRain(in: &context, size: size, time: time)
                    case .snow:
                        drawClouds(in: &context, size: size, time: time, isFog: false)
                        drawSnow(in: &context, size: size, time: time)
                    case .cloudy, .fog:
                        drawClouds(in: &context, size: size, time: time, isFog: condition == .fog)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.8), value: condition)
            .animation(.easeInOut(duration: 0.8), value: isNight)
            .ignoresSafeArea()
        }
        .accessibilityHidden(true)
    }

    private func drawSun(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let center = CGPoint(x: size.width * 0.78, y: size.height * 0.2)
        let pulse = 1 + 0.05 * sin(time * 1.2)
        let radius = min(size.width, size.height) * 0.09 * pulse

        for layer in stride(from: 3.0, through: 1.0, by: -1.0) {
            let glowRadius = radius * layer * 1.7
            let glowRect = CGRect(
                x: center.x - glowRadius,
                y: center.y - glowRadius,
                width: glowRadius * 2,
                height: glowRadius * 2
            )
            context.fill(
                Path(ellipseIn: glowRect),
                with: .color(.yellow.opacity(0.025 / layer))
            )
        }

        var rays = Path()
        let rotation = time * 0.08
        for index in 0..<12 {
            let angle = rotation + Double(index) * .pi / 6
            let inner = radius * 1.25
            let outer = radius * (1.55 + 0.08 * sin(time + Double(index)))
            rays.move(to: CGPoint(
                x: center.x + cos(angle) * inner,
                y: center.y + sin(angle) * inner
            ))
            rays.addLine(to: CGPoint(
                x: center.x + cos(angle) * outer,
                y: center.y + sin(angle) * outer
            ))
        }
        context.stroke(rays, with: .color(.yellow.opacity(0.5)), lineWidth: 2)

        let sunRect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fill(Path(ellipseIn: sunRect), with: .color(.yellow.opacity(0.88)))
    }

    private func drawNightSky(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        for index in 0..<70 {
            let seed = Double((index * 47) % 103) / 103
            let x = seed * size.width
            let y = Double((index * 31) % 89) / 100 * size.height * 0.68
            let twinkle = 0.35 + 0.5 * (0.5 + 0.5 * sin(time * 1.3 + seed * 40))
            let radius = CGFloat(1 + index % 3)
            let star = CGRect(x: x, y: y, width: radius, height: radius)
            context.fill(Path(ellipseIn: star), with: .color(.white.opacity(twinkle)))
        }

        let center = CGPoint(x: size.width * 0.78, y: size.height * 0.2)
        let radius = min(size.width, size.height) * 0.07
        let moonRect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fill(Path(ellipseIn: moonRect), with: .color(Color(red: 0.91, green: 0.93, blue: 1)))

        let shadowRect = moonRect.offsetBy(dx: radius * 0.42, dy: -radius * 0.24)
        context.fill(
            Path(ellipseIn: shadowRect),
            with: .color(Color(red: 0.18, green: 0.28, blue: 0.48))
        )
    }

    private func drawRain(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        for index in 0..<54 {
            let seed = Double((index * 37) % 101) / 101
            let x = seed * size.width
            let speed = 0.22 + Double(index % 5) * 0.035
            let progress = (seed + time * speed).truncatingRemainder(dividingBy: 1)
            let y = progress * (size.height + 30) - 15
            var drop = Path()
            drop.move(to: CGPoint(x: x, y: y))
            drop.addLine(to: CGPoint(x: x - 7, y: y + 17))
            context.stroke(drop, with: .color(.white.opacity(0.3)), lineWidth: 1.4)
        }
    }

    private func drawSnow(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        for index in 0..<42 {
            let seed = Double((index * 43) % 103) / 103
            let drift = sin(time * 0.55 + seed * 18) * 18
            let x = seed * size.width + drift
            let speed = 0.025 + Double(index % 4) * 0.009
            let progress = (seed + time * speed).truncatingRemainder(dividingBy: 1)
            let y = progress * (size.height + 12) - 6
            let diameter = 2 + CGFloat(index % 4)
            let flake = CGRect(x: x, y: y, width: diameter, height: diameter)
            context.fill(Path(ellipseIn: flake), with: .color(.white.opacity(0.75)))
        }
    }

    private func drawClouds(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        isFog: Bool
    ) {
        let cloudCount = isFog ? 4 : 5
        for index in 0..<cloudCount {
            let seed = Double(index) / Double(cloudCount)
            let width = size.width * (isFog ? 0.62 : 0.52)
            let x = (seed * (size.width + width) + time * (isFog ? 2 : 4))
                .truncatingRemainder(dividingBy: size.width + width) - width
            let y = size.height * (0.20 + Double(index % 4) * 0.14)
                + sin(time * 0.2 + seed * 8) * 9
            let cloudHeight = isFog ? 50.0 : 70.0
            let tone = isNight
                ? Color(red: 0.62, green: 0.70, blue: 0.82)
                : Color(red: 0.94, green: 0.97, blue: 1)
            let opacity = isFog ? 0.25 : 0.31

            var cloud = Path()
            cloud.addEllipse(in: CGRect(x: x + width * 0.02, y: y + cloudHeight * 0.34, width: width * 0.58, height: cloudHeight * 0.58))
            cloud.addEllipse(in: CGRect(x: x + width * 0.22, y: y + cloudHeight * 0.05, width: width * 0.34, height: cloudHeight * 0.78))
            cloud.addEllipse(in: CGRect(x: x + width * 0.43, y: y + cloudHeight * 0.22, width: width * 0.32, height: cloudHeight * 0.62))
            cloud.addEllipse(in: CGRect(x: x + width * 0.62, y: y + cloudHeight * 0.35, width: width * 0.31, height: cloudHeight * 0.5))
            context.fill(cloud, with: .color(tone.opacity(opacity)))
        }
    }

    private enum Condition: Equatable {
        case clear
        case partlyCloudy
        case rain
        case snow
        case cloudy
        case fog

        func gradient(isNight: Bool) -> [Color] {
            switch self {
            case .clear:
                if isNight {
                    return [
                        Color(red: 0.035, green: 0.08, blue: 0.19),
                        Color(red: 0.12, green: 0.20, blue: 0.37)
                    ]
                }
                return [
                    Color(red: 0.16, green: 0.43, blue: 0.82),
                    Color(red: 0.42, green: 0.76, blue: 0.96)
                ]
            case .partlyCloudy:
                if isNight {
                    return [
                        Color(red: 0.07, green: 0.13, blue: 0.25),
                        Color(red: 0.22, green: 0.31, blue: 0.46)
                    ]
                }
                return [
                    Color(red: 0.22, green: 0.50, blue: 0.83),
                    Color(red: 0.55, green: 0.75, blue: 0.91)
                ]
            case .rain:
                return [
                    isNight ? Color(red: 0.06, green: 0.10, blue: 0.19) : Color(red: 0.16, green: 0.25, blue: 0.43),
                    isNight ? Color(red: 0.20, green: 0.27, blue: 0.39) : Color(red: 0.34, green: 0.48, blue: 0.64)
                ]
            case .snow:
                return [
                    isNight ? Color(red: 0.10, green: 0.17, blue: 0.29) : Color(red: 0.39, green: 0.58, blue: 0.75),
                    isNight ? Color(red: 0.29, green: 0.39, blue: 0.52) : Color(red: 0.69, green: 0.82, blue: 0.91)
                ]
            case .cloudy:
                return [
                    isNight ? Color(red: 0.08, green: 0.13, blue: 0.23) : Color(red: 0.27, green: 0.39, blue: 0.55),
                    isNight ? Color(red: 0.22, green: 0.30, blue: 0.42) : Color(red: 0.52, green: 0.64, blue: 0.75)
                ]
            case .fog:
                return [
                    isNight ? Color(red: 0.12, green: 0.16, blue: 0.23) : Color(red: 0.42, green: 0.51, blue: 0.61),
                    isNight ? Color(red: 0.29, green: 0.34, blue: 0.40) : Color(red: 0.68, green: 0.74, blue: 0.78)
                ]
            }
        }
    }
}
