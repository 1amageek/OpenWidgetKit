package enum WidgetRuntimeOperation: String, Equatable, Sendable {
    case startup
    case currentConfigurations
    case reloadTimelines
    case reloadAllTimelines
    case create
    case recover
    case activate
    case deactivate
    case contextChange
    case delete
    case action
    case timelineRequest
    case invalidate
    case update
    case remove
    case shutdown
}
