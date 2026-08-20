# OpenWidgetKit Implementation Progress

## Current state

| Area | Status | Evidence |
|---|---|---|
| package/module boundary | Implemented in source | `Package.swift` and one-way target dependencies |
| requirements | Documented | `REQUIREMENTS.md` |
| runtime specification | Documented | `SPECIFICATION.md` |
| architecture decisions | Documented | `DESIGN.md` |
| M1 API baseline | Apple/local verified; Windows execution pending | `API_COMPATIBILITY.md` and `scripts/verify-m1-api.sh` |
| Windows constraints | Documented | `WINDOWS_NOTES.md` |
| Foundation/geometry ownership | Implemented and verified except Windows | OpenFoundation owns the canonical CFCG boundary and re-exports toolchain Foundation on full Swift |
| public SwiftUI API | Foundation slice only | `EnvironmentValues` substrate; View/Widget surface remains incomplete |
| public WidgetKit API | Foundation slice only | initial timeline entry/provider/value/context/family declarations |
| runtime behavior | Foundation slice only | finite, nonempty, ordered timeline and reload-date validation |
| Windows provider | Not implemented | no bridge or packaging target exists |
| build/test/runtime verification | Native and normal WASM passed | 12 Native tests, Apple system-module compile fixture, and normal WASM target build; Windows remains unverified |

Import-only success, declaration presence, or Package.swift resolution is not implementation evidence.

## Current foundational slice

```text
WidgetKit Timeline<Entry>
    -> package lowering
        -> OpenWidgetRuntime TimelineValidator
            -> ValidatedTimeline
            -> future TimelineScheduler
```

Source behavior tests cover accepted timelines, empty timelines, nonfinite dates,
out-of-order entries, reload dates, entry relevance, public value storage, canonical CFCG values, and the Apple-compatible
`EnvironmentVariants` key-path subscript call shape. All 12 Native tests passed on 2026-08-20, the initial API fixtures
typechecked against the pinned macOS 11, iOS 14, watchOS 9, and visionOS 26 system modules, Apple and replacement
behavior output matched, and the normal WASM API, behavior, and OpenCoreGraphics identity fixtures built with the pinned Swift 6.4 snapshot.
Windows compilation and real Widgets Board behavior remain unverified.

## Milestone dependency graph

```mermaid
flowchart LR
    M0["M0 Contract and skeleton<br/>complete"]
    M1["M1 Apple API fixtures<br/>1-2 weeks"]
    M2["M2 SwiftUI subset and IR<br/>2-4 weeks"]
    M3["M3 Timeline runtime<br/>2-3 weeks"]
    M4["M4 Adaptive Cards compiler<br/>2-3 weeks"]
    M5["M5 WinRT bridge and MSIX<br/>2-3 weeks"]
    M6["M6 Real Board static E2E<br/>1-2 weeks"]
    M7["M7 Interaction<br/>2-4 weeks"]

    M0 --> M1
    M1 --> M2
    M1 --> M3
    M2 --> M4
    M3 --> M4
    M3 --> M5
    M4 --> M6
    M5 --> M6
    M6 -->|source, semantic, or host mismatch| M1
    M6 -->|all static acceptance criteria pass| M7
```

Estimates are planning ranges for one experienced engineer, not completion claims. The critical path is
M1 -> M2/M3 -> M4/M5 -> M6. The M6 loop converges only when the same source compiles and the real
Widgets Board exercises successful and failed lifecycle paths.

## M0: Contract and package skeleton

- [x] Create standalone SwiftPM package directory
- [x] Define public `SwiftUI` product/module
- [x] Define public `WidgetKit` product/module
- [x] Define package-internal `OpenWidgetRuntime` target
- [x] Document source compatibility objective
- [x] Document module responsibility boundary
- [x] Document platform condition versus trait/macro decision
- [x] Document host-neutral `WidgetDocument`
- [x] Document Windows COM/MSIX/Adaptive Cards constraints
- [x] Document toolchain Foundation and geometry ownership
- [x] Add the OpenFoundation package dependency and re-export source boundary
- [x] Mark callable implementation as incomplete
- [x] Initialize a Git repository
- [x] Select the `1amageek/OpenWidgetKit` remote repository; release policy remains milestone-gated

OpenFoundation wiring is verified on Native and normal WASM. Windows compile/link verification is pending.
OpenWidgetKit does not advertise Embedded Swift support: its current Apple-compatible surface contains `Codable`,
which the pinned Embedded Swift mode does not provide.

