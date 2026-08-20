import OpenWidgetRuntime

nonisolated struct EnvironmentWritingView<Content, Value>: View where Content: View {
    typealias Body = Never

    let content: Content
    let keyPath: WritableKeyPath<EnvironmentValues, Value>
    let value: Value
}

extension EnvironmentWritingView: WidgetNodeConvertible {
    @MainActor
    package func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        let previousEnvironment = context.environment
        defer { context.environment = previousEnvironment }

        if let colorSchemeKeyPath = keyPath as? WritableKeyPath<
            EnvironmentValues,
            ColorScheme
        >,
        colorSchemeKeyPath == \EnvironmentValues.colorScheme,
        let colorScheme = value as? ColorScheme {
            context.environment.colorScheme = switch colorScheme {
            case .light: .light
            case .dark: .dark
            }
            return try lowerWidgetView(content, in: &context)
        }

        if let displayScaleKeyPath = keyPath as? WritableKeyPath<
            EnvironmentValues,
            CGFloat
        >,
        displayScaleKeyPath == \EnvironmentValues.displayScale,
        let displayScale = value as? CGFloat {
            guard displayScale.isFinite, displayScale > 0 else {
                throw WidgetSemanticError.invalidDisplayScale
            }
            context.environment.displayScale = displayScale
            return try lowerWidgetView(content, in: &context)
        }

        throw WidgetSemanticError.unsupportedEnvironmentKey
    }
}
