import OpenFoundation
import OpenWidgetRuntime
import Synchronization

package final class AdaptiveCardCompiler: Sendable {
    private struct CacheEntry: Sendable {
        let templateJSON: String
        var lastAccess: UInt64
    }

    private struct CacheState: Sendable {
        var entries: [String: CacheEntry] = [:]
        var accessCounter: UInt64 = 0
    }

    private enum Axis {
        case vertical
        case horizontal
    }

    private struct TextStyle {
        var font: WidgetFont?
        var foregroundColor: WidgetColor?
        var lineLimit: Int?
    }

    private struct VariantOutput {
        let themeName: String
        let elements: [CanonicalJSON]
        let data: [String: CanonicalJSON]
        let resourceReferences: [AdaptiveCardResourceReference]
    }

    private struct VariantBuilder {
        let bindingNamespace: String
        let document: WidgetDocument
        let textResolver: any WidgetTextResolving
        let resourceResolver: any AdaptiveCardResourceResolving
        var nextBinding = 0
        var data: [String: CanonicalJSON] = [:]
        var resourceReferences: [AdaptiveCardResourceReference] = []

        mutating func bind(_ value: String) -> String {
            let key = "v\(nextBinding)"
            nextBinding += 1
            data[key] = .string(value)
            return "${\(bindingNamespace).\(key)}"
        }

        mutating func compile(
            node: WidgetNode,
            parentAxis: Axis,
            textStyle: TextStyle = TextStyle()
        ) throws -> [CanonicalJSON] {
            switch node.kind {
            case .empty:
                try requireNoChildren(node, kind: "EmptyView")
                return []
            case .text(let text):
                try requireNoChildren(node, kind: "Text")
                return [try compileText(text, inheritedStyle: textStyle)]
            case .image(let image):
                try requireNoChildren(node, kind: "Image")
                return [try compileImage(image)]
            case .color:
                throw AdaptiveCardCompilationError.unsupportedNode(
                    "A standalone Color has no equivalent Adaptive Cards element."
                )
            case .verticalStack(let alignment, let spacing):
                let items = try compileChildren(
                    node.children,
                    axis: .vertical,
                    spacing: spacing,
                    textStyle: textStyle
                )
                let object: [String: CanonicalJSON] = [
                    "type": .string("Container"),
                    "items": .array(
                        items.map {
                            applyingHorizontalAlignment(alignment, to: $0)
                        }
                    )
                ]
                return [.object(object)]
            case .horizontalStack(let alignment, let spacing):
                guard alignment != .firstTextBaseline,
                      alignment != .lastTextBaseline else {
                    throw AdaptiveCardCompilationError.unsupportedNode(
                        "Adaptive Cards columns do not preserve text-baseline HStack alignment."
                    )
                }
                let columns = try compileColumns(
                    node.children,
                    alignment: alignment,
                    spacing: spacing,
                    textStyle: textStyle
                )
                return [
                    .object([
                        "type": .string("ColumnSet"),
                        "columns": .array(columns)
                    ])
                ]
            case .group:
                return try node.children.flatMap {
                    try compile(
                        node: $0,
                        parentAxis: parentAxis,
                        textStyle: textStyle
                    )
                }
            case .spacer(let minLength):
                try requireNoChildren(node, kind: "Spacer")
                switch parentAxis {
                case .vertical:
                    var object: [String: CanonicalJSON] = [
                        "type": .string("Container"),
                        "items": .array([]),
                        "height": .string("stretch")
                    ]
                    if let minLength {
                        object["minHeight"] = .string(
                            try pixelLength(minLength, field: "Spacer.minLength")
                        )
                    }
                    return [
                        .object(object)
                    ]
                case .horizontal:
                    throw AdaptiveCardCompilationError.invalidDocument(
                        "A horizontal Spacer must be compiled as a Column."
                    )
                }
            case .divider:
                try requireNoChildren(node, kind: "Divider")
                return [
                    .object([
                        "type": .string("TextBlock"),
                        "text": .string(""),
                        "separator": .boolean(true),
                        "spacing": .string("none")
                    ])
                ]
            case .modified(let modifier):
                return try compileModified(
                    modifier,
                    children: node.children,
                    parentAxis: parentAxis,
                    inheritedStyle: textStyle
                )
            case .background(
                let alignment,
                let ignoredEdges,
                let foregroundCount
            ):
                return try compileBackground(
                    node,
                    alignment: alignment,
                    ignoredEdges: ignoredEdges,
                    foregroundCount: foregroundCount,
                    parentAxis: parentAxis,
                    textStyle: textStyle
                )
            }
        }

        private mutating func compileText(
            _ text: WidgetText,
            inheritedStyle: TextStyle
        ) throws -> CanonicalJSON {
            let resolved = try textResolver.resolve(text)
            var object: [String: CanonicalJSON] = [
                "type": .string("TextBlock"),
                "text": .string(bind(resolved)),
                "wrap": .boolean(true)
            ]
            let font = text.font ?? inheritedStyle.font
            if let font {
                let mapping = fontMapping(font)
                object["size"] = .string(mapping.size)
                object["weight"] = .string(mapping.weight)
            }
            let color = text.foregroundColor ?? inheritedStyle.foregroundColor
            if let color {
                let mapping = try textColorMapping(color)
                if let name = mapping.name {
                    object["color"] = .string(name)
                }
                if mapping.isSubtle {
                    object["isSubtle"] = .boolean(true)
                }
            }
            if let lineLimit = inheritedStyle.lineLimit {
                guard lineLimit > 0 else {
                    throw AdaptiveCardCompilationError.unsupportedModifier(
                        "Adaptive Cards maxLines requires a positive line limit."
                    )
                }
                object["maxLines"] = .integer(lineLimit)
            }
            return .object(object)
        }

        private mutating func compileImage(
            _ image: WidgetImage
        ) throws -> CanonicalJSON {
            guard image.isDecorative || image.label != nil else {
                throw AdaptiveCardCompilationError.unsupportedNode(
                    "A Windows image must be decorative or provide an explicit accessibility label."
                )
            }
            guard let resource = document.resources[image.resourceID] else {
                throw AdaptiveCardCompilationError.unresolvedResource(
                    "The image node references a resource absent from its document."
                )
            }
            let uri = try resourceResolver.resolve(resource)
            try validateResourceURI(uri)
            if !resourceReferences.contains(where: { $0.resource == resource }) {
                resourceReferences.append(
                    AdaptiveCardResourceReference(resource: resource, uri: uri)
                )
            }
            var object: [String: CanonicalJSON] = [
                "type": .string("Image"),
                "url": .string(bind(uri)),
                "size": .string("auto")
            ]
            if let label = image.label {
                object["altText"] = .string(bind(try textResolver.resolve(label)))
            } else if image.isDecorative {
                object["altText"] = .string("")
            }
            return .object(object)
        }

        private mutating func compileChildren(
            _ children: [WidgetNode],
            axis: Axis,
            spacing: CGFloat?,
            textStyle: TextStyle
        ) throws -> [CanonicalJSON] {
            let spacingName = try adaptiveSpacing(spacing)
            var elements: [CanonicalJSON] = []
            for child in children {
                let childElements = try compile(
                    node: child,
                    parentAxis: axis,
                    textStyle: textStyle
                )
                for element in childElements {
                    let positioned = elements.isEmpty || spacingName == nil
                        ? element
                        : element.setting("spacing", to: .string(spacingName!))
                    elements.append(positioned)
                }
            }
            return elements
        }

        private mutating func compileColumns(
            _ children: [WidgetNode],
            alignment: WidgetVerticalAlignment,
            spacing: CGFloat?,
            textStyle: TextStyle
        ) throws -> [CanonicalJSON] {
            let spacingName = try adaptiveSpacing(spacing)
            var columns: [CanonicalJSON] = []
            for child in children {
                var column: [String: CanonicalJSON]
                if case .spacer(let minLength) = child.kind {
                    try requireNoChildren(child, kind: "Spacer")
                    guard minLength == nil else {
                        throw AdaptiveCardCompilationError.unsupportedNode(
                            "Adaptive Cards columns cannot preserve a horizontal Spacer minimum length."
                        )
                    }
                    column = [
                        "type": .string("Column"),
                        "width": .string("stretch"),
                        "items": .array([])
                    ]
                } else {
                    let items = try compile(
                        node: child,
                        parentAxis: .vertical,
                        textStyle: textStyle
                    )
                    column = [
                        "type": .string("Column"),
                        "width": .string("auto"),
                        "items": .array(items),
                        "verticalContentAlignment": .string(
                            try verticalAlignment(alignment)
                        )
                    ]
                }
                if !columns.isEmpty, let spacingName {
                    column["spacing"] = .string(spacingName)
                }
                columns.append(.object(column))
            }
            return columns
        }

        private mutating func compileModified(
            _ modifier: WidgetModifier,
            children: [WidgetNode],
            parentAxis: Axis,
            inheritedStyle: TextStyle
        ) throws -> [CanonicalJSON] {
            var style = inheritedStyle
            switch modifier {
            case .font(let font):
                style.font = font
            case .foregroundColor(let color):
                style.foregroundColor = color
            case .lineLimit(let lineLimit):
                style.lineLimit = lineLimit
            case .padding:
                throw AdaptiveCardCompilationError.unsupportedModifier(
                    "Adaptive Cards 1.6 has no inner-padding contract equivalent to SwiftUI padding."
                )
            case .frame:
                throw AdaptiveCardCompilationError.unsupportedModifier(
                    "Adaptive Cards 1.6 cannot preserve the complete SwiftUI frame constraint contract."
                )
            }
            return try children.flatMap {
                try compile(
                    node: $0,
                    parentAxis: parentAxis,
                    textStyle: style
                )
            }
        }

        private mutating func compileBackground(
            _ node: WidgetNode,
            alignment: WidgetAlignment,
            ignoredEdges: WidgetEdge?,
            foregroundCount: Int,
            parentAxis: Axis,
            textStyle: TextStyle
        ) throws -> [CanonicalJSON] {
            guard foregroundCount >= 0,
                  foregroundCount <= node.children.count else {
                throw AdaptiveCardCompilationError.invalidDocument(
                    "A background node has an invalid foreground partition."
                )
            }
            let foreground = Array(node.children.prefix(foregroundCount))
            let background = Array(node.children.dropFirst(foregroundCount))
            guard background.count == 1,
                  case .color(let color) = background[0].kind,
                  background[0].children.isEmpty else {
                throw AdaptiveCardCompilationError.unsupportedNode(
                    "M4 supports background only when it is a single semantic Color."
                )
            }
            let foregroundItems = try foreground.flatMap {
                try compile(
                    node: $0,
                    parentAxis: parentAxis,
                    textStyle: textStyle
                )
            }.map {
                applyingHorizontalAlignment(alignment.horizontal, to: $0)
            }
            var object: [String: CanonicalJSON] = [
                "type": .string("Container"),
                "items": .array(foregroundItems),
                "verticalContentAlignment": .string(
                    try verticalAlignment(alignment.vertical)
                )
            ]
            if let style = try containerStyle(color) {
                object["style"] = .string(style)
            }
            if let ignoredEdges {
                guard ignoredEdges == .all else {
                    throw AdaptiveCardCompilationError.unsupportedModifier(
                        "Adaptive Cards bleed cannot represent a partial safe-area edge set."
                    )
                }
                object["bleed"] = .boolean(true)
            }
            return [.object(object)]
        }

        private func requireNoChildren(_ node: WidgetNode, kind: String) throws {
            guard node.children.isEmpty else {
                throw AdaptiveCardCompilationError.invalidDocument(
                    "\(kind) unexpectedly contains child nodes."
                )
            }
        }

        private func validateResourceURI(_ uri: String) throws {
            guard uri.hasPrefix("ms-appx:///"),
                  !uri.contains(".."),
                  !uri.contains("\\") else {
                throw AdaptiveCardCompilationError.unresolvedResource(
                    "M4 bundled resources require a normalized ms-appx:/// URI."
                )
            }
        }

        private func adaptiveSpacing(_ value: CGFloat?) throws -> String? {
            guard let value else { return nil }
            guard value.isFinite, value >= 0 else {
                throw AdaptiveCardCompilationError.invalidDocument(
                    "Stack spacing must be finite and nonnegative."
                )
            }
            switch value {
            case 0: return "none"
            case ...4: return "small"
            case ...8: return "default"
            case ...16: return "medium"
            case ...24: return "large"
            default: return "extraLarge"
            }
        }

        private func pixelLength(
            _ value: CGFloat,
            field: String
        ) throws -> String {
            guard value.isFinite, value >= 0 else {
                throw AdaptiveCardCompilationError.invalidDocument(
                    "\(field) must be finite and nonnegative."
                )
            }
            return "\(Double(value))px"
        }

        private func horizontalAlignment(
            _ value: WidgetHorizontalAlignment
        ) -> String {
            switch value {
            case .leading: "left"
            case .center: "center"
            case .trailing: "right"
            }
        }

        private func verticalAlignment(
            _ value: WidgetVerticalAlignment
        ) throws -> String {
            switch value {
            case .top: "top"
            case .center: "center"
            case .bottom: "bottom"
            case .firstTextBaseline, .lastTextBaseline:
                throw AdaptiveCardCompilationError.unsupportedNode(
                    "Adaptive Cards cannot preserve baseline vertical alignment."
                )
            }
        }

        private func applyingHorizontalAlignment(
            _ alignment: WidgetHorizontalAlignment,
            to value: CanonicalJSON
        ) -> CanonicalJSON {
            guard case .object(var object) = value,
                  case .string(let type) = object["type"] else {
                return value
            }
            switch type {
            case "TextBlock", "Image", "ColumnSet":
                object["horizontalAlignment"] = .string(
                    horizontalAlignment(alignment)
                )
            case "Container":
                if case .array(let items) = object["items"] {
                    object["items"] = .array(
                        items.map {
                            applyingHorizontalAlignment(alignment, to: $0)
                        }
                    )
                }
            default:
                break
            }
            return .object(object)
        }

        private func fontMapping(_ font: WidgetFont) -> (size: String, weight: String) {
            switch font {
            case .largeTitle:
                ("extraLarge", "bolder")
            case .title, .title2:
                ("large", "bolder")
            case .title3, .headline:
                ("medium", "bolder")
            case .subheadline:
                ("default", "bolder")
            case .body, .callout:
                ("default", "default")
            case .footnote, .caption, .caption2:
                ("small", "default")
            }
        }

        private func textColorMapping(
            _ color: WidgetColor
        ) throws -> (name: String?, isSubtle: Bool) {
            guard case .standard(let standard) = color else {
                throw AdaptiveCardCompilationError.unsupportedColor(
                    "Adaptive Cards text colors cannot preserve arbitrary RGB or HSB values."
                )
            }
            switch standard {
            case .primary:
                return (nil, false)
            case .secondary:
                return (nil, true)
            case .red:
                return ("attention", false)
            case .orange, .yellow:
                return ("warning", false)
            case .green:
                return ("good", false)
            case .blue:
                return ("accent", false)
            default:
                throw AdaptiveCardCompilationError.unsupportedColor(
                    "The requested semantic color has no stable Adaptive Cards text palette mapping."
                )
            }
        }

        private func containerStyle(_ color: WidgetColor) throws -> String? {
            guard case .standard(let standard) = color else {
                throw AdaptiveCardCompilationError.unsupportedColor(
                    "Adaptive Cards containers cannot preserve arbitrary RGB or HSB backgrounds."
                )
            }
            switch standard {
            case .clear:
                return nil
            case .primary:
                return "default"
            case .secondary, .gray:
                return "emphasis"
            case .red:
                return "attention"
            case .orange, .yellow:
                return "warning"
            case .green:
                return "good"
            case .blue:
                return "accent"
            default:
                throw AdaptiveCardCompilationError.unsupportedColor(
                    "The requested semantic color has no stable Adaptive Cards container style mapping."
                )
            }
        }
    }

    private let capabilities: AdaptiveCardHostCapabilities
    private let textResolver: any WidgetTextResolving
    private let resourceResolver: any AdaptiveCardResourceResolving
    private let cacheCapacity: Int
    private let cache = Mutex(CacheState())

    package init(
        capabilities: AdaptiveCardHostCapabilities = AdaptiveCardHostCapabilities(),
        cacheCapacity: Int = 128,
        textResolver: any WidgetTextResolving = BundleWidgetTextResolver(),
        resourceResolver: any AdaptiveCardResourceResolving
    ) throws {
        guard cacheCapacity > 0 else {
            throw AdaptiveCardCompilationError.invalidCacheCapacity(cacheCapacity)
        }
        guard capabilities.schemaVersion == "1.6",
              capabilities.compilerContractVersion == 1 else {
            throw AdaptiveCardCompilationError.unsupportedHostCapabilities(
                "M4 implements Adaptive Cards 1.6 compiler contract 1 only."
            )
        }
        self.capabilities = capabilities
        self.cacheCapacity = cacheCapacity
        self.textResolver = textResolver
        self.resourceResolver = resourceResolver
    }

    package func compile(_ update: RuntimeWidgetUpdate) throws -> CompiledWidgetPayload {
        let documents = update.entry.documents
        try validate(documents: documents, family: update.family)
        let outputs = try documents.map { document in
            try compileVariant(document)
        }.sorted {
            themeRank($0.themeName) < themeRank($1.themeName)
        }
        let template = CanonicalJSON.object([
            "$schema": .string("http://adaptivecards.io/schemas/adaptive-card.json"),
            "type": .string("AdaptiveCard"),
            "version": .string(capabilities.schemaVersion),
            "body": .array(
                outputs.map { output in
                    .object([
                        "type": .string("Container"),
                        "$when": .string(
                            hostCondition(
                                family: update.family,
                                themeName: output.themeName
                            )
                        ),
                        "items": .array(output.elements)
                    ])
                }
            )
        ])
        let templateDescriptor = try CanonicalJSONEncoder.string(template)
        let structureIdentity = StableSHA256.hexDigest(
            of: Array(
                "\(capabilities.compilerContractVersion):\(templateDescriptor)".utf8
            )
        )
        let cached = cache.withLock { state -> (String, Bool) in
            state.accessCounter &+= 1
            if var entry = state.entries[templateDescriptor] {
                entry.lastAccess = state.accessCounter
                state.entries[templateDescriptor] = entry
                return (entry.templateJSON, true)
            }
            if state.entries.count >= cacheCapacity,
               let evicted = state.entries.min(by: {
                   $0.value.lastAccess < $1.value.lastAccess
               })?.key {
                state.entries.removeValue(forKey: evicted)
            }
            state.entries[templateDescriptor] = CacheEntry(
                templateJSON: templateDescriptor,
                lastAccess: state.accessCounter
            )
            return (templateDescriptor, false)
        }

        let data = CanonicalJSON.object(
            Dictionary(uniqueKeysWithValues: outputs.map {
                ($0.themeName, CanonicalJSON.object($0.data))
            })
        )
        let references = outputs.flatMap(\.resourceReferences).reduce(
            into: [AdaptiveCardResourceReference]()
        ) { result, reference in
            if !result.contains(reference) {
                result.append(reference)
            }
        }
        return CompiledWidgetPayload(
            templateJSON: cached.0,
            dataJSON: try CanonicalJSONEncoder.string(data),
            structureIdentity: structureIdentity,
            resourceReferences: references,
            templateWasReused: cached.1
        )
    }

    private func compileVariant(
        _ document: WidgetDocument
    ) throws -> VariantOutput {
        let themeName: String
        switch document.environment.colorScheme {
        case .light: themeName = "light"
        case .dark: themeName = "dark"
        }
        var builder = VariantBuilder(
            bindingNamespace: themeName,
            document: document,
            textResolver: textResolver,
            resourceResolver: resourceResolver
        )
        let elements = try builder.compile(
            node: document.root,
            parentAxis: .vertical
        )
        return VariantOutput(
            themeName: themeName,
            elements: elements,
            data: builder.data,
            resourceReferences: builder.resourceReferences
        )
    }

    private func validate(
        documents: [WidgetDocument],
        family: RuntimeWidgetFamily
    ) throws {
        var themes: Set<String> = []
        for document in documents {
            guard document.environment.displayScale.isFinite,
                  document.environment.displayScale > 0 else {
                throw AdaptiveCardCompilationError.invalidDocument(
                    "Display scale must be finite and positive."
                )
            }
            if let documentFamily = document.environment.family,
               documentFamily != family {
                throw AdaptiveCardCompilationError.invalidDocument(
                    "The document family does not match its runtime update."
                )
            }
            let theme: String
            switch document.environment.colorScheme {
            case .light: theme = "light"
            case .dark: theme = "dark"
            }
            guard themes.insert(theme).inserted else {
                throw AdaptiveCardCompilationError.duplicateThemeVariant(theme)
            }
            var nodeIDs: Set<WidgetNodeID> = []
            try validate(node: document.root, nodeIDs: &nodeIDs)
        }
        for requiredTheme in ["light", "dark"] where !themes.contains(requiredTheme) {
            throw AdaptiveCardCompilationError.missingThemeVariant(requiredTheme)
        }
    }

    private func validate(
        node: WidgetNode,
        nodeIDs: inout Set<WidgetNodeID>
    ) throws {
        guard nodeIDs.insert(node.id).inserted else {
            throw AdaptiveCardCompilationError.invalidDocument(
                "Widget node identities must be unique within a document."
            )
        }
        for child in node.children {
            try validate(node: child, nodeIDs: &nodeIDs)
        }
    }

    private func hostCondition(
        family: RuntimeWidgetFamily,
        themeName: String
    ) -> String {
        let size = switch family {
        case .systemSmall: "small"
        case .systemMedium: "medium"
        case .systemLarge: "large"
        }
        return "${$host.widgetSize == \"\(size)\" && $host.hostTheme == \"\(themeName)\"}"
    }

    private func themeRank(_ themeName: String) -> Int {
        themeName == "light" ? 0 : 1
    }
}
