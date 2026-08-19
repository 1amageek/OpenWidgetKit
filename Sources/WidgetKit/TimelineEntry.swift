import OpenFoundation

public protocol TimelineEntry {
    var date: Date { get }
    var relevance: TimelineEntryRelevance? { get }
}

extension TimelineEntry {
    public var relevance: TimelineEntryRelevance? { nil }
}
