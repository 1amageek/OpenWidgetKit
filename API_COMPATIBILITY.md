# OpenWidgetKit M1 API Compatibility Baseline

## Purpose

This document is the M1 source-of-truth for the initial Widget API inventory.
It separates Apple SDK facts from OpenWidgetKit implementation status. An API
listed here is not implemented merely because its Apple declaration and compile
fixture have been recorded.

## Pinned Apple baseline

| Component | Pinned identity |
|---|---|
| Xcode | 27.0, build `27A5237l` |
| macOS SDK | 27.0, build `26A5406c` |
| iOS SDK | 27.0, build `24A5408c` |
| watchOS SDK | 27.0, build `24R5346a` |
| visionOS SDK | 27.0, build `24M5347a` |
| tvOS SDK | 27.0, build `24J5346a`; no WidgetKit framework is present |
| Swift compiler | Swift 6.4 development snapshot, compiler commit `424cae54c1a10da` |
| macOS SwiftUI / WidgetKit interfaces | SHA-256 `4360bfdc6d8d82d387805414cfe0159a9d78d261aee97a214d0c77f5ef01ff90` / `57f637423a9fc5cb1d796728142e87aeeebc803dbaa14831adb11cdf2736314c` |
| iOS SwiftUI / WidgetKit interfaces | SHA-256 `b74bc6cfd5a4e1d4b68de8a3d3c6ec6ec36e13b92d4d7db5b6436ef4925c9f51` / `6937fef5e51dda7842de9085b3206713bb9475c425ee88f6c2b6f246d52ee1b4` |
| watchOS SwiftUI / WidgetKit interfaces | SHA-256 `b56d2190f2716aad4e46685f366c023dab44ae672ede558ca4ac16305cb153d6` / `b38b91345630636e5eaf4c9effcb33d66c7d155ae31439d4146cac1a67619a28` |
| visionOS SwiftUI / WidgetKit interfaces | SHA-256 `fb46f2f2c9cff14cbe35b7eec19e55811cffcdc558e0b64771ecea3b40dae1b2` / `de1e37b5fda694b5998c91218776be7e20e4b6afc53688b2b20fd86c31e0bdaf` |

The interface hashes are verification inputs. The SDK files remain the
authority; this repository does not copy the complete Apple interfaces.

## Initial API inventory

The initial baseline is the iOS 14/macOS 11 callback-based static-widget
surface. The declarations below normalize SDK qualification such as
`Swift::String` to ordinary Swift source syntax.

| Family | Module | Exact initial contract | Availability and isolation | Implementation milestone |
|---|---|---|---|---|
| `Widget` | SwiftUI | `associatedtype Body: WidgetConfiguration`; `init()`; `var body: Body { get }` | iOS 14, macOS 11, watchOS 9, visionOS 1; tvOS unavailable; protocol, initializer, and body are `@MainActor @preconcurrency` | M2/M3 |
| `WidgetConfiguration` | SwiftUI | recursive `associatedtype Body: WidgetConfiguration`; `var body: Body { get }`; Apple has a default low-level graph requirement | iOS 14, macOS 11, watchOS 9, visionOS 1; tvOS unavailable; `@MainActor @preconcurrency` | M2/M3 |
| `WidgetBundle` | SwiftUI | `associatedtype Body: Widget`; `init()`; `@WidgetBundleBuilder var body: Body { get }` | iOS 14, macOS 11, watchOS 9, visionOS 1; tvOS unavailable; `@MainActor @preconcurrency` | M3 |
| `StaticConfiguration<Content>` | WidgetKit | `Content: View`; `body: some WidgetConfiguration`; generic initializer constrained by `Provider: TimelineProvider`, with `@ViewBuilder @escaping (Provider.Entry) -> Content` | iOS 14, macOS 11, watchOS 9, visionOS 26; tvOS unavailable; type/body/initializer are `@MainActor @preconcurrency`; current SDK also declares `Sendable` | M2/M3 |
| `TimelineEntry` | WidgetKit | `date: Date`; `relevance: TimelineEntryRelevance?`; default relevance is `nil`. Relevance is `Codable`/`Hashable`, with mutable `Float` score, mutable `TimeInterval` duration, and an initializer whose duration defaults to zero | iOS 14, macOS 11, watchOS 9, visionOS 26; tvOS unavailable | Implemented initial slice |
| `TimelineProvider` | WidgetKit | `associatedtype Entry: TimelineEntry`; `Context` alias; placeholder, snapshot, and timeline operations | same WidgetKit initial availability; callback operations are `@preconcurrency` and completions are `@escaping @Sendable` | Declaration implemented; completion ownership is M3 |
| `TimelineProviderContext` | WidgetKit | environment variants, family, preview flag, and `CGSize` display size; both writable-key-path environment subscripts return optional arrays; neither context type has a public initializer | same WidgetKit initial availability | Implemented initial value slice |
| `Timeline<EntryType>` | WidgetKit | `EntryType: TimelineEntry`; immutable entries and policy; public initializer | same WidgetKit initial availability | Implemented initial slice |
| `TimelineReloadPolicy` | WidgetKit | `Equatable` only; `.atEnd`, `.never`, and `.after(Date)`; no public initializer | same WidgetKit initial availability; not `Sendable` | Implemented initial slice |
| `WidgetFamily` | WidgetKit | raw `Int`; raw-representable, debug/string convertible, `Sendable`, and `Hashable`; initial cases are small, medium, and large | enum has same WidgetKit initial availability; the three initial cases are unavailable on watchOS and tvOS | Implemented initial slice |
| `WidgetCenter` | WidgetKit | singleton with no public initializer; callback current-configurations query; reload by kind; reload all; nested `UserInfoKey` exposes kind, family, and activity-ID keys | same WidgetKit initial availability; configuration callback is `@preconcurrency` with an `@escaping @Sendable` completion | M3 |

