@MainActor
package struct RuntimeWidgetRegistry: Sendable {
    private let definitionsByKind: [String: RuntimeWidgetDefinition]

    package let definitions: [RuntimeWidgetDefinition]

    package init(definitions: [RuntimeWidgetDefinition]) throws {
        var indexed: [String: RuntimeWidgetDefinition] = [:]
        for definition in definitions {
            guard indexed[definition.kind] == nil else {
                throw WidgetRuntimeError.duplicateKind(definition.kind)
            }
            indexed[definition.kind] = definition
        }
        self.definitions = definitions
        definitionsByKind = indexed
    }

    package func definition(for kind: String) -> RuntimeWidgetDefinition? {
        definitionsByKind[kind]
    }
}
