package protocol WindowsWidgetActionHost: Sendable {
    func beginAction(
        instanceID: String,
        verb: String,
        data: String,
        customState: String
    ) async throws -> WindowsWidgetActionExecution
}