`Widget.main()` and `WidgetBundle.main()` are supplied by WidgetKit extensions
and are `@MainActor @preconcurrency`. Swift owns the process entry point in the
planned Windows provider architecture.

### Exact timeline declarations

```swift
public protocol TimelineEntry {
    var date: Date { get }
    var relevance: TimelineEntryRelevance? { get }
}

public protocol TimelineProvider {
    associatedtype Entry: TimelineEntry
    typealias Context = TimelineProviderContext

    func placeholder(in context: Context) -> Entry
    @preconcurrency
    func getSnapshot(
        in context: Context,
        completion: @escaping @Sendable (Entry) -> Void
    )
    @preconcurrency
    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<Entry>) -> Void
    )
}

public struct Timeline<EntryType> where EntryType: TimelineEntry {
    public let entries: [EntryType]
    public let policy: TimelineReloadPolicy
    public init(entries: [EntryType], policy: TimelineReloadPolicy)
}
```

### Intentional portable differences

Apple's `WidgetConfiguration` has a public low-level graph requirement whose
signature names SwiftUI implementation types. OpenWidgetKit must not reproduce
those private graph types. Its future protocol will preserve the source-facing
`Body` contract and provide an internal host-neutral lowering requirement with a
default implementation.

`TimelineReloadPolicy` must remain non-`Sendable`, matching Apple. Swift 6 rejects
stored global values whose public type is not `Sendable`, even when the values
are immutable. OpenWidgetKit therefore marks only `.atEnd` and `.never` as
`nonisolated(unsafe)`. Their stored representation is immutable and composed of
`Sendable` values. This annotation does not add a public `Sendable` conformance;
the negative fixture proves that both Apple and OpenWidgetKit reject such a
constraint.

The shared-state review matrix is identical on every target:

| Logical value | Native | normal WASM | Windows | Mutation | Lifetime/release |
|---|---|---|---|---|---|
| `.atEnd` | immutable `TimelineReloadPolicy` static storage | same storage and annotation | same storage and annotation | none | process lifetime; value storage has no external resource |
| `.never` | immutable `TimelineReloadPolicy` static storage | same storage and annotation | same storage and annotation | none | process lifetime; value storage has no external resource |

There is no Embedded branch, alternate raw state, callback, I/O, or external
resource inside either value. `.after(Date)` creates a new value and does not
touch static storage.

`WidgetCenter.getCurrentConfigurations` introduces `WidgetInfo`. The initial
Windows implementation will preserve `kind` and `family`. The Apple-only
`INIntent?` configuration property is outside the static configuration baseline
until an Intents compatibility module is designed; it must not be replaced with
an unrelated placeholder value.

## Explicitly out of scope for the initial baseline

- App Intent configuration and `AppIntentTimelineProvider`;
- provider `relevance()` and `WidgetRelevance`;
- Live Activities and ActivityKit;
- Control Widgets;
- accessory and post-iOS-14 widget families;
- interactive App Intents and configuration recommendations;
- preview-only and developer-tools APIs;
- Apple low-level graph implementation types.

