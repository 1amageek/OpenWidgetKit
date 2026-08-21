import OpenFoundation
import OpenWidgetRuntime
import Synchronization

package final class AdaptiveCardCompiler: Sendable {
    private struct CacheEntry: Sendable {
        let templateJSON: String
        let structureIdentity: String
        // The compiler emits placeholders and this plan together. Reusing the
        // plan prevents the data path from independently reconstructing binding
        // order when dynamic values change.
        let bindingPlans: [VariantBindingPlan]
    }

    private struct CacheState: Sendable {
        var entries: [String: CacheEntry] = [:]
        var recency: [String] = []

        mutating func value(for key: String) -> CacheEntry? {
            guard let value = entries[key] else { return nil }
            markRecentlyUsed(key)
            return value
        }

        mutating func insert(
            _ value: CacheEntry,
            for key: String,
            capacity: Int
        ) {
            if entries[key] == nil,
               entries.count >= capacity,
               let leastRecentKey = recency.first {
                entries.removeValue(forKey: leastRecentKey)
                recency.removeFirst()
            }
            entries[key] = value
            markRecentlyUsed(key)
        }

        private mutating func markRecentlyUsed(_ key: String) {
            if let existingIndex = recency.firstIndex(of: key) {
                recency.remove(at: existingIndex)
            }
            recency.append(key)
        }
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
        let bindingPlan: VariantBindingPlan
    }

    private struct VariantDataOutput {
        let themeName: String
        let data: [String: CanonicalJSON]
        let resourceReferences: [AdaptiveCardResourceReference]
    }

    private enum BindingRole: Sendable {
        case text
        case imageResource
        case imageLabel
        case actionTitle
    }

    private struct BindingDescriptor: Sendable {
        let key: String
        let nodePath: [Int]
        let role: BindingRole
    }

    private struct VariantBindingPlan: Sendable {
        let themeName: String
        let bindings: [BindingDescriptor]
    }

    private struct VariantBuilder {
        let bindingNamespace: String
        var nextBinding = 0
        var bindings: [BindingDescriptor] = []

        mutating func bind(
            nodePath: [Int],
            role: BindingRole
        ) -> String {
            let key = "v\(nextBinding)"
            nextBinding += 1
            bindings.append(
                BindingDescriptor(
                    key: key,
                    nodePath: nodePath,
                    role: role
                )
            )
            return "${\(bindingNamespace).\(key)}"
        }

        mutating func compile(
            node: WidgetNode,
            nodePath: [Int],
            parentAxis: Axis,
            textStyle: TextStyle = TextStyle()
        ) throws -> [CanonicalJSON] {
            switch node.kind {
            case .empty:
                try requireNoChildren(node, kind: "EmptyView")
                return []
            case .text(let text):
                try requireNoChildren(node, kind: "Text")
                return [
                    try compileText(
                        text,
                        nodePath: nodePath,
                        inheritedStyle: textStyle
                    )
                ]
            case .image(let image):
                try requireNoChildren(node, kind: "Image")
                return [try compileImage(image, nodePath: nodePath)]
            case .color:
                throw AdaptiveCardCompilationError.unsupportedNode(
                    "A standalone Color has no equivalent Adaptive Cards element."
                )
            case .verticalStack(let alignment, let spacing):
                let items = try compileChildren(
                    node.children,
                    parentPath: nodePath,
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
                    parentPath: nodePath,
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
                return try node.children.enumerated().flatMap { index, child in
                    try compile(
                        node: child,
                        nodePath: nodePath + [index],
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
            case .action(let action):
                return [
                    try compileAction(
                        action,
                        node: node,
                        nodePath: nodePath,
                        inheritedStyle: textStyle
                    )
                ]
            case .modified(let modifier):
                return try compileModified(
                    modifier,
                    children: node.children,
                    parentPath: nodePath,
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
                    nodePath: nodePath,
                    parentAxis: parentAxis,
                    textStyle: textStyle
                )
            }
        }

        private mutating func compileText(
            _ text: WidgetText,
            nodePath: [Int],
            inheritedStyle: TextStyle
        ) throws -> CanonicalJSON {
            var object: [String: CanonicalJSON] = [
                "type": .string("TextBlock"),
                "text": .string(
                    bind(nodePath: nodePath, role: .text)
                ),
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
            _ image: WidgetImage,
            nodePath: [Int]
        ) throws -> CanonicalJSON {
            guard image.isDecorative || image.label != nil else {
                throw AdaptiveCardCompilationError.unsupportedNode(
                    "A Windows image must be decorative or provide an explicit accessibility label."
                )
            }
            var object: [String: CanonicalJSON] = [
                "type": .string("Image"),
                "url": .string(
                    bind(nodePath: nodePath, role: .imageResource)
                ),
                "size": .string("auto")
            ]
            if image.label != nil {
                object["altText"] = .string(
                    bind(nodePath: nodePath, role: .imageLabel)
                )
            } else if image.isDecorative {
                object["altText"] = .string("")
            }
            return .object(object)
        }

        private mutating func compileAction(
            _ action: WidgetActionDescriptor,
            node: WidgetNode,
            nodePath: [Int],
            inheritedStyle: TextStyle
        ) throws -> CanonicalJSON {
            try requireNoChildren(node, kind: "Button")
            guard action.title.font == nil,
                  action.title.foregroundColor == nil,
                  inheritedStyle.font == nil,
                  inheritedStyle.foregroundColor == nil,
                  inheritedStyle.lineLimit == nil else {
                throw AdaptiveCardCompilationError.unsupportedNode(
                    "Adaptive Cards action titles cannot preserve Text font, foreground-color, or line-limit overrides."
                )
            }
            let verb = actionVerb(action.id)
            var execute: [String: CanonicalJSON] = [
                "type": .string("Action.Execute"),
                "title": .string(bind(nodePath: nodePath, role: .actionTitle)),
                "verb": .string(verb),
                "data": .object([
                    "openWidgetActionID": .string(verb)
                ]),
                "associatedInputs": .string("none")
            ]
            switch action.role {
            case .standard:
                break
            case .cancel:
                throw AdaptiveCardCompilationError.unsupportedNode(
                    "Adaptive Cards Action.Execute has no cancel-role semantic equivalent."
                )
            case .close:
                throw AdaptiveCardCompilationError.unsupportedNode(
                    "Adaptive Cards Action.Execute has no close-role semantic equivalent."
                )
            case .destructive:
                execute["style"] = .string("destructive")
            case .confirm:
                execute["style"] = .string("positive")
            }
            return .object([
                "type": .string("ActionSet"),
                "actions": .array([.object(execute)])
            ])
        }

        private func actionVerb(_ id: WidgetActionID) -> String {
            "\(id.rawValue)|theme:\(bindingNamespace)"
        }

        private mutating func compileChildren(
            _ children: [WidgetNode],
            parentPath: [Int],
            axis: Axis,
            spacing: CGFloat?,
            textStyle: TextStyle
        ) throws -> [CanonicalJSON] {
            let spacingName = try adaptiveSpacing(spacing)
            var elements: [CanonicalJSON] = []
            for (index, child) in children.enumerated() {
                let childElements = try compile(
                    node: child,
                    nodePath: parentPath + [index],
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
            parentPath: [Int],
            alignment: WidgetVerticalAlignment,
            spacing: CGFloat?,
            textStyle: TextStyle
        ) throws -> [CanonicalJSON] {
            let spacingName = try adaptiveSpacing(spacing)
            var columns: [CanonicalJSON] = []
            for (index, child) in children.enumerated() {
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
                        nodePath: parentPath + [index],
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
            parentPath: [Int],
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
            return try children.enumerated().flatMap { index, child in
                try compile(
                    node: child,
                    nodePath: parentPath + [index],
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
            nodePath: [Int],
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
            let foregroundItems = try foreground.enumerated().flatMap { index, child in
                try compile(
                    node: child,
                    nodePath: nodePath + [index],
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
        let actionBindings = try actionBindings(documents: documents)
        let cacheKey = templateCacheKey(
            documents: documents,
            family: update.family
        )
        // Dynamic text and resource identities are intentionally absent from
        // this exact semantic key. Every hit still materializes them through
        // the binding plan stored with the matching template.
        let cachedEntry = cache.withLock { state in
            state.value(for: cacheKey)
        }
        if let cachedEntry {
            let dataOutputs = try materializeData(
                documents: documents,
                bindingPlans: cachedEntry.bindingPlans
            )
            return CompiledWidgetPayload(
                templateJSON: cachedEntry.templateJSON,
                dataJSON: try dataJSON(dataOutputs),
                structureIdentity: cachedEntry.structureIdentity,
                resourceReferences: resourceReferences(dataOutputs),
                actionBindings: actionBindings,
                templateCompilationWasSkipped: true
            )
        }

        let templateOutputs = try documents.map { document in
            try compileVariant(document)
        }.sorted {
            themeRank($0.themeName) < themeRank($1.themeName)
        }
        let bindingPlans = templateOutputs.map(\.bindingPlan)
        let dataOutputs = try materializeData(
            documents: documents,
            bindingPlans: bindingPlans
        )
        let template = CanonicalJSON.object([
            "$schema": .string("http://adaptivecards.io/schemas/adaptive-card.json"),
            "type": .string("AdaptiveCard"),
            "version": .string(capabilities.schemaVersion),
            "body": .array(
                templateOutputs.map { output in
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
        let entry = CacheEntry(
            templateJSON: templateDescriptor,
            structureIdentity: structureIdentity,
            bindingPlans: bindingPlans
        )
        cache.withLock { state in
            state.insert(
                entry,
                for: cacheKey,
                capacity: cacheCapacity
            )
        }
        return CompiledWidgetPayload(
            templateJSON: templateDescriptor,
            dataJSON: try dataJSON(dataOutputs),
            structureIdentity: structureIdentity,
            resourceReferences: resourceReferences(dataOutputs),
            actionBindings: actionBindings,
            templateCompilationWasSkipped: false
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
            bindingNamespace: themeName
        )
        let elements = try builder.compile(
            node: document.root,
            nodePath: [],
            parentAxis: .vertical
        )
        return VariantOutput(
            themeName: themeName,
            elements: elements,
            bindingPlan: VariantBindingPlan(
                themeName: themeName,
                bindings: builder.bindings
            )
        )
    }

    private func materializeData(
        documents: [WidgetDocument],
        bindingPlans: [VariantBindingPlan]
    ) throws -> [VariantDataOutput] {
        try bindingPlans.map { bindingPlan in
            guard let document = documents.first(where: {
                themeName($0) == bindingPlan.themeName
            }) else {
                throw AdaptiveCardCompilationError.invalidDocument(
                    "A cached binding plan has no matching theme document."
                )
            }
            return try materializeData(
                document: document,
                bindingPlan: bindingPlan
            )
        }
    }

    private func materializeData(
        document: WidgetDocument,
        bindingPlan: VariantBindingPlan
    ) throws -> VariantDataOutput {
        var data: [String: CanonicalJSON] = [:]
        var resourceReferences: [AdaptiveCardResourceReference] = []
        var nextBindingIndex = 0
        var nodePath: [Int] = []
        try materializeBindings(
            node: document.root,
            nodePath: &nodePath,
            document: document,
            bindings: bindingPlan.bindings,
            nextBindingIndex: &nextBindingIndex,
            data: &data,
            resourceReferences: &resourceReferences
        )
        guard nextBindingIndex == bindingPlan.bindings.count else {
            throw bindingPlanMismatch()
        }
        return VariantDataOutput(
            themeName: bindingPlan.themeName,
            data: data,
            resourceReferences: resourceReferences
        )
    }

    private func materializeBindings(
        node: WidgetNode,
        nodePath: inout [Int],
        document: WidgetDocument,
        bindings: [BindingDescriptor],
        nextBindingIndex: inout Int,
        data: inout [String: CanonicalJSON],
        resourceReferences: inout [AdaptiveCardResourceReference]
    ) throws {
        while nextBindingIndex < bindings.count,
              bindings[nextBindingIndex].nodePath == nodePath {
            let binding = bindings[nextBindingIndex]
            switch binding.role {
            case .text:
                guard case .text(let text) = node.kind else {
                    throw bindingPlanMismatch()
                }
                data[binding.key] = .string(try textResolver.resolve(text))
            case .imageResource:
                guard case .image(let image) = node.kind else {
                    throw bindingPlanMismatch()
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
                data[binding.key] = .string(uri)
            case .imageLabel:
                guard case .image(let image) = node.kind,
                      let label = image.label else {
                    throw bindingPlanMismatch()
                }
                data[binding.key] = .string(try textResolver.resolve(label))
            case .actionTitle:
                guard case .action(let action) = node.kind else {
                    throw bindingPlanMismatch()
                }
                data[binding.key] = .string(try textResolver.resolve(action.title))
            }
            nextBindingIndex += 1
        }
        guard nextBindingIndex < bindings.count else { return }
        for (index, child) in node.children.enumerated() {
            nodePath.append(index)
            try materializeBindings(
                node: child,
                nodePath: &nodePath,
                document: document,
                bindings: bindings,
                nextBindingIndex: &nextBindingIndex,
                data: &data,
                resourceReferences: &resourceReferences
            )
            nodePath.removeLast()
        }
    }

    private func bindingPlanMismatch() -> AdaptiveCardCompilationError {
        .invalidDocument(
            "The document structure does not match its cached binding plan."
        )
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

    private func templateCacheKey(
        documents: [WidgetDocument],
        family: RuntimeWidgetFamily
    ) -> String {
        var components = [
            "contract",
            String(capabilities.compilerContractVersion),
            "schema",
            capabilities.schemaVersion,
            "family",
            String(family.rawValue)
        ]
        for document in documents.sorted(by: {
            themeRank(themeName($0)) < themeRank(themeName($1))
        }) {
            components.append("theme")
            components.append(themeName(document))
            appendTemplateStructure(of: document.root, to: &components)
        }
        return components.joined(separator: "|")
    }

    private func appendTemplateStructure(
        of node: WidgetNode,
        to components: inout [String]
    ) {
        switch node.kind {
        case .empty:
            components.append("empty")
        case .text(let text):
            components.append("text")
            components.append(text.font?.rawValue ?? "nil")
            components.append(String(reflecting: text.foregroundColor))
        case .image(let image):
            components.append("image")
            components.append(image.label == nil ? "unlabeled" : "labeled")
            components.append(image.isDecorative ? "decorative" : "semantic")
        case .color(let color):
            components.append("color")
            components.append(String(reflecting: color))
        case .verticalStack(let alignment, let spacing):
            components.append("verticalStack")
            components.append(alignment.rawValue)
            components.append(String(reflecting: spacing))
        case .horizontalStack(let alignment, let spacing):
            components.append("horizontalStack")
            components.append(alignment.rawValue)
            components.append(String(reflecting: spacing))
        case .group:
            components.append("group")
        case .spacer(let minLength):
            components.append("spacer")
            components.append(String(reflecting: minLength))
        case .divider:
            components.append("divider")
        case .action(let action):
            components.append("action")
            components.append(action.id.rawValue)
            components.append(String(reflecting: action.role))
            components.append(action.title.font?.rawValue ?? "nil")
            components.append(String(reflecting: action.title.foregroundColor))
        case .modified(let modifier):
            components.append("modified")
            components.append(String(reflecting: modifier))
        case .background(let alignment, let ignoredEdges, let foregroundCount):
            components.append("background")
            components.append(String(reflecting: alignment))
            components.append(String(reflecting: ignoredEdges?.rawValue))
            components.append(String(foregroundCount))
        }
        components.append("children")
        components.append(String(node.children.count))
        for child in node.children {
            appendTemplateStructure(of: child, to: &components)
        }
        components.append("end")
    }

    private func themeName(_ document: WidgetDocument) -> String {
        switch document.environment.colorScheme {
        case .light: "light"
        case .dark: "dark"
        }
    }

    private func dataJSON(_ outputs: [VariantDataOutput]) throws -> String {
        try encodedDataJSON(
            outputs.map { ($0.themeName, $0.data) }
        )
    }

    private func encodedDataJSON(
        _ outputs: [(String, [String: CanonicalJSON])]
    ) throws -> String {
        let data = CanonicalJSON.object(
            Dictionary(uniqueKeysWithValues: outputs.map {
                ($0.0, CanonicalJSON.object($0.1))
            })
        )
        return try CanonicalJSONEncoder.string(data)
    }

    private func resourceReferences(
        _ outputs: [VariantDataOutput]
    ) -> [AdaptiveCardResourceReference] {
        deduplicatedResourceReferences(outputs.flatMap(\.resourceReferences))
    }

    private func actionBindings(
        documents: [WidgetDocument]
    ) throws -> [AdaptiveCardActionBinding] {
        guard let canonicalDocument = documents.sorted(by: {
            themeRank(themeName($0)) < themeRank(themeName($1))
        }).first else {
            return []
        }
        let canonicalIDs = Set(canonicalDocument.actions.keys)
        for document in documents {
            guard Set(document.actions.keys) == canonicalIDs else {
                throw AdaptiveCardCompilationError.invalidDocument(
                    "Every environment variant must expose the same action identities."
                )
            }
            for id in canonicalIDs {
                guard document.actions[id]?.handlerIdentity ==
                        canonicalDocument.actions[id]?.handlerIdentity else {
                    throw AdaptiveCardCompilationError.invalidDocument(
                        "Every environment variant must bind an action identity to the same persistent intent identity."
                    )
                }
            }
        }
        return documents.sorted {
            themeRank(themeName($0)) < themeRank(themeName($1))
        }.flatMap { document in
            document.actions.values.sorted {
                $0.id.rawValue < $1.id.rawValue
            }.map { action in
                let verb = actionVerb(
                    action.id,
                    themeName: themeName(document)
                )
                return AdaptiveCardActionBinding(
                    verb: verb,
                    action: action
                )
            }
        }
    }

    private func actionVerb(
        _ id: WidgetActionID,
        themeName: String
    ) -> String {
        "\(id.rawValue)|theme:\(themeName)"
    }

    private func deduplicatedResourceReferences(
        _ references: [AdaptiveCardResourceReference]
    ) -> [AdaptiveCardResourceReference] {
        references.reduce(into: []) { result, reference in
            if !result.contains(reference) {
                result.append(reference)
            }
        }
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
            var actionIDs: Set<WidgetActionID> = []
            try validate(
                node: document.root,
                nodeIDs: &nodeIDs,
                actionIDs: &actionIDs
            )
            guard actionIDs == Set(document.actions.keys) else {
                throw AdaptiveCardCompilationError.invalidDocument(
                    "The document action table must exactly match its action nodes."
                )
            }
        }
        for requiredTheme in ["light", "dark"] where !themes.contains(requiredTheme) {
            throw AdaptiveCardCompilationError.missingThemeVariant(requiredTheme)
        }
    }

    private func validate(
        node: WidgetNode,
        nodeIDs: inout Set<WidgetNodeID>,
        actionIDs: inout Set<WidgetActionID>
    ) throws {
        guard nodeIDs.insert(node.id).inserted else {
            throw AdaptiveCardCompilationError.invalidDocument(
                "Widget node identities must be unique within a document."
            )
        }
        if case .action(let action) = node.kind {
            guard action.id == WidgetActionID(nodeID: node.id) else {
                throw AdaptiveCardCompilationError.invalidDocument(
                    "An action identity must be derived from its semantic node identity."
                )
            }
            guard actionIDs.insert(action.id).inserted else {
                throw AdaptiveCardCompilationError.invalidDocument(
                    "Widget action identities must be unique within a document."
                )
            }
        }
        for child in node.children {
            try validate(
                node: child,
                nodeIDs: &nodeIDs,
                actionIDs: &actionIDs
            )
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
