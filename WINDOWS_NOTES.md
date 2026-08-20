# Windows Integration Notes

## Purpose

この文書はOpenWidgetKitのWindows adapter実装と検証で見落としやすい制約をまとめます。
Microsoft documentationは更新されるため、実装時には固定したWindows App SDK versionの
metadata/header/sampleと実Widgets Boardで再確認してください。

## Current host model

```text
Packaged provider process
    C++/WinRT IWidgetProvider
        <-> Windows Widget Platform
            <-> Widgets Board
```

現行の一般Widget Providerはpackaged Win32 appまたはPWAとして登録します。Win32 pathでは
out-of-process COM local serverが`IWidgetProvider`を実装します。Swiftだけで直接WinRTの
所有権とclass factoryを扱う前提にせず、薄いC++/WinRT bridgeを置きます。M5 sourceでは
bridgeをSwift executableへ静的に混ぜず、`OpenWidgetWindowsBridge.dll`として狭いC ABIから
動的にloadします。

## IWidgetProvider callbacks

最低限扱うeventは次の通りです。

| Callback | Runtime meaning |
|---|---|
| `CreateWidget` | instance生成、初回snapshot/update準備 |
| `DeleteWidget` | task cancel、state/resource解放 |
| `OnActionInvoked` | action verb/payload配送 |
| `OnWidgetContextChanged` | family/theme/context generation更新 |
| `Activate` | hostがupdateを必要とするactive state |
| `Deactivate` | background workを抑制できるinactive state |

Swift runtimeがinstance activityの正本です。`Deactivate`は進行中のprovider
requestと将来のtimeline sleepを新しいgenerationでfenceしますが、Microsoftの
contractどおりinactive中の明示的な`WidgetCenter` reloadは許可します。新規
`CreateWidget`はinactiveでも初期contentを1回生成し、inactive startup recovery
ではnonempty `CustomState`が以前のaccepted updateを示す場合だけWidgets Boardに保存済みの
contentを維持してactivationまでworkを延期します。empty stateは初期contentを生成します。削除後も
generation tombstoneをprocess lifetime中保持し、同じwidget IDが再生成された場合は
strictly newer generationと完全なtemplateを要求します。
起動時は既存instanceのrecovery eventをすべてqueueへ渡してから
`CoResumeClassObjects`を呼び、Activate/ContextChangedがrecoveryを追い越さないようにします。
MicrosoftのWidget Provider contractに従いclass factoryは`winrt::no_module_lock`で、
`IClassFactory::LockServer`はprocess lifetimeを保持しません。生成されたprovider objectだけが
custom server process counterを増減し、その参照がなくなった場合にshutdown eventを発行します。
payloadを持たないshutdown eventはowner allocationを行わず、allocation failureでprocess終了が
停止しない経路にします。

Microsoftはcallback引数objectをcallback外で保持しないよう要求しています。bridgeは必要値を
callback内でコピーします。

```text
WinRT callback object (borrowed)
    -> validate and copy in C++
        -> owned C ABI value
            -> Swift actor state
```

`WidgetContext`や`WidgetActionInvokedArgs`をSwift objectのstored propertyに保存しないでください。

## Entry point and COM lifetime

通常のMicrosoft sampleはC++ executableの`main`でclass factoryを登録します。しかし本packageは
`@main struct MyWidget: Widget`をsource-compatibleにするため、Swiftがprocess entry pointを
所有します。

C++ targetは次を提供するlibraryとします。

- COM apartment初期化;
- class factory登録;
- `IWidgetProvider` implementation;
- module/server reference count;
- shutdown event wait/signal;
- Swift callback table呼び出し。

C++側に第二の`main`を置いてはいけません。Swift `Widget.main()`がbridgeのrun operationを呼び、
shutdownまで戻らない構成にします。

## ABI boundary

Swift/C++ interopを広いobject graphへ使うと、WinRT template、exception、ARC/reference count、
compiler versionがruntime coreへ漏れます。最初のboundaryは狭いC ABIを推奨します。

ABI valueには次を明示します。

- pointerとbyte count;
- UTF encoding;
- owner context;
- release callback;
- operation ID;
- typed status code;
- callbackが同期か非同期か。

