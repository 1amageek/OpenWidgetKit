import OpenWidgetRuntime

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct Image: Equatable, Sendable {
    package let resource: WidgetResource
    package let label: WidgetText?
    package let isDecorative: Bool

    public init(_ name: String, bundle: Bundle? = nil) {
        resource = .namedImage(
            name: name,
            bundleIdentifier: Text.bundleIdentity(bundle)
        )
        label = nil
        isDecorative = false
    }

    public init(_ name: String, bundle: Bundle? = nil, label: Text) {
        resource = .namedImage(
            name: name,
            bundleIdentifier: Text.bundleIdentity(bundle)
        )
        self.label = label.widgetValue
        isDecorative = false
    }

    public init(decorative name: String, bundle: Bundle? = nil) {
        resource = .namedImage(
            name: name,
            bundleIdentifier: Text.bundleIdentity(bundle)
        )
        label = nil
        isDecorative = true
    }

    @available(macOS 11.0, *)
    public init(systemName: String) {
        resource = .systemImage(name: systemName)
        label = nil
        isDecorative = false
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension Image: WidgetNodeConvertible {
    package func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        switch resource {
        case .namedImage(let name, _), .systemImage(let name):
            guard !name.isEmpty else {
                throw WidgetSemanticError.invalidResourceName
            }
        }
        let resourceID = context.register(resource)
        let image = WidgetImage(
            resourceID: resourceID,
            label: label,
            isDecorative: isDecorative
        )
        return [WidgetNode(id: context.path, kind: .image(image))]
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension Image: View {
    public typealias Body = Never
}
