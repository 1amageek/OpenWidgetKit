import OpenFoundation

package struct RuntimeTimelineEntry: Equatable, Sendable {
    package let date: Date
    package let document: WidgetDocument

    package init(date: Date, document: WidgetDocument) {
        self.date = date
        self.document = document
    }
}
