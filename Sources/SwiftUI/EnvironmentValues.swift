import OpenWidgetRuntime

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct EnvironmentValues: CustomStringConvertible {
    private var values: [ObjectIdentifier: Any]

    public init() {
        values = [:]
    }

    public subscript<Key>(key: Key.Type) -> Key.Value where Key: EnvironmentKey {
        get {
            values[ObjectIdentifier(key)] as? Key.Value ?? Key.defaultValue
        }
        set {
            values[ObjectIdentifier(key)] = newValue
        }
    }

    public var description: String {
        "EnvironmentValues(\(values.count) value(s))"
    }

    package init(snapshot: WidgetEnvironmentSnapshot) {
        self.init()
        colorScheme = switch snapshot.colorScheme {
        case .light: .light
        case .dark: .dark
        }
        widgetFamily = snapshot.family
        displayScale = snapshot.displayScale
    }

    package var widgetSnapshot: WidgetEnvironmentSnapshot {
        let runtimeColorScheme: WidgetEnvironmentSnapshot.ColorScheme
        switch colorScheme {
        case .light:
            runtimeColorScheme = .light
        case .dark:
            runtimeColorScheme = .dark
        }
        return WidgetEnvironmentSnapshot(
            colorScheme: runtimeColorScheme,
            family: widgetFamily,
            displayScale: displayScale
        )
    }
}

private enum ColorSchemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: ColorScheme = .light
}

private enum DisplayScaleEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

private enum WidgetFamilyEnvironmentKey: EnvironmentKey {
    static let defaultValue: RuntimeWidgetFamily? = nil
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension EnvironmentValues {
    public var colorScheme: ColorScheme {
        get { self[ColorSchemeEnvironmentKey.self] }
        set { self[ColorSchemeEnvironmentKey.self] = newValue }
    }

    public var displayScale: CGFloat {
        get { self[DisplayScaleEnvironmentKey.self] }
        set { self[DisplayScaleEnvironmentKey.self] = newValue }
    }

    package var widgetFamily: RuntimeWidgetFamily? {
        get { self[WidgetFamilyEnvironmentKey.self] }
        set { self[WidgetFamilyEnvironmentKey.self] = newValue }
    }
}
