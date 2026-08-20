import OpenFoundation

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
public struct TimelineEntryRelevance: Codable, Hashable {
    public var score: Float
    public var duration: TimeInterval

    public init(score: Float, duration: TimeInterval = 0.0) {
        self.score = score
        self.duration = duration
    }
}
