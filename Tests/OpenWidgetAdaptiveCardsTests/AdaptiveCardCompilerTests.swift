import AppIntents
import OpenFoundation
import OpenWidgetRuntime
@testable import OpenWidgetAdaptiveCards
import SwiftUI
import Testing

private struct FixtureResourceResolver: AdaptiveCardResourceResolving {
    func resolve(_ resource: WidgetResource) throws -> String {
        switch resource {
        case .namedImage(let name, nil):
            return "ms-appx:///Assets/\(name).png"
        case .namedImage(let name, let bundleIdentifier):
            throw AdaptiveCardCompilationError.unresolvedResource(
                "Unexpected bundle '\(bundleIdentifier ?? "")' for '\(name)'."
            )
        case .systemImage(let name):
            throw AdaptiveCardCompilationError.unresolvedResource(
                "System image '\(name)' has no Windows package resource."
            )
        }
    }
}

private struct LocalizedResourceFixtureTextResolver: WidgetTextResolving {
    let expected: LocalizedStringResource

    func resolve(_ text: WidgetText) throws -> String {
        guard case .localizedResource(let resource) = text.storage,
              resource == expected else {
            throw AdaptiveCardCompilationError.invalidLocalizedString(
                "The localized resource did not reach the rendering boundary."
            )
        }
        return "Resolved at render time"
    }
}

