package enum TimelineRuntimeError: Error, Equatable, Sendable {
    case emptyTimeline
    case nonFiniteEntryDate(index: Int)
    case entriesOutOfOrder(previousIndex: Int, index: Int)
    case nonFiniteReloadDate
}
