import OpenFoundation

public struct TimelineEntryRelevance: Codable, Hashable {
    public var score: Float
    public var duration: TimeInterval

    public init(score: Float, duration: TimeInterval = 0.0) {
        self.score = score
        self.duration = duration
    }
}
