import AppIntents
import OpenFoundation
@testable import OpenWidgetRuntime
@testable import SwiftUI
import Testing

@MainActor
@Suite
struct WidgetDocumentTests {
    @Test
    func lowersCustomBodyContainersAndModifiers() throws {
        let document = try makeWidgetDocument(
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "star")
                    Text(verbatim: "Value")
                }
            }
            .padding(.horizontal, 12)
            .frame(minWidth: 100, maxWidth: 240, alignment: .topLeading)
        )

        #expect(document.root.children.count == 1)
        let frameNode = try #require(document.root.children.first)
        guard case .modified(.frame(let frame)) = frameNode.kind else {
            Issue.record("Expected the outer frame modifier")
            return
        }
        #expect(frame.minWidth == 100)
        #expect(frame.maxWidth == 240)
        #expect(frame.alignment.horizontal == .leading)
        #expect(frame.alignment.vertical == .top)

        let paddingNode = try #require(frameNode.children.first)
        guard case .modified(.padding(let edges, let insets)) = paddingNode.kind else {
            Issue.record("Expected the padding modifier")
            return
        }
        #expect(edges == .horizontal)
        #expect(insets?.leading == 12)

        let stackNode = try #require(paddingNode.children.first)
        guard case .verticalStack(let alignment, let spacing) = stackNode.kind else {
            Issue.record("Expected a vertical stack")
            return
        }
        #expect(alignment == .leading)
        #expect(spacing == 8)
        #expect(stackNode.children.count == 2)
    }

    @Test
    func variadicBuilderPreservesMoreThanTenChildren() throws {
        let document = try makeWidgetDocument(
            VStack {
                Text(verbatim: "0")
                Text(verbatim: "1")
                Text(verbatim: "2")
                Text(verbatim: "3")
                Text(verbatim: "4")
                Text(verbatim: "5")
                Text(verbatim: "6")
                Text(verbatim: "7")
                Text(verbatim: "8")
                Text(verbatim: "9")
                Text(verbatim: "10")
            }
        )

        let stack = try #require(document.root.children.first)
        #expect(stack.children.count == 11)
    }

    @Test(arguments: [true, false])
    func lowersConditionalContent(_ includesDetail: Bool) throws {
        let document = try makeWidgetDocument(
            Group {
                Text(verbatim: "Always")
                if includesDetail {
                    Text(verbatim: "Detail")
                }
            }
        )

        let group = try #require(document.root.children.first)
        #expect(group.children.count == (includesDetail ? 2 : 1))
    }

    @Test
    func registersAndDeduplicatesImageResources() throws {
        let document = try makeWidgetDocument(
            HStack {
                Image("badge", label: Text(verbatim: "Badge"))
                Image(decorative: "badge")
            }
        )

        #expect(document.resources.count == 1)
        let stack = try #require(document.root.children.first)
        let first = try #require(stack.children.first)
        let second = try #require(stack.children.last)
        guard case .image(let labeledImage) = first.kind,
              case .image(let decorativeImage) = second.kind else {
            Issue.record("Expected image nodes")
            return
        }
        #expect(labeledImage.resourceID == decorativeImage.resourceID)
        #expect(labeledImage.label != nil)
        #expect(decorativeImage.isDecorative)
    }

    @Test
    func lowersIntentButtonWithStableActionIdentity() throws {
        let first = try makeWidgetDocument(
            Button("Run", intent: DocumentFixtureIntent())
        )
        let second = try makeWidgetDocument(
            Button("Run again", intent: DocumentFixtureIntent())
        )

        #expect(first.actions.count == 1)
        #expect(Set(first.actions.keys) == Set(second.actions.keys))
        let node = try #require(first.root.children.first)
        guard case .action(let descriptor) = node.kind else {
            Issue.record("Expected an action node")
            return
        }
        #expect(first.actions[descriptor.id]?.handlerIdentity ==
            DocumentFixtureIntent.persistentIdentifier)
    }

    @Test
    func retainsLocalizedStringResourceUntilRendering() throws {
        let resource: LocalizedStringResource = "Localized action"
        let document = try makeWidgetDocument(
            Button(resource, intent: DocumentFixtureIntent())
        )
        let node = try #require(document.root.children.first)
        guard case .action(let descriptor) = node.kind,
              case .localizedResource(let storedResource) = descriptor.title.storage else {
            Issue.record("Expected a localized-resource action title")
            return
        }

        #expect(storedResource == resource)
    }

    @Test
    func rejectsUnsupportedIntentModesAndButtonLabels() {
        #expect(throws: WidgetSemanticError.self) {
            try makeWidgetDocument(
                Button(intent: OpensAppFixtureIntent()) {
                    Text(verbatim: "Open")
                }
            )
        }
        #expect(throws: WidgetSemanticError.self) {
            try makeWidgetDocument(
                Button(intent: DocumentFixtureIntent()) {
                    Image(systemName: "star")
                }
            )
        }
        #expect(throws: WidgetSemanticError.self) {
            try makeWidgetDocument(
                Button("Custom result", intent: CustomResultFixtureIntent())
            )
        }
    }

    @Test
    func backgroundStylePreservesIgnoredSafeAreaEdges() throws {
        let document = try makeWidgetDocument(
            Text(verbatim: "Foreground")
                .background(Color.red, ignoresSafeAreaEdges: [.top, .bottom])
        )

        let node = try #require(document.root.children.first)
        guard case .background(
            let alignment,
            let ignoredEdges,
            let foregroundCount
        ) = node.kind else {
            Issue.record("Expected a background node")
            return
        }
        #expect(alignment.horizontal == .center)
        #expect(alignment.vertical == .center)
        #expect(ignoredEdges == [.top, .bottom])
        #expect(foregroundCount == 1)
        #expect(node.children.count == 2)
    }

    @Test
    func preservesTextStyleModifiersAndPrimitiveLayoutNodes() throws {
        let document = try makeWidgetDocument(
            VStack {
                AnyView(
                    Text(verbatim: "Styled")
                        .font(.headline)
                        .foregroundColor(.red)
                        .lineLimit(2)
                )
                Spacer(minLength: 6)
                Divider()
            }
        )

        let stack = try #require(document.root.children.first)
        #expect(stack.children.count == 3)
        guard case .modified(.lineLimit(2)) = stack.children[0].kind,
              case .text(let text) = stack.children[0].children.first?.kind,
              case .spacer(minLength: 6) = stack.children[1].kind,
              case .divider = stack.children[2].kind else {
            Issue.record("Expected the complete style and primitive node chain")
            return
        }
        #expect(text.font == .headline)
        #expect(text.foregroundColor == .standard(.red))
    }

    @Test
    func environmentOverridesAreVisibleWhileEvaluatingBody() throws {
        let document = try makeWidgetDocument(
            EnvironmentReader()
                .environment(\.colorScheme, .dark)
                .environment(\.displayScale, 2)
        )

        let text = try #require(document.root.children.first)
        guard case .text(let value) = text.kind,
              case .verbatim(let string) = value.storage else {
            Issue.record("Expected environment-derived text")
            return
        }
        #expect(string == "dark@2.0")
    }

    @Test
    func forEachIdentitySurvivesReordering() throws {
        let identityStore = WidgetIdentityStore()
        let first = try makeWidgetDocument(
            ItemList(items: [Item(id: 1), Item(id: 2)]),
            identityStore: identityStore
        )
        let second = try makeWidgetDocument(
            ItemList(items: [Item(id: 2), Item(id: 1)]),
            identityStore: identityStore
        )

        #expect(textIdentityMap(in: first) == textIdentityMap(in: second))
    }

    @Test
    func identityEvaluationPrunesUnusedValuesAndRollsBackFailures() throws {
        let identityStore = WidgetIdentityStore()

        _ = try makeWidgetDocument(
            ItemList(items: [Item(id: 1), Item(id: 2)]),
            identityStore: identityStore
        )
        #expect(identityStore.retainedIdentifierCount == 2)

        _ = try makeWidgetDocument(
            ItemList(items: [Item(id: 2)]),
            identityStore: identityStore
        )
        #expect(identityStore.retainedIdentifierCount == 1)

        #expect(throws: WidgetSemanticError.duplicateStableID(typeName: "Swift.Int")) {
            try makeWidgetDocument(
                ItemList(items: [Item(id: 3), Item(id: 3)]),
                identityStore: identityStore
            )
        }
        #expect(identityStore.retainedIdentifierCount == 1)
    }

    @Test
    func nestedIdentityEvaluationRollsBackOnlyTheFailedFrame() throws {
        let identityStore = WidgetIdentityStore()
        let namespace = WidgetNodeID(components: [.role("fixture")])

        try identityStore.withEvaluation {
            _ = try identityStore.identifier(for: 1, namespace: namespace)
            do {
                try identityStore.withEvaluation {
                    _ = try identityStore.identifier(for: 2, namespace: namespace)
                    throw IdentityFixtureError.expectedFailure
                }
            } catch IdentityFixtureError.expectedFailure {
                // The outer evaluation intentionally continues after rollback.
            }
            _ = try identityStore.identifier(for: 3, namespace: namespace)
        }

        #expect(identityStore.retainedIdentifierCount == 2)
    }

    @Test
    func rejectsDuplicateForEachIdentity() {
        #expect(throws: WidgetSemanticError.duplicateStableID(typeName: "Swift.Int")) {
            try makeWidgetDocument(
                ItemList(items: [Item(id: 1), Item(id: 1)])
            )
        }
    }

    @Test
    func rejectsInvalidSemanticValues() {
        #expect(throws: WidgetSemanticError.invalidDisplayScale) {
            try makeWidgetDocument(
                Text(verbatim: "Scale").environment(\.displayScale, 0)
            )
        }
        #expect(throws: WidgetSemanticError.invalidResourceName) {
            try makeWidgetDocument(Image(""))
        }
        #expect(
            throws: WidgetSemanticError.nonFiniteLayoutValue(
                field: "VStack.spacing"
            )
        ) {
            try makeWidgetDocument(VStack(spacing: .infinity) { EmptyView() })
        }
        #expect(throws: WidgetSemanticError.invalidLineLimit(-1)) {
            try makeWidgetDocument(Text(verbatim: "Invalid").lineLimit(-1))
        }
        #expect(
            throws: WidgetSemanticError.invalidFrameRange(axis: "horizontal")
        ) {
            try makeWidgetDocument(
                Text(verbatim: "Invalid")
                    .frame(minWidth: 20, maxWidth: 10)
            )
        }
        #expect(
            throws: WidgetSemanticError.invalidColorComponent(component: "red")
        ) {
            try makeWidgetDocument(
                Color(red: .infinity, green: 0, blue: 0)
            )
        }
        #expect(throws: WidgetSemanticError.unsupportedEnvironmentKey) {
            try makeWidgetDocument(
                Text(verbatim: "Unsupported")
                    .environment(\.fixtureValue, 1)
            )
        }
    }

    @Test
    func unsupportedPrimitiveFailsWithoutEvaluatingNeverBody() {
        #expect(
            throws: WidgetSemanticError.unsupportedView(
                typeName: String(reflecting: UnsupportedPrimitive.self)
            )
        ) {
            try makeWidgetDocument(UnsupportedPrimitive())
        }
    }

    @Test
    func documentIsSendable() throws {
        let document = try makeWidgetDocument(Text(verbatim: "Sendable"))
        requireSendable(document)
    }

    private func textIdentityMap(
        in document: WidgetDocument
    ) -> [String: WidgetNodeID] {
        var result: [String: WidgetNodeID] = [:]
        collectText(in: document.root, result: &result)
        return result
    }

    private func collectText(
        in node: WidgetNode,
        result: inout [String: WidgetNodeID]
    ) {
        if case .text(let text) = node.kind,
           case .verbatim(let value) = text.storage {
            result[value] = node.id
        }
        for child in node.children {
            collectText(in: child, result: &result)
        }
    }
}

