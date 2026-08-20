import OpenWidgetRuntime

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct HorizontalAlignment: Equatable {
    private enum Storage: Equatable {
        case leading
        case center
        case trailing
    }

    private let storage: Storage

    private init(storage: Storage) {
        self.storage = storage
    }

    // These values are immutable. The annotation preserves Apple's
    // non-Sendable public alignment types under Swift 6 checking.
    nonisolated(unsafe) public static let leading = HorizontalAlignment(storage: .leading)
    nonisolated(unsafe) public static let center = HorizontalAlignment(storage: .center)
    nonisolated(unsafe) public static let trailing = HorizontalAlignment(storage: .trailing)

    package var widgetValue: WidgetHorizontalAlignment {
        switch storage {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct VerticalAlignment: Equatable {
    private enum Storage: Equatable {
        case top
        case center
        case bottom
        case firstTextBaseline
        case lastTextBaseline
    }

    private let storage: Storage

    private init(storage: Storage) {
        self.storage = storage
    }

    nonisolated(unsafe) public static let top = VerticalAlignment(storage: .top)
    nonisolated(unsafe) public static let center = VerticalAlignment(storage: .center)
    nonisolated(unsafe) public static let bottom = VerticalAlignment(storage: .bottom)
    nonisolated(unsafe) public static let firstTextBaseline = VerticalAlignment(storage: .firstTextBaseline)
    nonisolated(unsafe) public static let lastTextBaseline = VerticalAlignment(storage: .lastTextBaseline)

    package var widgetValue: WidgetVerticalAlignment {
        switch storage {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        case .firstTextBaseline: .firstTextBaseline
        case .lastTextBaseline: .lastTextBaseline
        }
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct Alignment: Equatable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment

    public init(
        horizontal: HorizontalAlignment,
        vertical: VerticalAlignment
    ) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    nonisolated(unsafe) public static let center = Alignment(horizontal: .center, vertical: .center)
    nonisolated(unsafe) public static let leading = Alignment(horizontal: .leading, vertical: .center)
    nonisolated(unsafe) public static let trailing = Alignment(horizontal: .trailing, vertical: .center)
    nonisolated(unsafe) public static let top = Alignment(horizontal: .center, vertical: .top)
    nonisolated(unsafe) public static let bottom = Alignment(horizontal: .center, vertical: .bottom)
    nonisolated(unsafe) public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    nonisolated(unsafe) public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    nonisolated(unsafe) public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)
    nonisolated(unsafe) public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)

    package var widgetValue: WidgetAlignment {
        WidgetAlignment(
            horizontal: horizontal.widgetValue,
            vertical: vertical.widgetValue
        )
    }
}
