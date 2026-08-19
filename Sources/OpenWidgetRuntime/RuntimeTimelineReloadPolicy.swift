import OpenFoundation

package enum RuntimeTimelineReloadPolicy: Equatable, Sendable {
    case atEnd
    case after(Date)
    case never
}
