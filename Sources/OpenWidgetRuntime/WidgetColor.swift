package enum WidgetColor: Hashable, Sendable {
    package enum RGBColorSpace: Hashable, Sendable {
        case sRGB
        case sRGBLinear
        case displayP3
    }

    package enum Standard: Hashable, Sendable {
        case red
        case orange
        case yellow
        case green
        case mint
        case teal
        case cyan
        case blue
        case indigo
        case purple
        case pink
        case brown
        case white
        case gray
        case black
        case clear
        case primary
        case secondary
    }

    case standard(Standard)
    case rgba(
        colorSpace: RGBColorSpace,
        red: Double,
        green: Double,
        blue: Double,
        opacity: Double
    )
    case hsba(
        hue: Double,
        saturation: Double,
        brightness: Double,
        opacity: Double
    )
}