@MainActor
struct AdaptiveCardCompilerTests {
    @Test
    func emitsCanonicalThemeAndFamilyTemplateWithSeparateData() throws {
        let compiler = try AdaptiveCardCompiler(
            resourceResolver: FixtureResourceResolver()
        )
        let payload = try compiler.compile(
            makeUpdate(lightText: "Light", darkText: "Dark")
        )

        #expect(
            payload.templateJSON ==
                #"{"$schema":"http://adaptivecards.io/schemas/adaptive-card.json","body":[{"$when":"${$host.widgetSize == \"small\" && $host.hostTheme == \"light\"}","items":[{"text":"${light.v0}","type":"TextBlock","wrap":true}],"type":"Container"},{"$when":"${$host.widgetSize == \"small\" && $host.hostTheme == \"dark\"}","items":[{"text":"${dark.v0}","type":"TextBlock","wrap":true}],"type":"Container"}],"type":"AdaptiveCard","version":"1.6"}"#
        )
        #expect(payload.dataJSON == #"{"dark":{"v0":"Dark"},"light":{"v0":"Light"}}"#)
        #expect(payload.structureIdentity.count == 64)
        #expect(!payload.templateCompilationWasSkipped)
    }

    @Test
    func compilesIntentButtonIntoBoundActionExecute() throws {
        let compiler = try AdaptiveCardCompiler(
            resourceResolver: FixtureResourceResolver()
        )
        let payload = try compiler.compile(
            makeUpdate(
                light: Button("Run", intent: CompilerFixtureIntent()),
                dark: Button("Run dark", intent: CompilerFixtureIntent())
            )
        )

        #expect(payload.templateJSON.contains(#""type":"ActionSet""#))
        #expect(payload.templateJSON.contains(#""type":"Action.Execute""#))
        #expect(payload.templateJSON.contains(#""associatedInputs":"none""#))
        #expect(payload.dataJSON.contains("Run"))
        #expect(payload.dataJSON.contains("Run dark"))
        #expect(payload.actionBindings.count == 2)
        #expect(payload.actionBindings.allSatisfy {
            payload.templateJSON.contains($0.verb)
        })
    }

    @Test
    func resolvesLocalizedStringResourcesAtTheDataRenderingBoundary() throws {
        let resource: LocalizedStringResource = "Deferred title"
        let compiler = try AdaptiveCardCompiler(
            textResolver: LocalizedResourceFixtureTextResolver(expected: resource),
            resourceResolver: FixtureResourceResolver()
        )
        let payload = try compiler.compile(
            makeUpdate(
                light: Button(resource, intent: CompilerFixtureIntent()),
                dark: Button(resource, intent: CompilerFixtureIntent())
            )
        )

        #expect(payload.dataJSON.contains("Resolved at render time"))
    }

    @Test
    func rejectsActionSetsThatDifferAcrossEnvironmentVariants() throws {
        let compiler = try AdaptiveCardCompiler(
            resourceResolver: FixtureResourceResolver()
        )
        let update = try makeUpdate(
            light: Button("Run", intent: CompilerFixtureIntent()),
            dark: Text(verbatim: "No action")
        )

        #expect(throws: AdaptiveCardCompilationError.self) {
            try compiler.compile(update)
        }

        let mismatchedHandler = try makeUpdate(
            light: Button("Run", intent: CompilerFixtureIntent()),
            dark: Button("Run", intent: AlternativeCompilerFixtureIntent())
        )
        #expect(throws: AdaptiveCardCompilationError.self) {
            try compiler.compile(mismatchedHandler)
        }
    }

    @Test
    func rejectsButtonSemanticsWithoutAnAdaptiveCardsEquivalent() throws {
        let compiler = try AdaptiveCardCompiler(
            resourceResolver: FixtureResourceResolver()
        )
        let cancel = try makeUpdate(
            light: Button(
                "Cancel",
                role: .cancel,
                intent: CompilerFixtureIntent()
            ),
            dark: Button(
                "Cancel",
                role: .cancel,
                intent: CompilerFixtureIntent()
            )
        )
        let styled = try makeUpdate(
            light: Button(intent: CompilerFixtureIntent()) {
                Text(verbatim: "Styled").font(.headline)
            },
            dark: Button(intent: CompilerFixtureIntent()) {
                Text(verbatim: "Styled").font(.headline)
            }
        )
        let inheritedStyle = try makeUpdate(
            light: Button("Styled", intent: CompilerFixtureIntent())
                .lineLimit(1),
            dark: Button("Styled", intent: CompilerFixtureIntent())
                .lineLimit(1)
        )

        #expect(throws: AdaptiveCardCompilationError.self) {
            try compiler.compile(cancel)
        }
        _ = try compiler.compile(
            makeUpdate(
                light: Button("Plain", intent: CompilerFixtureIntent()),
                dark: Button("Plain", intent: CompilerFixtureIntent())
            )
        )
        #expect(throws: AdaptiveCardCompilationError.self) {
            try compiler.compile(styled)
        }
        #expect(throws: AdaptiveCardCompilationError.self) {
            try compiler.compile(inheritedStyle)
        }
    }

    @Test
    func preservesTheIntentInstanceForEachEnvironmentVariant() async throws {
        let recorder = CompilerActionRecorder()
        let compiler = try AdaptiveCardCompiler(
            resourceResolver: FixtureResourceResolver()
        )
        let payload = try compiler.compile(
            makeUpdate(
                light: Button(
                    "Light",
                    intent: CompilerRecordingIntent(recorder: recorder, value: 1)
                ),
                dark: Button(
                    "Dark",
                    intent: CompilerRecordingIntent(recorder: recorder, value: 2)
                )
            )
        )
        let light = try #require(
            payload.actionBindings.first { $0.verb.hasSuffix("|theme:light") }
        )
        let dark = try #require(
            payload.actionBindings.first { $0.verb.hasSuffix("|theme:dark") }
        )

        try await light.action.perform()
        try await dark.action.perform()

        #expect(await recorder.values == [1, 2])
    }

    @Test
    func reusesTemplateWhenOnlyEntryValuesChange() throws {
        let compiler = try AdaptiveCardCompiler(
            resourceResolver: FixtureResourceResolver()
        )
        let first = try compiler.compile(
            makeUpdate(lightText: "First", darkText: "First dark")
        )
        let second = try compiler.compile(
            makeUpdate(lightText: "Second", darkText: "Second dark")
        )

        #expect(first.templateJSON == second.templateJSON)
        #expect(first.structureIdentity == second.structureIdentity)
        #expect(first.dataJSON != second.dataJSON)
        #expect(second.templateCompilationWasSkipped)
    }

    @Test
    func canonicalOutputDoesNotDependOnVariantInputOrder() throws {
        let compiler = try AdaptiveCardCompiler(
            resourceResolver: FixtureResourceResolver()
        )
        let ordered = try makeUpdate(lightText: "Light", darkText: "Dark")
        let reversed = RuntimeWidgetUpdate(
            instanceID: ordered.instanceID,
            kind: ordered.kind,
            family: ordered.family,
            generation: ordered.generation,
            entry: RuntimeTimelineEntry(
                date: ordered.entry.date,
                document: ordered.entry.additionalDocuments[0],
                additionalDocuments: [ordered.entry.document]
            )
        )

        let orderedPayload = try compiler.compile(ordered)
        let reversedPayload = try compiler.compile(reversed)

        #expect(orderedPayload.templateJSON == reversedPayload.templateJSON)
        #expect(orderedPayload.dataJSON == reversedPayload.dataJSON)
        #expect(orderedPayload.structureIdentity == reversedPayload.structureIdentity)
    }

    @Test
    func evictsTheLeastRecentlyUsedTemplateAtCapacity() throws {
        let compiler = try AdaptiveCardCompiler(
            cacheCapacity: 1,
            resourceResolver: FixtureResourceResolver()
        )
        let plain = try makeUpdate(
            light: Text(verbatim: "Light"),
            dark: Text(verbatim: "Dark")
        )
        let styled = try makeUpdate(
            light: Text(verbatim: "Light").font(.headline),
            dark: Text(verbatim: "Dark").font(.headline)
        )

        let firstPlain = try compiler.compile(plain)
        let firstStyled = try compiler.compile(styled)
        let secondPlain = try compiler.compile(plain)

        #expect(!firstPlain.templateCompilationWasSkipped)
        #expect(!firstStyled.templateCompilationWasSkipped)
        #expect(!secondPlain.templateCompilationWasSkipped)
    }

    @Test
    func cacheHitsRefreshLeastRecentlyUsedOrder() throws {
        let compiler = try AdaptiveCardCompiler(
            cacheCapacity: 2,
            resourceResolver: FixtureResourceResolver()
        )
        let plain = try makeUpdate(
            light: Text(verbatim: "Light"),
            dark: Text(verbatim: "Dark")
        )
        let headline = try makeUpdate(
            light: Text(verbatim: "Light").font(.headline),
            dark: Text(verbatim: "Dark").font(.headline)
        )
        let limited = try makeUpdate(
            light: Text(verbatim: "Light").lineLimit(1),
            dark: Text(verbatim: "Dark").lineLimit(1)
        )

        _ = try compiler.compile(plain)
        _ = try compiler.compile(headline)
        let refreshedPlain = try compiler.compile(plain)
        #expect(refreshedPlain.templateCompilationWasSkipped)
        _ = try compiler.compile(limited)

        let evictedHeadline = try compiler.compile(headline)
        #expect(!evictedHeadline.templateCompilationWasSkipped)
    }

    @Test
    func rejectsMissingThemeVariant() throws {
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        environment.widgetFamily = .systemSmall
        let document = try makeWidgetDocument(
            Text(verbatim: "Only light"),
            environment: environment
        )
        let update = RuntimeWidgetUpdate(
            instanceID: "instance",
            kind: "fixture",
            family: .systemSmall,
            generation: 1,
            entry: RuntimeTimelineEntry(
                date: Date(timeIntervalSince1970: 0),
                document: document
            )
        )
        let compiler = try AdaptiveCardCompiler(
            resourceResolver: FixtureResourceResolver()
        )

        #expect(throws: AdaptiveCardCompilationError.missingThemeVariant("dark")) {
            try compiler.compile(update)
        }
    }

    @Test
    func rejectsModifierWithoutEquivalentInsteadOfDroppingIt() throws {
        let update = try makeUpdate(
            light: Text(verbatim: "Light").padding(8),
            dark: Text(verbatim: "Dark").padding(8)
        )
        let compiler = try AdaptiveCardCompiler(
            resourceResolver: FixtureResourceResolver()
        )

        #expect(throws: AdaptiveCardCompilationError.self) {
            try compiler.compile(update)
        }
    }

    @Test
    func mapsConfiguredLabeledImageAndRecordsResourceOwnership() throws {
        let update = try makeUpdate(
            light: Image(
                "logo",
                label: Text(verbatim: "OpenWidgetKit logo")
            ),
            dark: Image(
                "logo",
                label: Text(verbatim: "OpenWidgetKit logo")
            )
        )
        let compiler = try AdaptiveCardCompiler(
            resourceResolver: FixtureResourceResolver()
        )

        let payload = try compiler.compile(update)

        #expect(payload.templateJSON.contains(#""type":"Image""#))
        #expect(payload.dataJSON.contains("ms-appx:///Assets/logo.png"))
        #expect(payload.resourceReferences.count == 1)
        #expect(payload.resourceReferences[0].uri == "ms-appx:///Assets/logo.png")
    }

    @Test
    func cachedTemplateStillReevaluatesImageDataAndOwnership() throws {
        let compiler = try AdaptiveCardCompiler(
            resourceResolver: FixtureResourceResolver()
        )
        let first = try compiler.compile(
            makeUpdate(
                light: VStack {
                    Text(verbatim: "First heading")
                    Image("logo", label: Text(verbatim: "First image"))
                },
                dark: VStack {
                    Text(verbatim: "First dark heading")
                    Image("logo", label: Text(verbatim: "First dark image"))
                }
            )
        )
        let second = try compiler.compile(
            makeUpdate(
                light: VStack {
                    Text(verbatim: "Second heading")
                    Image("badge", label: Text(verbatim: "Second image"))
                },
                dark: VStack {
                    Text(verbatim: "Second dark heading")
                    Image("badge", label: Text(verbatim: "Second dark image"))
                }
            )
        )

        #expect(second.templateCompilationWasSkipped)
        #expect(first.templateJSON == second.templateJSON)
        #expect(second.dataJSON.contains("Second heading"))
        #expect(second.dataJSON.contains("Second image"))
        #expect(second.dataJSON.contains("ms-appx:///Assets/badge.png"))
        #expect(!second.dataJSON.contains("ms-appx:///Assets/logo.png"))
        #expect(second.resourceReferences.map(\.uri) == ["ms-appx:///Assets/badge.png"])
    }

    @Test
    func rejectsUnmappedSystemImage() throws {
        let compiler = try AdaptiveCardCompiler(
            resourceResolver: FixtureResourceResolver()
        )
        let update = try makeUpdate(
            light: Image(systemName: "star"),
            dark: Image(systemName: "star")
        )

        #expect(throws: AdaptiveCardCompilationError.self) {
            try compiler.compile(update)
        }
    }

    @Test
    func stableSHA256MatchesPublishedVector() {
        #expect(
            StableSHA256.hexDigest(of: Array("abc".utf8)) ==
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test
    func rejectsAnUnimplementedHostContract() {
        #expect(
            throws: AdaptiveCardCompilationError.unsupportedHostCapabilities(
                "M4 implements Adaptive Cards 1.6 compiler contract 1 only."
            )
        ) {
            _ = try AdaptiveCardCompiler(
                capabilities: AdaptiveCardHostCapabilities(
                    schemaVersion: "1.7",
                    compilerContractVersion: 2
                ),
                resourceResolver: FixtureResourceResolver()
            )
        }
    }

    private func makeUpdate(
        lightText: String,
        darkText: String
    ) throws -> RuntimeWidgetUpdate {
        try makeUpdate(
            light: Text(verbatim: lightText),
            dark: Text(verbatim: darkText)
        )
    }

    private func makeUpdate<Light: View, Dark: View>(
        light: Light,
        dark: Dark
    ) throws -> RuntimeWidgetUpdate {
        var lightEnvironment = EnvironmentValues()
        lightEnvironment.colorScheme = .light
        lightEnvironment.widgetFamily = .systemSmall
        var darkEnvironment = EnvironmentValues()
        darkEnvironment.colorScheme = .dark
        darkEnvironment.widgetFamily = .systemSmall
        let lightDocument = try makeWidgetDocument(
            light,
            environment: lightEnvironment
        )
        let darkDocument = try makeWidgetDocument(
            dark,
            environment: darkEnvironment
        )
        return RuntimeWidgetUpdate(
            instanceID: "instance",
            kind: "fixture",
            family: .systemSmall,
            generation: 1,
            entry: RuntimeTimelineEntry(
                date: Date(timeIntervalSince1970: 0),
                document: lightDocument,
                additionalDocuments: [darkDocument]
            )
        )
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
private struct CompilerFixtureIntent: AppIntent {
    static let title: LocalizedStringResource = "Compiler fixture"
    static let persistentIdentifier = "OpenWidgetKit.CompilerFixtureIntent"

    init() {}

    func perform() async throws -> some IntentResult {
        .result()
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
private struct AlternativeCompilerFixtureIntent: AppIntent {
    static let title: LocalizedStringResource = "Alternative compiler fixture"
    static let persistentIdentifier = "OpenWidgetKit.AlternativeCompilerFixtureIntent"

    init() {}

    func perform() async throws -> some IntentResult {
        .result()
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
private struct CompilerRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Recording fixture"

    private let recorder: CompilerActionRecorder
    private let value: Int

    init() {
        recorder = CompilerActionRecorder()
        value = 0
    }

    init(recorder: CompilerActionRecorder, value: Int) {
        self.recorder = recorder
        self.value = value
    }

    func perform() async throws -> some IntentResult {
        await recorder.record(value)
        return .result()
    }
}

private actor CompilerActionRecorder {
    private(set) var values: [Int] = []

    func record(_ value: Int) {
        values.append(value)
    }
}