C++ exceptionはSwiftへ越境させず、bridge内で捕捉します。Swift errorもC++ exceptionへ変換せず、
typed result/statusとして返します。

## Adaptive Cards constraints

Windows Widgets UIはAdaptive Cards templateとdata JSONで表現します。

注意点:

- Widgets Boardが対応するschema/versionだけを使用する;
- generic Adaptive Cardsで使えるelementがWidget hostでも使えるとは仮定しない;
- interactive actionはWidget hostが対応する`Action.Execute`へ限定して開始する;
- `$host.widgetSize`はsmall/medium/largeを取る;
- light/dark themeとheader/customization capabilityをhost dataから判断する;
- malformed JSONやunsupported elementをhost fallbackへ任せて成功扱いしない;
- templateとdataを分離し、更新量を小さくする。

`ZStack`、arbitrary overlay、Canvas、Path、continuous animationは直接mappingできると仮定しません。

## Web widget caution

Web Widget Providerはremote URLのHTMLを表示できますが、Providerは引き続きAdaptive Card JSONを
提供し、hostがweb contentを表示できない場合のfallbackが必要です。

これは次の理由でMVP backendにしません。

- remote deploymentが必須;
- offline behaviorが異なる;
- authentication/CSP/network policyが必要;
- Swift runtimeが生成したlocal HTMLを直接hostへ渡す一般contractではない;
- fallback Adaptive Cardを別途保守する必要がある。

## MSIX and manifest

SwiftPM packageだけではWidget Providerの配布は完結しません。少なくとも次が必要です。

```text
Swift executable and runtime libraries
    + C++/WinRT bridge
    + Windows App SDK dependencies
    + COM server registration
    + WidgetProvider manifest extension
    + icons/screenshots/localized strings
    -> MSIX package
```

manifestでは次のdriftが特に危険です。

| Drift | Failure |
|---|---|
| CLSID mismatch | Provider activation failure |
| Definition ID/kind mismatch | runtime definition lookup failure |
| family/size mismatch | unsupported layout request |
| executable path mismatch | COM server start failure |
| missing asset/resource | gallery registration/display failure |

M5では`OpenWidgetProvider.json`をsingle source of truthにし、deterministicなmanifest generatorと
runtime registry validatorが同じ値を消費します。Widget bodyをbuild時に任意実行してmetadataを
抽出しません。

## Threading and reentrancy

COM callback threadをMainActorと仮定してはいけません。bridgeはowned eventをSwift runtimeへ
enqueueし、provider stateはactorで直列化します。

注意する競合:

- `CreateWidget`直後の`Activate`;
- timeline取得中の`OnWidgetContextChanged`;
- update送信中の`DeleteWidget`;
- action handler中のreload;
- shutdownとCOM callback;
- provider completionの重複または遅延;
- 古いgenerationのresource load完了。

外部callbackをactor state mutationの途中や`Mutex.withLock`内で呼ばないでください。

## Error reporting

`IWidgetProvider` callbackの多くは`void`なので、Swift errorをそのままthrowできません。
次を分離します。

1. callback入力の同期validation failure;
2. provider/timelineの非同期failure;
3. JSON compile failure;
4. `WidgetManager.UpdateWidget` rejection;
5. COM activation/lifetime failure。

公開Apple APIがnonthrowingでも、内部errorを消してはいけません。typed runtime state、structured
diagnostic、利用可能なWindows provider error interfaceへ接続します。新しい失敗後も直前payloadが
hostに残る場合、その事実を「更新成功」と表現しません。

## Resources and security

- action payloadを信頼せず、verb、instance、generation、payload shapeを検証する;
- remote URLやimage URIはscheme/domain policyを持つ;
- bundled resourceはpackage-relative pathだけを正本とし、`ms-appx:///` URIを導出する;
- percent-decode後もidentityが変わらないURI-safe pathだけを許可し、package root外へescapeさせない;
- diagnosticへtoken、cookie、完全なuser payloadを出さない;
- JSON stringへ未検証値を手連結せず、encoderを使用する;
- resource cacheのowner、eviction、shutdown releaseを明示する。

## Foundation distribution

Windows Providerは`OpenFoundation`をimport境界として使用し、OpenFoundationがSwift toolchainに
組み込まれた`Foundation`を再公開します。
`swift-foundation`をSwiftPM dependencyとして取得せず、package版とtoolchain版を同一processへ
混在させません。

