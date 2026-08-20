package struct WidgetText: Equatable, Sendable {
    package enum Storage: Equatable, Sendable {
        case verbatim(String)
        case localized(
            key: String,
            tableName: String?,
            bundleIdentifier: String?,
            comment: String?,
            arguments: [String]
        )
    }

    package let storage: Storage
    package let font: WidgetFont?
    package let foregroundColor: WidgetColor?

    package init(
        storage: Storage,
        font: WidgetFont? = nil,
        foregroundColor: WidgetColor? = nil
    ) {
        self.storage = storage
        self.font = font
        self.foregroundColor = foregroundColor
    }
}
