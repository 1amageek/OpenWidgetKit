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
        #expect(!payload.templateWasReused)
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
        #expect(second.templateWasReused)
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

        #expect(!firstPlain.templateWasReused)
        #expect(!firstStyled.templateWasReused)
        #expect(!secondPlain.templateWasReused)
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
    func rejectsUnmappedSystemImage() throws {
        let update = try makeUpdate(
            light: Image(systemName: "star"),
            dark: Image(systemName: "star")
        )
        let compiler = try AdaptiveCardCompiler(
            resourceResolver: FixtureResourceResolver()
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
