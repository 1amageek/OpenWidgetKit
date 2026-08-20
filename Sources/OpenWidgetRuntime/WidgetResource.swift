package enum WidgetResource: Equatable, Sendable {
    case namedImage(name: String, bundleIdentifier: String?)
    case systemImage(name: String)

    package var id: WidgetResourceID {
        switch self {
        case .namedImage(let name, let bundleIdentifier):
            WidgetResourceID(
                storage: .namedImage(
                    name: name,
                    bundleIdentifier: bundleIdentifier
                )
            )
        case .systemImage(let name):
            WidgetResourceID(storage: .systemImage(name: name))
        }
    }
}
