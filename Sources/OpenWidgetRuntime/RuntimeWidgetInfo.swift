package struct RuntimeWidgetInfo: Hashable, Sendable {
    package let instanceID: String
    package let kind: String
    package let family: RuntimeWidgetFamily

    package init(
        instanceID: String,
        kind: String,
        family: RuntimeWidgetFamily
    ) {
        self.instanceID = instanceID
        self.kind = kind
        self.family = family
    }
}
