import AppIntents
import SwiftUI

@available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *)
private struct FixtureInteractionIntent: AppIntent {
    static let title: LocalizedStringResource = "Run fixture action"
    static let persistentIdentifier = "OpenWidgetKit.FixtureInteractionIntent"

    init() {}

    func perform() async throws -> some IntentResult {
        .result()
    }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
private struct FixtureCustomIntentResult: IntentResult {
    var value: Never? { nil }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
private struct FixtureCustomResultIntent: AppIntent {
    static let title: LocalizedStringResource = "Custom result"

    init() {}

    func perform() async throws -> FixtureCustomIntentResult {
        FixtureCustomIntentResult()
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *)
public func compileM7InteractionSurface() -> some View {
    Button(intent: FixtureInteractionIntent()) {
        Text("Run")
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *)
public func compileM7PersistentIntentIdentity() -> String {
    FixtureInteractionIntent.persistentIdentifier
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public func compileM7CustomResultIntent() -> some AppIntent {
    FixtureCustomResultIntent()
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *)
public func compileM7LocalizedInteractionSurface() -> some View {
    let title: LocalizedStringResource = "Delete"
    return Button(
        title,
        role: .destructive,
        intent: FixtureInteractionIntent()
    )
}

@available(iOS 26.0, macOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public func compileM7CurrentButtonRoles() -> some View {
    Button("Close", role: .close, intent: FixtureInteractionIntent())
}
