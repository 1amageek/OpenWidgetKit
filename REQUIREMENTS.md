# OpenWidgetKit Requirements

## Status and terminology

この文書はOpenWidgetKitの規範要件です。`MUST`、`SHOULD`、`MAY`はそれぞれ必須、
原則必須、任意を表します。実装状況は[IMPLEMENTATION_PROGRESS.md](IMPLEMENTATION_PROGRESS.md)
で管理し、要件の存在を実装済みの根拠にしてはいけません。

## Product objective

OpenWidgetKitは、Apple Widget向けソースをWindows固有コードへ書き換えることなく、
Windows Widgets Boardへ登録・表示・更新できる環境を提供しなければなりません。

```text
One widget source
    ├── Apple build   -> Apple SwiftUI + WidgetKit
    └── Windows build -> OpenWidgetKit SwiftUI + WidgetKit
```

## Source and module compatibility

### REQ-SOURCE-001: Unmodified imports

Widget sourceはAppleとWindowsで次のimportを共有できなければなりません。

```swift
import SwiftUI
import WidgetKit
```

利用側sourceに`#if os(Windows)`、module alias、Windows suffixを要求してはいけません。

### REQ-SOURCE-002: Unmodified widget declaration

`@main struct ...: Widget`、`body: some WidgetConfiguration`、
`StaticConfiguration`、`TimelineProvider`を使うWidget定義は、対象compatibility level内で
source変更なしにcompileできなければなりません。

### REQ-MODULE-001: Public module ownership

- `SwiftUI` moduleは`View` DSL、`Widget`、`WidgetConfiguration`、`WidgetBundle`を所有する。
- `WidgetKit` moduleは`StaticConfiguration`、timeline型、`WidgetFamily`、`WidgetCenter`を所有する。
- `WidgetKit`は`SwiftUI`へ依存してよい。
- `SwiftUI`は`WidgetKit`へ依存してはならない。
- 両moduleの内部連携は`OpenWidgetRuntime`へ依存する。

### REQ-MODULE-002: Apple isolation

Apple application targetはOpenWidgetKitの`SwiftUI`または`WidgetKit` productをlinkしては
なりません。Apple targetではsystem frameworkを使用し、Windows targetだけがこのpackage
productへ依存しなければなりません。

## Platform selection

### REQ-PLATFORM-001: Platform identity

Windows/Web/WASIの選択はSwiftPM platform conditionとcompiler platform conditionで
表現しなければなりません。

- dependency selection: `.when(platforms: [.windows])`または`.wasi`;
- source selection: `#if os(Windows)`、`#if os(WASI)`、または具体的capability;
- backend selectionはcomposition rootで一度だけ行う。

### REQ-PLATFORM-002: Package Trait usage

Package Traitはplatform identityに使用してはなりません。Traitを追加する場合は、
diagnostics、experimental rendererなど利用者が任意に有効化する加算的capabilityに限ります。

### REQ-PLATFORM-003: Macro usage

Macroをdependency/backend選択に使用してはなりません。Macroは将来、明示的に仕様化された
metadata生成など、source generationが必要な場合にだけ使用できます。

## Compatibility baseline

### REQ-API-001: Apple API baseline

公開宣言を追加する前に、次の原文を確認しなければなりません。

1. 固定したApple SDKの`.swiftinterface`またはsymbol graph;
2. `remark`で取得したApple documentation;
3. Apple上でcompileするsource fixture;
4. availability、generic constraint、actor isolation、`Sendable`契約。

推測したsignatureを公開してはいけません。

### REQ-API-002: Compatibility levels

互換性は宣言単位で次のいずれかに分類しなければなりません。

| Level | 意味 |
|---|---|
| Source | 同じsourceがcompileする |
| Semantic | 同じ入力が同じ意味・更新契約を持つ |
| Visual | host差を許容した上で指定したvisual fixtureを満たす |
| Unsupported | 明示的なtyped failureとなる |