## M1: Apple API inventory and compatibility fixtures

No public declaration may be added before its inventory row is complete.

| Family | SDK signature | Apple compile fixture | Availability/isolation | Status |
|---|---|---|---|---|
| `Widget` | pinned SDK declaration recorded | canonical Apple static-widget fixture passes | `@MainActor @preconcurrency`; exact baseline recorded | inventory complete; implementation M2/M3 |
| `WidgetConfiguration` | pinned SDK declaration and graph requirement recorded | exercised by both canonical Apple fixtures | `@MainActor @preconcurrency`; opaque body recorded | inventory complete; implementation M2/M3 |
| `WidgetBundle` | pinned SDK declaration recorded | canonical Apple bundle fixture passes | builder and `@MainActor @preconcurrency` recorded | inventory complete; implementation M3 |
| `StaticConfiguration` | generic initializer and opaque body recorded | canonical Apple static-widget and bundle fixtures pass | `@MainActor @preconcurrency`; current `Sendable` conformance recorded | inventory complete; implementation M2/M3 |
| `TimelineEntry` | exact initial date/relevance surface recorded | shared Apple/replacement fixture and behavior tests pass | exact initial availability applied | initial slice locally verified |
| `TimelineProvider` | exact initial generic and callback surface recorded | shared Apple/replacement fixture and conformance test pass | callback `@preconcurrency`/`@Sendable` recorded | declaration locally verified; ownership M3 |
| `TimelineProviderContext` | exact initial properties and key-path subscripts recorded | Apple/replacement geometry and key-path fixtures pass | exact initial availability applied | initial value slice locally verified |
| `Timeline` | exact generic constraint, storage, and initializer recorded | shared Apple/replacement fixture and behavior tests pass | exact initial availability applied | initial slice locally verified |
| `TimelineReloadPolicy` | exact `Equatable`-only surface recorded | positive behavior and Apple/replacement negative-conformance fixtures pass | exact initial availability applied | initial slice locally verified |
| `WidgetFamily` | exact conformances and first three cases recorded | shared Apple/replacement fixture and behavior test pass | type and case availability applied | initial slice locally verified |
| `WidgetCenter` | exact initial singleton/query/reload surface recorded | Apple compile fixture passes | callback `@preconcurrency`/`@Sendable` recorded | inventory complete; implementation M3 |

Required work:

- [x] Pin the exact Apple SDK/Xcode/compiler/interface-hash baseline
- [x] Store normalized public signature inventory without copying complete SDK interfaces
- [x] Create Apple compile fixtures for canonical widget and widget-bundle sources
- [x] Record generic constraints and opaque return behavior
- [x] Record actor isolation and `@Sendable` completion behavior
- [x] Define the initial availability baseline
- [x] Define explicit out-of-scope API families
- [x] Pin the exact Windows Swift installer and Foundation/runtime distribution baseline
- [x] Add one shared Apple/replacement compile fixture using `Date`, `CGFloat`, `CGPoint`, `CGSize`, and `CGRect`
- [x] Verify non-Embedded OpenCoreGraphics values cross the OpenWidgetKit API without conversion on macOS and normal WASM
- [x] Verify the intended Foundation re-export and public-import surface on Native and normal WASM; Windows remains pending
- [x] Add a dispatch-only Windows workflow pinned to the Swift installer SHA-256, action commits, and sibling-package commits
- [ ] Run `scripts/verify-m1-windows.ps1` on the pinned x86_64 Windows toolchain and record installed Foundation artifact hashes

## M2: Widget-scoped SwiftUI and semantic document

- [ ] `View` protocol and builder contract
- [ ] conditional/tuple/group content
- [ ] `Text`
- [ ] limited `Image`
- [ ] `VStack`
- [ ] `HStack`
- [ ] `Spacer`
- [ ] `Divider`
- [ ] stable-identity `ForEach`
- [ ] font/color/padding/frame/background/line-limit subset
- [ ] widget environment snapshot
- [ ] immutable `WidgetDocument`
- [ ] stable node/action/resource identities
- [ ] unsupported View/modifier typed errors
- [ ] success and failure behavior tests for every supported declaration

Canvas, Path, ZStack, gradient, animation, general application navigation, and responder APIs remain
unadvertised until a later milestone defines their semantics.

## M3: WidgetKit configuration and timeline runtime

