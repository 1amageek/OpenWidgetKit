package struct RuntimeWidgetUpdate: Equatable, Sendable {
    package let instanceID: String
    package let kind: String
    package let family: RuntimeWidgetFamily
    package let generation: UInt64
    package let entry: RuntimeTimelineEntry

    package init(
        instanceID: String,
        kind: String,
        family: RuntimeWidgetFamily,
        generation: UInt64,
        entry: RuntimeTimelineEntry
    ) {
        self.instanceID = instanceID
        self.kind = kind
        self.family = family
        self.generation = generation
        self.entry = entry
    }
}