An out-of-scope API remains undeclared until its own inventory and semantic
contract are complete.

## Compatibility fixtures

```mermaid
flowchart LR
    SDK["Pinned Apple interfaces"] --> Apple["Apple API fixtures"]
    SDK --> Inventory["This inventory"]
    Shared["Shared timeline fixture"] --> Apple
    Shared --> Replacement["OpenWidgetKit fixture target"]
    Behavior["Shared behavior executable"] --> Apple
    Behavior --> Replacement
    Context["TimelineProviderContext CGSize"] --> Identity["OpenCoreGraphics identity fixture"]
    Identity --> Replacement
    Negative["Non-Sendable negative fixture"] --> Apple
    Negative --> Replacement
```

| Fixture | Contract checked |
|---|---|
| `Fixtures/AppleAPI/CanonicalStaticWidget.swift` | `Widget`, `WidgetConfiguration`, `StaticConfiguration`, `ViewBuilder`, `Widget.main()` |
| `Fixtures/AppleAPI/CanonicalWidgetBundle.swift` | `WidgetBundle`, `WidgetBundleBuilder`, `WidgetBundle.main()` |
| `Fixtures/AppleAPI/WidgetCenterSurface.swift` | initial `WidgetCenter` query and reload call shapes |
| `Fixtures/AppleAPI/OpenWidgetKitFoundationSurface.swift` | `CGSize` and both environment-variant key-path subscripts |
| `Fixtures/SharedAPI/InitialTimelineSurface.swift` | one source file against Apple and replacement timeline APIs, including Foundation geometry |
| `Fixtures/BehaviorAPI/M1Behavior.swift` | differential runtime output for initial family, reload-policy, and relevance behavior |
| `Fixtures/NegativeAPI/TimelineReloadPolicySendable.swift` | both implementations reject the non-Apple `Sendable` conformance |
| `Fixtures/WorkspaceAPI` | OpenWidgetKit context geometry passes directly into OpenCoreGraphics APIs without conversion |

Run `scripts/verify-m1-api.sh` on the pinned macOS host. It validates every
recorded interface hash, typechecks Apple fixtures for macOS 11, iOS 14,
watchOS 9, and visionOS 26, confirms WidgetKit is absent from tvOS, builds the
replacement fixture, checks the negative conformance, compares
Apple/replacement runtime output, and builds the isolated workspace identity
fixture.

## Pinned Windows compile baseline

| Component | Pinned identity |
|---|---|
| Swift installer | `swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-01-a-windows10.exe` |
| Official artifact URL | `https://download.swift.org/swift-6.4.x-branch/windows10/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-01-a/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-01-a-windows10.exe` |
| Artifact size | 2,100,187,856 bytes |
| Artifact SHA-256 | `C287DD533A65A73D657B1B9F2305BE50552F89B46199A0F6162A287DEE547149` |
| Artifact ETag | `6C286D90F53F9C163D2903A8A6583474` |
| Swift source tag | `swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-01-a` |
| Peeled source commit | `db4e13695491982c8de74c36c5efb75bbc715987` |
| Initial target | `x86_64-unknown-windows-msvc` |

Foundation, FoundationEssentials, FoundationInternationalization, the standard
library, and runtime DLLs must all come from this one installer. The package does
not download a separate swift-foundation product.

`scripts/verify-m1-windows.ps1` is the Windows execution gate. It builds the
shared replacement and OpenCoreGraphics identity fixtures, executes the
replacement behavior fixture, proves the non-Apple `Sendable` conformance is
rejected, and emits the exact installed Foundation artifact hashes. A macOS
cross-compile is not accepted as Windows evidence.
`.github/workflows/m1-windows.yml` provisions the pinned installer on a real
Windows runner, checks its SHA-256, checks out the exact sibling-package commits,
executes the gate, and uploads the JSON evidence. The workflow is dispatch-only.

## Evidence status

As of 2026-08-20, the pinned Apple API fixtures typecheck for macOS 11, iOS 14,
watchOS 9, and visionOS 26, and the replacement checks pass on the local arm64
macOS host. All 12 focused Native behavior tests pass. The normal WASM API,
behavior, and OpenCoreGraphics identity fixture targets also build with the
pinned Swift 6.4 snapshot. The Windows script has not run on a Windows host. M1
therefore remains incomplete until that execution output and exact installed
Foundation artifact hashes are recorded.
