@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
package struct AppIntentAction: Sendable {
    package let typeName: String
    package let persistentIdentifier: String
    package let resultTypeName: String
    package let opensAppWhenRun: Bool
    package let hasExecutableResult: Bool
    private let operation: @Sendable () async throws -> Void

    package init<Intent>(_ intent: Intent) where Intent: AppIntent {
        typeName = String(reflecting: Intent.self)
        persistentIdentifier = Intent.persistentIdentifier
        resultTypeName = String(reflecting: Intent.PerformResult.self)
        opensAppWhenRun = Intent.openAppWhenRun
        hasExecutableResult = (
            Intent.PerformResult.self is any WidgetExecutableIntentResult.Type
        )
        operation = {
            _ = try await intent.perform()
        }
    }

    package func perform() async throws {
        try await operation()
    }
}
