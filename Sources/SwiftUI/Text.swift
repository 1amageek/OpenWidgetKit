import OpenWidgetRuntime

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct Text: Equatable, Sendable {
    private enum Storage: Equatable, Sendable {
        case verbatim(String)
        case localizedResource(LocalizedStringResource)
        case localized(
            key: String,
            tableName: String?,
            bundleIdentifier: String?,
            comment: String?,
            arguments: [String]
        )
    }

    private var storage: Storage
    private var selectedFont: Font?
    private var selectedForegroundColor: Color?

    public init(verbatim content: String) {
        storage = .verbatim(content)
        selectedFont = nil
        selectedForegroundColor = nil
    }

    @_disfavoredOverload
    public init<Content>(_ content: Content) where Content: StringProtocol {
        self.init(verbatim: String(content))
    }

    public init(
        _ key: LocalizedStringKey,
        tableName: String? = nil,
        bundle: Bundle? = nil,
        comment: StaticString? = nil
    ) {
        storage = .localized(
            key: key.key,
            tableName: tableName,
            bundleIdentifier: Self.bundleIdentity(bundle),
            comment: comment.map(String.init(describing:)),
            arguments: key.arguments
        )
        selectedFont = nil
        selectedForegroundColor = nil
    }

    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    @_disfavoredOverload
    public init(_ resource: LocalizedStringResource) {
        storage = .localizedResource(resource)
        selectedFont = nil
        selectedForegroundColor = nil
    }

    nonisolated public func font(_ font: Font?) -> Text {
        var copy = self
        copy.selectedFont = font
        return copy
    }

    nonisolated public func foregroundColor(_ color: Color?) -> Text {
        var copy = self
        copy.selectedForegroundColor = color
        return copy
    }

    package var widgetValue: WidgetText {
        let runtimeStorage: WidgetText.Storage
        switch storage {
        case .verbatim(let value):
            runtimeStorage = .verbatim(value)
        case .localizedResource(let resource):
            runtimeStorage = .localizedResource(resource)
        case .localized(
            let key,
            let tableName,
            let bundleIdentifier,
            let comment,
            let arguments
        ):
            runtimeStorage = .localized(
                key: key,
                tableName: tableName,
                bundleIdentifier: bundleIdentifier,
                comment: comment,
                arguments: arguments
            )
        }

        return WidgetText(
            storage: runtimeStorage,
            font: selectedFont?.widgetValue,
            foregroundColor: selectedForegroundColor?.widgetValue
        )
    }

    package static func bundleIdentity(_ bundle: Bundle?) -> String? {
        guard let bundle else { return nil }
        return bundle.bundleIdentifier ?? bundle.bundleURL.absoluteString
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension Text: WidgetNodeConvertible {
    package func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        [WidgetNode(id: context.path, kind: .text(widgetValue))]
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension Text: View {
    public typealias Body = Never
}