同名APIの存在だけでSemanticまたはVisual互換を主張してはいけません。

### REQ-API-003: Initial surface

最初のAPI baselineは`StaticConfiguration`とcallback-based `TimelineProvider`を中心とする
iOS 14 / macOS 11由来の基本Widget surfaceです。このbaselineに含まれる
`TimelineEntryRelevance`は対象に含めます。新しいOSで追加されたApp Intent、providerの
`relevance()`/`WidgetRelevance`、Live Activity、Control Widgetは個別milestoneで追加します。

## Foundation and geometry

### REQ-FOUNDATION-001: OpenFoundation boundary

`SwiftUI`、`WidgetKit`、`OpenWidgetRuntime`は`OpenFoundation`をFoundation取り扱いの共通境界として
使用し、`Foundation`と`FoundationEssentials`をconsumer targetで直接選択してはなりません。

Windows buildではOpenFoundationが固定Swift toolchain組み込み`Foundation`を再公開しなければ
なりません。shipping packageは`swift-foundation`をSwiftPM dependencyとして追加してはなりません。
compiler、標準library、`Foundation`、`FoundationEssentials`、
`FoundationInternationalization`、Swift runtime libraryは同一toolchain由来でなければなりません。

Embedded buildではOpenFoundationがFoundation familyをimport/linkせず、明示されたportable subsetだけを
提供しなければなりません。

### REQ-FOUNDATION-002: Public type identity

full Swiftの公開互換APIはtoolchain Foundationの`Date`、`CGFloat`、`CGPoint`、`CGSize`、`CGRect`を
そのまま使用しなければなりません。OpenWidgetKit内で同名structまたは`Double`への独自typealiasを
定義してはいけません。Foundation互換値とCFCG値identityはOpenFoundation、graphics operationと
renderingはOpenCoreGraphicsの所有です。

非EmbeddedのOpenCoreGraphicsと値をコピーまたは変換せず受け渡せる同一のFoundation型identityを
維持します。AppleとWindowsでmodule qualificationが異なる場合も、共有source上の非修飾型名、
initializer、主要な値semanticsをcompile fixtureとbehavior testで確認します。

Embedded Widget backendはOpenFoundationのportable CFCG値を使用し、OpenWidgetKit内へ複製しては
いけません。値型だけを必要とするruntimeはOpenCoreGraphicsを依存へ追加せず、graphics operationや
rasterizationを選ぶbackendだけが明示的にOpenCoreGraphicsへ依存します。

### REQ-FOUNDATION-003: Public import surface

`SwiftUI` productは、共有Widget sourceが`import SwiftUI`と`import WidgetKit`だけでFoundationの
基本値型とgeometry型を利用できるimport surfaceを提供しなければなりません。

- `SwiftUI` umbrellaはOpenFoundationをre-exportする;
- `WidgetKit`はOpenFoundationとSwiftUIをpublic dependencyとしてimportする;
- `OpenWidgetRuntime`はpackage-visible contractに必要なvisibilityでOpenFoundationをimportする。

import成功だけで互換性を主張せず、`Date`、`CGFloat`、`CGSize`、`CGRect`を含む共有source fixtureを
Apple system moduleとWindows replacement moduleの両方でcompileします。

Embedded向け同一fixtureでもOpenFoundationのportable CFCG値を使用し、scalar幅と値semanticsを
compile/link/runtimeで検証します。

### REQ-FOUNDATION-004: Foundation family selection

full SwiftではOpenFoundationが`Foundation` umbrellaを再公開し、`FoundationEssentials`を公開互換moduleの
代替として直接使用してはなりません。Embeddedでは`FoundationEssentials`へ置換せずFoundation familyを
依存グラフから外さなければなりません。

size効果は同一toolchain、SDK、target triple、optimization、LTO、strip、application sourceを固定した
最終binary比較とlink symbol graphで検証し、推測した軽量化を完了根拠にしてはいけません。

## SwiftUI view evaluation

### REQ-VIEW-001: Widget-scoped surface

