package struct WindowsWidgetActionExecution: Sendable {
    private let task: Task<UInt64, Error>

    package init(
        operation: @escaping @Sendable () async throws -> UInt64
    ) {
        task = Task(operation: operation)
    }

    package func value() async throws -> UInt64 {
        try await task.value
    }
}
