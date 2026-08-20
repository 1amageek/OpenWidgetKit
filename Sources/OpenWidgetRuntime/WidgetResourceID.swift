package struct WidgetResourceID: Hashable, Sendable {
    package enum Storage: Hashable, Sendable {
        case namedImage(name: String, bundleIdentifier: String?)
        case systemImage(name: String)
    }

    package let storage: Storage

    package init(storage: Storage) {
        self.storage = storage
    }
}