SwiftUI compatibility layerはWidgetに必要なViewとmodifierから実装しなければなりません。
一般application navigation、window、responder chainを初期依存関係に含めてはいけません。

### REQ-VIEW-002: Host-neutral document

View evaluationはAdaptive Cards JSONやWinRT型を直接生成せず、不変かつ`Sendable`な
host-neutral `WidgetDocument`を生成しなければなりません。

`WidgetDocument`は少なくとも次を表現します。

- stable node identity;
- text/image/container/action semantics;
- axis、alignment、spacing、padding、frame;
- font、color、background、line limit;
- accessibility/localization metadata;
- widget family、theme、display scaleなどのenvironment snapshot。

### REQ-VIEW-003: Unsupported behavior

表現不能なView、modifier、resource、layoutを無視して成功させてはいけません。
compilerは型付きエラーを返し、直前の正常なhost payloadを保持するか、host error pathへ
報告しなければなりません。

## Timeline runtime

### REQ-TIMELINE-001: Provider contract

公開`TimelineProvider`はAppleのcallback-based signatureとactor/`Sendable`契約を保ち、
内部でasync/awaitへ変換する場合もcompletionをexactly onceで完了しなければなりません。

### REQ-TIMELINE-002: Entry validation

runtimeは次を検証しなければなりません。

- timelineが空でないこと;
- entry dateが有効で、順序契約を満たすこと;
- reload policyの日付が有効であること;
- provider timeout、重複completion、未完了completionを検出できること。

不正なtimelineを空の成功値へ変換してはいけません。

### REQ-TIMELINE-003: Scheduling

instanceごとにgenerationを持ち、reload、context変更、削除、shutdown後に返った古いprovider
結果をhostへ送信してはいけません。`.atEnd`、`.after`、`.never`はWindows schedulerへ
意味を保って変換しなければなりません。

### REQ-TIMELINE-004: Reload

`WidgetCenter.reloadTimelines(ofKind:)`と`reloadAllTimelines()`は対象instanceを無効化し、
次の有効なtimeline取得をscheduleしなければなりません。未知kindはsilent successにせず、
内部diagnosticで区別可能にします。ただし公開signatureがnonthrowingの場合はAppleの
surfaceを変更せず、runtime diagnostic channelへ記録します。

## Windows host integration

### REQ-HOST-001: Provider lifecycle

Windows adapterは少なくとも次の`IWidgetProvider` eventを扱わなければなりません。

- `CreateWidget`;
- `DeleteWidget`;
- `OnActionInvoked`;
- `OnWidgetContextChanged`;
- `Activate`;
- `Deactivate`。

### REQ-HOST-002: Borrowed callback values

WinRT callback objectをcallback return後まで保持してはいけません。C++/WinRT bridgeは
必要な値をcallback scope内で所有済みvalueへコピーし、その値だけをSwiftへ渡します。

### REQ-HOST-003: Swift entry point

Widget sourceの`@main`を維持するため、process entry pointはSwiftの`Widget.main()`です。
C++/WinRT targetは別の`main`を定義せず、COM class factory登録とhost callbackを提供する
library boundaryでなければなりません。

### REQ-HOST-004: Narrow ABI

WinRT/COMのtemplate typeとexceptionをSwift runtimeへ直接漏らしてはいけません。
bridgeは所有権、byte count、encoding、error code、deallocatorを明示した狭いC ABIを
原則とします。C++ exceptionはbridge内で捕捉し、typed statusへ変換します。

### REQ-HOST-005: Adaptive Cards

最初のrendererはAdaptive Cards template/data JSONを生成します。template structureと
entry valueを分離し、同一structureではdataだけを更新できるようにしなければなりません。

### REQ-HOST-006: Packaging

Win32 Widget Providerはpackage manifestでCOM class、CLSID、widget definition、kind、family、
assetを登録しなければなりません。runtime registryとmanifestの重複情報はbuild時または
validation時に一致を検証しなければなりません。