private struct EnvironmentReader: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let scheme = switch colorScheme {
        case .light: "light"
        case .dark: "dark"
        }
        Text(verbatim: "\(scheme)@\(displayScale)")
    }
}

private struct Item: Identifiable {
    let id: Int
}

private struct ItemList: View {
    let items: [Item]

    var body: some View {
        ForEach(items) { item in
            Text(verbatim: String(item.id))
        }
    }
}

private struct UnsupportedPrimitive: View {
    typealias Body = Never
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
private struct DocumentFixtureIntent: AppIntent {
    static let title: LocalizedStringResource = "Document fixture"
    static let persistentIdentifier = "OpenWidgetKit.DocumentFixtureIntent"

    init() {}

    func perform() async throws -> some IntentResult {
        .result()
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
private struct OpensAppFixtureIntent: AppIntent {
    static let title: LocalizedStringResource = "Open app fixture"
    static let openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult {
        .result()
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
private struct CustomResultFixtureIntent: AppIntent {
    static let title: LocalizedStringResource = "Custom result fixture"

    init() {}

    func perform() async throws -> CustomFixtureIntentResult {
        CustomFixtureIntentResult()
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private struct CustomFixtureIntentResult: IntentResult {
    var value: Never? { nil }
}

private enum FixtureEnvironmentKey: EnvironmentKey {
    static let defaultValue = 0
}

private enum IdentityFixtureError: Error {
    case expectedFailure
}

private extension EnvironmentValues {
    var fixtureValue: Int {
        get { self[FixtureEnvironmentKey.self] }
        set { self[FixtureEnvironmentKey.self] = newValue }
    }
}

private func requireSendable<Value: Sendable>(_ value: Value) {}