公開`SwiftUI`/`WidgetKit` APIとOpenCoreGraphicsは、非Embedded WindowsではFoundationの
`Date`、`CGFloat`、`CGPoint`、`CGSize`、`CGRect`を共有します。Foundation structをC ABIへ
直接渡さず、bridge境界ではowned byte bufferと明示的なscalarだけを使用します。

MSIXへ含めるSwift/Foundation runtime libraryは、Providerをcompile/linkしたtoolchainの公式
`rtl.dynamic.private` redistributable merge moduleから取得します。Windows Swift installerが通常配置する
runtimeはhost architectureだけなので、SDK全体から同名DLLを再帰検索してcross-target payloadを選びません。
x64は`rtl.dynamic.private.amd64.msm`、ARM64は`rtl.dynamic.private.arm64.msm`を使用し、WiXによる
administrative imageのprivate-assembly layoutを保持します。別release、別snapshot、別architectureの
`Foundation`、`FoundationEssentials`、`FoundationInternationalization`、Swift runtime DLLを混在させません。
最終executableとbridgeから辿るSwift/Foundation dependency closureがmerge module内で閉じることも検証します。

Windows Providerでは`FoundationEssentials`を直接選択しません。Embedded deploymentの軽量化は
OpenFoundationがFoundation familyを完全に外す別分岐で扱い、Windows Providerへ混在させません。

## Toolchain baseline checklist

M5 source baselineは次の通りです。

| Component | Pin |
|---|---|
| Swift Windows | `swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a` |
| Windows App SDK | `2.3.1` |
| Widgets NuGet package | `2.0.5` |
| C++/WinRT NuGet package | `2.0.230706.1` |
| WiX Toolset SDK | `7.0.0` |
| Adaptive Cards host template | `1.6` |
| Visual C++ toolset | `v145` |
| Windows SDK | `10.0.26100.0` |
| architectures | `x64`, `arm64` |
| Foundation link mode | dynamic, official private redistributable merge module |

Swift Provider executableがpackaged appを所有します。C++/WinRT bridge DLLへ
`WindowsAppSDKSelfContained`を適用せず、生成manifestが
`Microsoft.WindowsAppRuntime.2` version 2.3.1.0以上をframework package dependencyとして宣言します。
Widgets runtime DLLはこのWindows package graphから解決します。

baseline更新時に次を固定して記録します。

- Swift Windows toolchain version and compiler commit;
- Foundation module/runtime library versions and dynamic/static link mode;
- Windows SDK version;
- Windows App SDK package version;
- C++ compiler/toolset version;
- target architectures;
- minimum supported Windows release;
- Adaptive Cards host schema/version;
- MSIX packaging tool version。

Windows App SDKの`latest`だけを記録して再現性があると扱ってはいけません。

## Verification checklist

- [ ] callback objectをscope外に保持しないことをcode reviewで確認
- [ ] Apple/WindowsでFoundation geometryを含む同一source fixtureがcompileする
- [ ] OpenFoundationを正本とするOpenCoreGraphicsとOpenWidgetKitのCFCG値が変換なしで受け渡せる
- [ ] Providerと同じtoolchain由来のFoundation/runtime libraryだけをMSIXへ含める
- [ ] C++ exceptionがABIを越えないことをfailure fixtureで確認
- [ ] JSON bufferがsuccess/failure/shutdownでexactly once解放される
- [ ] x64/arm64でCOM activationが成功する
- [ ] Widgets Boardでsmall/medium/largeを実表示する
- [ ] light/dark themeを実表示する
- [ ] create/activate/deactivate/deleteの順序差を検証する
- [ ] context change中のstale updateを拒否する
- [ ] inactive recovery、deactivate cancellation、inactive explicit reloadを検証する
- [ ] delete/recreate時にold generationを拒否しcomplete templateを再送する
- [ ] `Action.Execute`の正常/未知/期限切れactionを検証する
- [ ] malformed JSONとhost rejectionを失敗として観測する
- [ ] manifest/runtime metadata driftを自動検出する
- [ ] process shutdown後にtask、callback、COM referenceが残らない