## Interaction

### REQ-ACTION-001: Action identity

interactive Viewは安定したaction IDとpayloadへ変換し、Windows `Action.Execute`のverbから
登録済みhandlerへ配送します。未知、重複、期限切れaction IDはtyped failureとなります。

### REQ-ACTION-002: No responder dependency

Widget interactionはdiscrete host actionとして処理し、UIKit/AppKit responder chainを
要求してはいけません。将来一般application UIを実装する場合は別package/backendの責務です。

## Concurrency and ownership

### REQ-CONCURRENCY-001: State isolation

| State | Required isolation |
|---|---|
| widget definition registry | immutable after startup |
| provider lifecycle and ordered I/O | actor |
| instance and timeline generation | actor |
| short in-memory template cache | `Mutex<State>` |
| View evaluation | `MainActor` |
| COM callback object | C++ callback scope only |

I/O、`await`、external callback、host updateを`Mutex.withLock`内で実行してはいけません。

### REQ-CONCURRENCY-002: Shutdown

runtimeは明示的なshutdown pathを持ち、timeline taskをcancelし、event streamがあればfinishし、
host callbackの受付を停止し、C++ server lifetimeをexactly onceで解放しなければなりません。

### REQ-OWNERSHIP-001: Payload buffers

SwiftからC++へ渡すJSON/resource bufferはowner、byte count、lifetime、deallocatorを明示し、
二重解放、解放漏れ、callback外pointer escapeを防がなければなりません。

## Errors and diagnostics

### REQ-ERROR-001: Typed failure domains

少なくとも次のfailure domainを区別します。

- configuration/registration;
- timeline/provider;
- view evaluation/compilation;
- resource;
- host activation/update;
- packaging/manifest;
- shutdown/lifetime。

### REQ-ERROR-002: No silent fallback

未対応、壊れたJSON、host rejection、resource欠落、provider failureをplaceholder、空data、
最後に生成した架空値へ黙って置き換えてはいけません。placeholderはhostがplaceholderを
要求したときだけ使用します。

### REQ-DIAGNOSTIC-001: Correlation

diagnosticはwidget kind、instance ID、generation、operation、typed causeを関連付けます。
secret、認証token、個人情報、完全なuser data payloadを記録してはいけません。

## Performance

### REQ-PERFORMANCE-001: Repeated update path

timeline更新経路はtemplate structural hashを再利用し、変更されないlayout/styleを毎回
materializeしない設計とします。JSONやUTF変換はhost ABI境界に限定します。

### REQ-PERFORMANCE-002: Resource ownership

image/resourceはownerとidentityを保持し、各timeline entryで無条件にbyte arrayへコピー
してはいけません。Windows hostが要求する最終形式への変換だけを明示的copy boundaryとします。

## Acceptance criteria

最初のproduction milestoneは次をすべて満たしたときだけ完了です。

1. 同一fixture sourceがApple system modulesとWindows package modulesでcompile/linkする。
2. Windows x64とarm64でProvider executableがpackage化される。
3. 実Widgets Boardでpin、create、activate、update、resize/theme change、deactivate、deleteが動く。
4. `.atEnd`、`.after`、`.never`と明示reloadが実時間で検証される。
5. 対応Viewのgolden Adaptive Cards payloadと実host表示が検証される。
6. 未対応View、malformed resource、provider timeout、host rejectionが明示的に失敗する。
7. callback lifetime、reload/delete競合、shutdown競合、action再入を検証する。
8. manifest kind/family/CLSIDとruntime registryが一致する。
9. `FIXME(INCOMPLETE_IMPLEMENTATION)`を削除する宣言には成功・失敗のbehavior testがある。
10. Foundation geometry型がApple、Windows、OpenCoreGraphics間で同じsource valueとして受け渡せる。
11. 配布物のFoundation/runtime libraryが固定したcompiler toolchainと一致する。

build成功、import成功、型の存在だけをproduction完了の証拠にしてはいけません。