- [ ] `Widget` bootstrap into runtime registration
- [ ] `WidgetConfiguration` internal lowering contract
- [ ] `StaticConfiguration`
- [ ] immutable widget registry and duplicate-kind failure
- [x] `TimelineEntry` declaration and default relevance (Native/WASM verified)
- [x] `TimelineProvider` callback declaration (Native/WASM verified)
- [ ] one-shot completion ownership
- [ ] timeout/duplicate/late completion failures
- [x] `Timeline` value and validation lowering (Native/WASM verified)
- [x] `TimelineReloadPolicy` value and runtime lowering (Native/WASM verified)
- [ ] `.atEnd`, `.after`, `.never` scheduler semantics
- [x] Initial `WidgetFamily` values and context value surface (Native/WASM verified)
- [ ] Host `WidgetFamily` context mapping
- [ ] `WidgetCenter` reload behavior
- [ ] instance generation and stale result rejection
- [ ] shutdown/cancellation behavior
- [ ] concurrent reload/delete/action tests

## M4: Adaptive Cards compiler

- [ ] canonical JSON encoder contract
- [ ] `WidgetDocument` validation
- [ ] structural hash
- [ ] template/data separation
- [ ] TextBlock mapping
- [ ] Image/resource mapping
- [ ] vertical Container mapping
- [ ] horizontal ColumnSet mapping
- [ ] family/theme host conditions
- [ ] explicit unsupported semantic errors
- [ ] template cache ownership and eviction
- [ ] golden success fixtures
- [ ] malformed/unsupported failure fixtures

## M5: Windows host bridge and packaging

- [ ] Pin Swift/Windows SDK/Windows App SDK/C++ toolset versions
- [ ] Record Foundation/runtime library versions and dynamic/static link mode
- [ ] Package only Foundation/runtime libraries from the compiler toolchain
- [ ] Reject mixed Foundation module/runtime versions during packaging validation
- [ ] Define narrow C ABI
- [ ] Implement C++/WinRT `IWidgetProvider`
- [ ] Copy callback values within callback scope
- [ ] Implement COM class factory lifetime
- [ ] Keep Swift `Widget.main()` as the only process entry point
- [ ] Implement host update and typed rejection path
- [ ] Define JSON/resource owner and exactly-once deallocator
- [ ] Create MSIX packaging project/tooling
- [ ] Register COM server and Widget Provider extension
- [ ] Validate CLSID/kind/family/resource metadata
- [ ] Build/link x64
- [ ] Build/link arm64

## M6: Real Windows Widgets Board static E2E

- [ ] Install signed development MSIX
- [ ] Discover widget in gallery
- [ ] Pin widget
- [ ] Exercise `CreateWidget`
- [ ] Exercise `Activate`/`Deactivate`
- [ ] Render small/medium/large
- [ ] Render light/dark themes
- [ ] Update timeline entries
- [ ] Exercise `.atEnd`, `.after`, `.never`
- [ ] Exercise `WidgetCenter` reload
- [ ] Exercise context changes during provider work
- [ ] Exercise delete during provider work
- [ ] Verify malformed payload failure remains observable
- [ ] Verify process shutdown and resource release
- [ ] Compile the exact same source against Apple system modules

## M7: Interaction

- [ ] Define supported SwiftUI interaction surface
- [ ] Stable action identity and payload
- [ ] `Action.Execute` compilation
- [ ] `OnActionInvoked` routing
- [ ] Unknown, duplicate, stale action failures
- [ ] Action-triggered timeline invalidation
- [ ] Callback reentrancy tests
- [ ] Decide App Intents compatibility boundary

## Future milestones

- richer layout and style mapping;
- accessibility and localization conformance;
- image rasterization through OpenCoreGraphics after Windows verification;
- provider customization;
- App Intents-compatible interaction;
- Web/WASI host adapter;
- remote HTML Widget backend;
- diagnostics and developer preview tooling.

## Completion evidence policy

Every completed row must link to or name evidence for:

1. public signature or internal contract;
2. concrete production implementation path;
3. successful behavior test;
4. failed behavior test;
5. applicable concurrency/lifetime test;
6. target compile/link evidence;
7. real host evidence when a platform adapter is involved.

Before removing any `FIXME(INCOMPLETE_IMPLEMENTATION)` marker, update this document in the same change.
An unsupported API must remain undeclared or return an explicit typed failure according to its public contract;
it must not return placeholder data and claim success.
