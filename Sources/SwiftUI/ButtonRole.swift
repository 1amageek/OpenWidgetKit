import OpenWidgetRuntime

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct ButtonRole: Equatable, Sendable {
    package enum Kind: Equatable, Sendable {
        case destructive
        case cancel
        case confirm
        case close
    }

    package let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let destructive = ButtonRole(kind: .destructive)
    public static let cancel = ButtonRole(kind: .cancel)

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public static let confirm = ButtonRole(kind: .confirm)

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public static let close = ButtonRole(kind: .close)

    package var widgetValue: WidgetActionRole {
        switch kind {
        case .destructive: .destructive
        case .cancel: .cancel
        case .confirm: .confirm
        case .close: .close
        }
    }
}
