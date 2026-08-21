import AppIntents
import OpenWidgetRuntime

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
nonisolated public struct Button<Label>: View where Label: View {
    public typealias Body = Never

    private let label: Label
    private let intent: AppIntentAction
    private let role: ButtonRole?

    nonisolated public init<Intent>(
        intent: Intent,
        @ViewBuilder label: () -> Label
    ) where Intent: AppIntent {
        self.label = label()
        self.intent = AppIntentAction(intent)
        role = nil
    }

    nonisolated public init(
        role: ButtonRole?,
        intent: some AppIntent,
        @ViewBuilder label: () -> Label
    ) {
        self.label = label()
        self.intent = AppIntentAction(intent)
        self.role = role
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension Button where Label == Text {
    nonisolated public init(
        _ titleKey: LocalizedStringKey,
        intent: some AppIntent
    ) {
        self.init(intent: intent) { Text(titleKey) }
    }

    @_alwaysEmitIntoClient
    @_disfavoredOverload
    nonisolated public init(
        _ titleResource: LocalizedStringResource,
        intent: some AppIntent
    ) {
        self.init(intent: intent) { Text(titleResource) }
    }

    @_disfavoredOverload
    nonisolated public init<Title>(
        _ title: Title,
        intent: some AppIntent
    ) where Title: StringProtocol {
        self.init(intent: intent) { Text(title) }
    }

    nonisolated public init(
        _ titleKey: LocalizedStringKey,
        role: ButtonRole?,
        intent: some AppIntent
    ) {
        self.init(role: role, intent: intent) { Text(titleKey) }
    }

    @_alwaysEmitIntoClient
    @_disfavoredOverload
    nonisolated public init(
        _ titleResource: LocalizedStringResource,
        role: ButtonRole?,
        intent: some AppIntent
    ) {
        self.init(role: role, intent: intent) { Text(titleResource) }
    }

    @_disfavoredOverload
    nonisolated public init(
        _ title: some StringProtocol,
        role: ButtonRole?,
        intent: some AppIntent
    ) {
        self.init(role: role, intent: intent) { Text(title) }
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension Button: WidgetNodeConvertible {
    @MainActor
    package func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        guard let title = label as? Text else {
            throw WidgetSemanticError.unsupportedView(
                typeName: "Button label \(String(reflecting: Label.self))"
            )
        }
        let id = WidgetActionID(nodeID: context.path)
        let intent = intent
        guard !intent.opensAppWhenRun else {
            throw WidgetSemanticError.unsupportedAppIntentMode(
                typeName: intent.typeName
            )
        }
        guard intent.hasExecutableResult else {
            throw WidgetSemanticError.unsupportedAppIntentResult(
                typeName: intent.resultTypeName
            )
        }
        try context.register(
            WidgetAction(
                id: id,
                handlerIdentity: intent.persistentIdentifier,
                operation: { try await intent.perform() }
            )
        )
        return [
            WidgetNode(
                id: context.path,
                kind: .action(
                    WidgetActionDescriptor(
                        id: id,
                        title: title.widgetValue,
                        role: role?.widgetValue ?? .standard
                    )
                )
            )
        ]
    }
}
