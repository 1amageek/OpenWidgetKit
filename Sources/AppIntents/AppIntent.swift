@_exported import OpenFoundation

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public protocol AppIntent: PersistentlyIdentifiable, Sendable {
    associatedtype PerformResult: IntentResult

    static var title: LocalizedStringResource { get }
    static var openAppWhenRun: Bool { get }

    init()

    func perform() async throws -> PerformResult
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
extension AppIntent {
    public static var openAppWhenRun: Bool { false }
}
