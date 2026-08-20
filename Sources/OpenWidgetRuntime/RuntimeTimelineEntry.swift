import OpenFoundation

package struct RuntimeTimelineEntry: Equatable, Sendable {
    package let date: Date
    package let document: WidgetDocument
    package let additionalDocuments: [WidgetDocument]

    package var documents: [WidgetDocument] {
        [document] + additionalDocuments
    }

    package init(
        date: Date,
        document: WidgetDocument,
        additionalDocuments: [WidgetDocument] = []
    ) {
        self.date = date
        self.document = document
        self.additionalDocuments = additionalDocuments
    }
}
