package struct WidgetActionDescriptor: Equatable, Sendable {
    package let id: WidgetActionID
    package let title: WidgetText
    package let role: WidgetActionRole

    package init(
        id: WidgetActionID,
        title: WidgetText,
        role: WidgetActionRole
    ) {
        self.id = id
        self.title = title
        self.role = role
    }
}
