import OpenWidgetRuntime

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct Color: Hashable, CustomStringConvertible, Sendable, ShapeStyle {
    public enum RGBColorSpace: Hashable, Sendable {
        case sRGB
        case sRGBLinear
        case displayP3
    }

    package let widgetValue: WidgetColor

    private init(standard: WidgetColor.Standard) {
        widgetValue = .standard(standard)
    }

    public init(
        _ colorSpace: RGBColorSpace = .sRGB,
        red: Double,
        green: Double,
        blue: Double,
        opacity: Double = 1
    ) {
        widgetValue = .rgba(
            colorSpace: colorSpace.widgetValue,
            red: red,
            green: green,
            blue: blue,
            opacity: opacity
        )
    }

    public init(
        _ colorSpace: RGBColorSpace = .sRGB,
        white: Double,
        opacity: Double = 1
    ) {
        self.init(
            colorSpace,
            red: white,
            green: white,
            blue: white,
            opacity: opacity
        )
    }

    public init(
        hue: Double,
        saturation: Double,
        brightness: Double,
        opacity: Double = 1
    ) {
        widgetValue = .hsba(
            hue: hue,
            saturation: saturation,
            brightness: brightness,
            opacity: opacity
        )
    }

    public static let red = Color(standard: .red)
    public static let orange = Color(standard: .orange)
    public static let yellow = Color(standard: .yellow)
    public static let green = Color(standard: .green)

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    public static let mint = Color(standard: .mint)

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    public static let teal = Color(standard: .teal)

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    public static let cyan = Color(standard: .cyan)

    public static let blue = Color(standard: .blue)

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    public static let indigo = Color(standard: .indigo)

    public static let purple = Color(standard: .purple)
    public static let pink = Color(standard: .pink)

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    public static let brown = Color(standard: .brown)

    public static let white = Color(standard: .white)
    public static let gray = Color(standard: .gray)
    public static let black = Color(standard: .black)
    public static let clear = Color(standard: .clear)
    public static let primary = Color(standard: .primary)
    public static let secondary = Color(standard: .secondary)

    public var description: String {
        String(describing: widgetValue)
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension Color.RGBColorSpace {
    package var widgetValue: WidgetColor.RGBColorSpace {
        switch self {
        case .sRGB: .sRGB
        case .sRGBLinear: .sRGBLinear
        case .displayP3: .displayP3
        }
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension Color: WidgetNodeConvertible {
    package func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        for (name, value) in widgetComponents {
            guard value.isFinite else {
                throw WidgetSemanticError.invalidColorComponent(component: name)
            }
        }
        return [WidgetNode(id: context.path, kind: .color(widgetValue))]
    }

    private var widgetComponents: [(String, Double)] {
        switch widgetValue {
        case .standard:
            []
        case .rgba(_, let red, let green, let blue, let opacity):
            [("red", red), ("green", green), ("blue", blue), ("opacity", opacity)]
        case .hsba(let hue, let saturation, let brightness, let opacity):
            [
                ("hue", hue),
                ("saturation", saturation),
                ("brightness", brightness),
                ("opacity", opacity)
            ]
        }
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension Color: View {
    public typealias Body = Never
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension ShapeStyle where Self == Color {
    public static var red: Color { .red }
    public static var orange: Color { .orange }
    public static var yellow: Color { .yellow }
    public static var green: Color { .green }
    public static var blue: Color { .blue }
    public static var purple: Color { .purple }
    public static var pink: Color { .pink }
    public static var white: Color { .white }
    public static var gray: Color { .gray }
    public static var black: Color { .black }
    public static var clear: Color { .clear }
}
