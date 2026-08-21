package struct WidgetAction: Sendable {
    package let id: WidgetActionID
    package let handlerIdentity: String
    private let operation: @Sendable () async throws -> Void

    package init(
        id: WidgetActionID,
        handlerIdentity: String,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        self.id = id
        self.handlerIdentity = handlerIdentity
        self.operation = operation
    }

    package func perform() async throws {
        try await operation()
    }
}
