#!/usr/bin/env bash

set -euo pipefail

readonly EXPECTED_XCODE_VERSION="Xcode 27.0"
readonly EXPECTED_XCODE_BUILD="Build version 27A5237l"
readonly EXPECTED_MACOS_SDK_BUILD="26A5406c"
readonly EXPECTED_IOS_SDK_BUILD="24A5408c"
readonly EXPECTED_WATCHOS_SDK_BUILD="24R5346a"
readonly EXPECTED_XROS_SDK_BUILD="24M5347a"
readonly EXPECTED_TVOS_SDK_BUILD="24J5346a"
readonly EXPECTED_SWIFT_COMMIT="424cae54c1a10da"
readonly EXPECTED_SWIFTUI_INTERFACE_SHA256="4360bfdc6d8d82d387805414cfe0159a9d78d261aee97a214d0c77f5ef01ff90"
readonly EXPECTED_SWIFTUICORE_INTERFACE_SHA256="2f5f6d708ec1d7d2a5fc63cf27eb57f3cbce7beb29f4ca1436e08e893d40bfb3"
readonly EXPECTED_WIDGETKIT_INTERFACE_SHA256="57f637423a9fc5cb1d796728142e87aeeebc803dbaa14831adb11cdf2736314c"
readonly EXPECTED_IOS_SWIFTUI_INTERFACE_SHA256="b74bc6cfd5a4e1d4b68de8a3d3c6ec6ec36e13b92d4d7db5b6436ef4925c9f51"
readonly EXPECTED_IOS_SWIFTUICORE_INTERFACE_SHA256="5664b8453cfdb2534c9444d153d070a2a94f0fcc9b9d16f88e42eee60e94c0cc"
readonly EXPECTED_IOS_WIDGETKIT_INTERFACE_SHA256="6937fef5e51dda7842de9085b3206713bb9475c425ee88f6c2b6f246d52ee1b4"
readonly EXPECTED_WATCHOS_SWIFTUI_INTERFACE_SHA256="b56d2190f2716aad4e46685f366c023dab44ae672ede558ca4ac16305cb153d6"
readonly EXPECTED_WATCHOS_SWIFTUICORE_INTERFACE_SHA256="4b1c9a11810fc3ae7d414966014d71115015fc48e65ad45783f6415d8c6a0cb5"
readonly EXPECTED_WATCHOS_WIDGETKIT_INTERFACE_SHA256="b38b91345630636e5eaf4c9effcb33d66c7d155ae31439d4146cac1a67619a28"
readonly EXPECTED_XROS_SWIFTUI_INTERFACE_SHA256="fb46f2f2c9cff14cbe35b7eec19e55811cffcdc558e0b64771ecea3b40dae1b2"
readonly EXPECTED_XROS_SWIFTUICORE_INTERFACE_SHA256="27e01eea3b2673579ee4befd4f7c99d3598292ec71112d7de94e453b97df85e9"
readonly EXPECTED_XROS_WIDGETKIT_INTERFACE_SHA256="de1e37b5fda694b5998c91218776be7e20e4b6afc53688b2b20fd86c31e0bdaf"
readonly EXPECTED_APPINTENTS_INTERFACE_SHA256="94714e4a254dee4c1c437e8467be401608c2cfab64b09377a89cf22718c028ff"
readonly EXPECTED_APPINTENTS_SWIFTUI_INTERFACE_SHA256="d0af683d3669cec03328ba749656ae2d6112afdc35f525901f03162989a47c1c"
readonly EXPECTED_IOS_APPINTENTS_INTERFACE_SHA256="c50c82523db423749562ec53e9f9bf13d26be33ac4e5ce0f5d39faf8d102df72"
readonly EXPECTED_IOS_APPINTENTS_SWIFTUI_INTERFACE_SHA256="5e808150275887388ab137c53dad9f80426c4f90743fcc05bba2b9918d30cb83"
readonly EXPECTED_WATCHOS_APPINTENTS_INTERFACE_SHA256="8fba6a4e4d342cb21576e89e8917db1551745ba3725bc08a8aed5649c1a4c93d"
readonly EXPECTED_WATCHOS_APPINTENTS_SWIFTUI_INTERFACE_SHA256="81b686777b2ad0925edfb4bc29e494860308311f3db2a0e062feb7893abb6f57"
readonly EXPECTED_XROS_APPINTENTS_INTERFACE_SHA256="57b3bebfc8ad4d5c6ef35b297a85f4d5f7ea6584a0bf76e5aff291ba2d97ce4d"
readonly EXPECTED_XROS_APPINTENTS_SWIFTUI_INTERFACE_SHA256="955412582943e88cc95054077efecda5bc5b70fd698f211fcec986c9084fa175"
readonly PINNED_TOOLCHAIN="org.swift.64202608141a"
readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
readonly TEMPORARY_DIRECTORY="$(mktemp -d)"

cd "$REPOSITORY_ROOT"
trap 'rm -rf "$TEMPORARY_DIRECTORY"' EXIT

fail() {
    printf 'OpenWidgetKit API verification failed: %s\n' "$1" >&2
    exit 1
}

require_line() {
    local expected="$1"
    local actual="$2"

    grep -Fqx "$expected" <<<"$actual" || fail "expected line '$expected'"
}

expect_typecheck_failure() {
    local expected_diagnostic="$1"
    shift

    local output
    local result

    set +e
    output=$("$@" 2>&1)
    result=$?
    set -e

    [[ $result -ne 0 ]] || fail "negative fixture unexpectedly typechecked"
    grep -Fq "$expected_diagnostic" <<<"$output" || {
        printf '%s\n' "$output" >&2
        fail "negative fixture failed for an unexpected reason"
    }
}

[[ "$(uname -s)" == "Darwin" ]] || fail "Apple API verification requires macOS"
[[ "$(uname -m)" == "arm64" ]] || fail "the pinned Apple interface is arm64"

readonly XCODE_VERSION_OUTPUT="$(xcodebuild -version)"
require_line "$EXPECTED_XCODE_VERSION" "$XCODE_VERSION_OUTPUT"
require_line "$EXPECTED_XCODE_BUILD" "$XCODE_VERSION_OUTPUT"

readonly SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
readonly IOS_SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
readonly WATCHOS_SDK_PATH="$(xcrun --sdk watchos --show-sdk-path)"
readonly XROS_SDK_PATH="$(xcrun --sdk xros --show-sdk-path)"
readonly TVOS_SDK_PATH="$(xcrun --sdk appletvos --show-sdk-path)"

[[ "$(xcrun --sdk macosx --show-sdk-build-version)" == "$EXPECTED_MACOS_SDK_BUILD" ]] || fail "unexpected macOS SDK build"
[[ "$(xcrun --sdk iphoneos --show-sdk-build-version)" == "$EXPECTED_IOS_SDK_BUILD" ]] || fail "unexpected iOS SDK build"
[[ "$(xcrun --sdk watchos --show-sdk-build-version)" == "$EXPECTED_WATCHOS_SDK_BUILD" ]] || fail "unexpected watchOS SDK build"
[[ "$(xcrun --sdk xros --show-sdk-build-version)" == "$EXPECTED_XROS_SDK_BUILD" ]] || fail "unexpected visionOS SDK build"
[[ "$(xcrun --sdk appletvos --show-sdk-build-version)" == "$EXPECTED_TVOS_SDK_BUILD" ]] || fail "unexpected tvOS SDK build"

readonly SWIFT_VERSION_OUTPUT="$(TOOLCHAINS="$PINNED_TOOLCHAIN" xcrun swift --version)"
grep -Fq "$EXPECTED_SWIFT_COMMIT" <<<"$SWIFT_VERSION_OUTPUT" || fail "unexpected Swift compiler commit"

readonly SWIFTUI_INTERFACE="$SDK_PATH/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface"
readonly SWIFTUICORE_INTERFACE="$SDK_PATH/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface"
readonly WIDGETKIT_INTERFACE="$SDK_PATH/System/Library/Frameworks/WidgetKit.framework/Modules/WidgetKit.swiftmodule/arm64e-apple-macos.swiftinterface"
readonly IOS_SWIFTUI_INTERFACE="$IOS_SDK_PATH/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface"
readonly IOS_SWIFTUICORE_INTERFACE="$IOS_SDK_PATH/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface"
readonly IOS_WIDGETKIT_INTERFACE="$IOS_SDK_PATH/System/Library/Frameworks/WidgetKit.framework/Modules/WidgetKit.swiftmodule/arm64e-apple-ios.swiftinterface"
readonly WATCHOS_SWIFTUI_INTERFACE="$WATCHOS_SDK_PATH/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64_32-apple-watchos.swiftinterface"
readonly WATCHOS_SWIFTUICORE_INTERFACE="$WATCHOS_SDK_PATH/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64_32-apple-watchos.swiftinterface"
readonly WATCHOS_WIDGETKIT_INTERFACE="$WATCHOS_SDK_PATH/System/Library/Frameworks/WidgetKit.framework/Modules/WidgetKit.swiftmodule/arm64_32-apple-watchos.swiftinterface"
readonly XROS_SWIFTUI_INTERFACE="$XROS_SDK_PATH/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-xros.swiftinterface"
readonly XROS_SWIFTUICORE_INTERFACE="$XROS_SDK_PATH/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-xros.swiftinterface"
readonly XROS_WIDGETKIT_INTERFACE="$XROS_SDK_PATH/System/Library/Frameworks/WidgetKit.framework/Modules/WidgetKit.swiftmodule/arm64e-apple-xros.swiftinterface"
readonly APPINTENTS_INTERFACE="$SDK_PATH/System/Library/Frameworks/AppIntents.framework/Modules/AppIntents.swiftmodule/arm64e-apple-macos.swiftinterface"
readonly APPINTENTS_SWIFTUI_INTERFACE="$SDK_PATH/System/Library/Frameworks/_AppIntents_SwiftUI.framework/Modules/_AppIntents_SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface"
readonly IOS_APPINTENTS_INTERFACE="$IOS_SDK_PATH/System/Library/Frameworks/AppIntents.framework/Modules/AppIntents.swiftmodule/arm64e-apple-ios.swiftinterface"
readonly IOS_APPINTENTS_SWIFTUI_INTERFACE="$IOS_SDK_PATH/System/Library/Frameworks/_AppIntents_SwiftUI.framework/Modules/_AppIntents_SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface"
readonly WATCHOS_APPINTENTS_INTERFACE="$WATCHOS_SDK_PATH/System/Library/Frameworks/AppIntents.framework/Modules/AppIntents.swiftmodule/arm64_32-apple-watchos.swiftinterface"
readonly WATCHOS_APPINTENTS_SWIFTUI_INTERFACE="$WATCHOS_SDK_PATH/System/Library/Frameworks/_AppIntents_SwiftUI.framework/Modules/_AppIntents_SwiftUI.swiftmodule/arm64_32-apple-watchos.swiftinterface"
readonly XROS_APPINTENTS_INTERFACE="$XROS_SDK_PATH/System/Library/Frameworks/AppIntents.framework/Modules/AppIntents.swiftmodule/arm64e-apple-xros.swiftinterface"
readonly XROS_APPINTENTS_SWIFTUI_INTERFACE="$XROS_SDK_PATH/System/Library/Frameworks/_AppIntents_SwiftUI.framework/Modules/_AppIntents_SwiftUI.swiftmodule/arm64e-apple-xros.swiftinterface"
readonly SWIFTUI_INTERFACE_SHA256="$(shasum -a 256 "$SWIFTUI_INTERFACE" | awk '{print $1}')"
readonly SWIFTUICORE_INTERFACE_SHA256="$(shasum -a 256 "$SWIFTUICORE_INTERFACE" | awk '{print $1}')"
readonly WIDGETKIT_INTERFACE_SHA256="$(shasum -a 256 "$WIDGETKIT_INTERFACE" | awk '{print $1}')"

[[ "$SWIFTUI_INTERFACE_SHA256" == "$EXPECTED_SWIFTUI_INTERFACE_SHA256" ]] || fail "SwiftUI interface drift"
[[ "$SWIFTUICORE_INTERFACE_SHA256" == "$EXPECTED_SWIFTUICORE_INTERFACE_SHA256" ]] || fail "SwiftUICore interface drift"
[[ "$WIDGETKIT_INTERFACE_SHA256" == "$EXPECTED_WIDGETKIT_INTERFACE_SHA256" ]] || fail "WidgetKit interface drift"
[[ "$(shasum -a 256 "$IOS_SWIFTUI_INTERFACE" | awk '{print $1}')" == "$EXPECTED_IOS_SWIFTUI_INTERFACE_SHA256" ]] || fail "iOS SwiftUI interface drift"
[[ "$(shasum -a 256 "$IOS_SWIFTUICORE_INTERFACE" | awk '{print $1}')" == "$EXPECTED_IOS_SWIFTUICORE_INTERFACE_SHA256" ]] || fail "iOS SwiftUICore interface drift"
[[ "$(shasum -a 256 "$IOS_WIDGETKIT_INTERFACE" | awk '{print $1}')" == "$EXPECTED_IOS_WIDGETKIT_INTERFACE_SHA256" ]] || fail "iOS WidgetKit interface drift"
[[ "$(shasum -a 256 "$WATCHOS_SWIFTUI_INTERFACE" | awk '{print $1}')" == "$EXPECTED_WATCHOS_SWIFTUI_INTERFACE_SHA256" ]] || fail "watchOS SwiftUI interface drift"
[[ "$(shasum -a 256 "$WATCHOS_SWIFTUICORE_INTERFACE" | awk '{print $1}')" == "$EXPECTED_WATCHOS_SWIFTUICORE_INTERFACE_SHA256" ]] || fail "watchOS SwiftUICore interface drift"
[[ "$(shasum -a 256 "$WATCHOS_WIDGETKIT_INTERFACE" | awk '{print $1}')" == "$EXPECTED_WATCHOS_WIDGETKIT_INTERFACE_SHA256" ]] || fail "watchOS WidgetKit interface drift"
[[ "$(shasum -a 256 "$XROS_SWIFTUI_INTERFACE" | awk '{print $1}')" == "$EXPECTED_XROS_SWIFTUI_INTERFACE_SHA256" ]] || fail "visionOS SwiftUI interface drift"
[[ "$(shasum -a 256 "$XROS_SWIFTUICORE_INTERFACE" | awk '{print $1}')" == "$EXPECTED_XROS_SWIFTUICORE_INTERFACE_SHA256" ]] || fail "visionOS SwiftUICore interface drift"
[[ "$(shasum -a 256 "$XROS_WIDGETKIT_INTERFACE" | awk '{print $1}')" == "$EXPECTED_XROS_WIDGETKIT_INTERFACE_SHA256" ]] || fail "visionOS WidgetKit interface drift"
[[ "$(shasum -a 256 "$APPINTENTS_INTERFACE" | awk '{print $1}')" == "$EXPECTED_APPINTENTS_INTERFACE_SHA256" ]] || fail "macOS AppIntents interface drift"
[[ "$(shasum -a 256 "$APPINTENTS_SWIFTUI_INTERFACE" | awk '{print $1}')" == "$EXPECTED_APPINTENTS_SWIFTUI_INTERFACE_SHA256" ]] || fail "macOS AppIntents SwiftUI overlay drift"
[[ "$(shasum -a 256 "$IOS_APPINTENTS_INTERFACE" | awk '{print $1}')" == "$EXPECTED_IOS_APPINTENTS_INTERFACE_SHA256" ]] || fail "iOS AppIntents interface drift"
[[ "$(shasum -a 256 "$IOS_APPINTENTS_SWIFTUI_INTERFACE" | awk '{print $1}')" == "$EXPECTED_IOS_APPINTENTS_SWIFTUI_INTERFACE_SHA256" ]] || fail "iOS AppIntents SwiftUI overlay drift"
[[ "$(shasum -a 256 "$WATCHOS_APPINTENTS_INTERFACE" | awk '{print $1}')" == "$EXPECTED_WATCHOS_APPINTENTS_INTERFACE_SHA256" ]] || fail "watchOS AppIntents interface drift"
[[ "$(shasum -a 256 "$WATCHOS_APPINTENTS_SWIFTUI_INTERFACE" | awk '{print $1}')" == "$EXPECTED_WATCHOS_APPINTENTS_SWIFTUI_INTERFACE_SHA256" ]] || fail "watchOS AppIntents SwiftUI overlay drift"
[[ "$(shasum -a 256 "$XROS_APPINTENTS_INTERFACE" | awk '{print $1}')" == "$EXPECTED_XROS_APPINTENTS_INTERFACE_SHA256" ]] || fail "visionOS AppIntents interface drift"
[[ "$(shasum -a 256 "$XROS_APPINTENTS_SWIFTUI_INTERFACE" | awk '{print $1}')" == "$EXPECTED_XROS_APPINTENTS_SWIFTUI_INTERFACE_SHA256" ]] || fail "visionOS AppIntents SwiftUI overlay drift"
[[ ! -e "$TVOS_SDK_PATH/System/Library/Frameworks/WidgetKit.framework" ]] || fail "WidgetKit unexpectedly exists in the tvOS SDK"

for fixture in Fixtures/AppleAPI/*.swift Fixtures/SharedAPI/*.swift; do
    TOOLCHAINS="$PINNED_TOOLCHAIN" xcrun swiftc \
        -parse-as-library \
        -swift-version 6 \
        -Xfrontend -enable-cross-import-overlays \
        -typecheck \
        -sdk "$SDK_PATH" \
        "$fixture"
done

for platform_specification in \
    "$IOS_SDK_PATH|arm64-apple-ios14.0" \
    "$WATCHOS_SDK_PATH|arm64_32-apple-watchos9.0" \
    "$XROS_SDK_PATH|arm64-apple-xros26.0"; do
    platform_sdk_path="${platform_specification%%|*}"
    platform_target="${platform_specification#*|}"

    for fixture in Fixtures/AppleAPI/*.swift Fixtures/SharedAPI/*.swift; do
        TOOLCHAINS="$PINNED_TOOLCHAIN" xcrun swiftc \
            -parse-as-library \
            -swift-version 6 \
            -Xfrontend -enable-cross-import-overlays \
            -typecheck \
            -sdk "$platform_sdk_path" \
            -target "$platform_target" \
            "$fixture"
    done

    expect_typecheck_failure \
        "type 'TimelineReloadPolicy' does not conform to the 'Sendable' protocol" \
        env TOOLCHAINS="$PINNED_TOOLCHAIN" xcrun swiftc \
            -parse-as-library \
            -swift-version 6 \
            -typecheck \
            -sdk "$platform_sdk_path" \
            -target "$platform_target" \
            Fixtures/NegativeAPI/TimelineReloadPolicySendable.swift

    expect_typecheck_failure \
        "conformance of 'ViewBuilder' to 'Sendable' is unavailable" \
        env TOOLCHAINS="$PINNED_TOOLCHAIN" xcrun swiftc \
            -parse-as-library \
            -swift-version 6 \
            -typecheck \
            -sdk "$platform_sdk_path" \
            -target "$platform_target" \
            Fixtures/NegativeAPI/ViewBuilderSendable.swift
done

for behavior_platform_specification in \
    "$IOS_SDK_PATH|arm64-apple-ios14.0" \
    "$XROS_SDK_PATH|arm64-apple-xros26.0"; do
    behavior_sdk_path="${behavior_platform_specification%%|*}"
    behavior_target="${behavior_platform_specification#*|}"
    TOOLCHAINS="$PINNED_TOOLCHAIN" xcrun swiftc \
        -parse-as-library \
        -swift-version 6 \
        -typecheck \
        -sdk "$behavior_sdk_path" \
        -target "$behavior_target" \
        Fixtures/BehaviorAPI/M1Behavior.swift
done

TOOLCHAINS="$PINNED_TOOLCHAIN" xcrun swiftc \
    -parse-as-library \
    -swift-version 6 \
    -sdk "$SDK_PATH" \
    -framework WidgetKit \
    -framework SwiftUI \
    -o "$TEMPORARY_DIRECTORY/apple-m1-behavior" \
    Fixtures/BehaviorAPI/M1Behavior.swift

readonly APPLE_BEHAVIOR_OUTPUT="$("$TEMPORARY_DIRECTORY/apple-m1-behavior")"

expect_typecheck_failure \
    "type 'TimelineReloadPolicy' does not conform to the 'Sendable' protocol" \
    env TOOLCHAINS="$PINNED_TOOLCHAIN" xcrun swiftc \
        -parse-as-library \
        -swift-version 6 \
        -typecheck \
        -sdk "$SDK_PATH" \
        Fixtures/NegativeAPI/TimelineReloadPolicySendable.swift

expect_typecheck_failure \
    "conformance of 'ViewBuilder' to 'Sendable' is unavailable" \
    env TOOLCHAINS="$PINNED_TOOLCHAIN" xcrun swiftc \
        -parse-as-library \
        -swift-version 6 \
        -typecheck \
        -sdk "$SDK_PATH" \
        Fixtures/NegativeAPI/ViewBuilderSendable.swift

TOOLCHAINS="$PINNED_TOOLCHAIN" xcrun swift build --target OpenWidgetKitAPIFixture
readonly REPLACEMENT_BEHAVIOR_OUTPUT="$(
    TOOLCHAINS="$PINNED_TOOLCHAIN" xcrun swift run OpenWidgetKitBehaviorFixture
)"

if [[ "$APPLE_BEHAVIOR_OUTPUT" != "$REPLACEMENT_BEHAVIOR_OUTPUT" ]]; then
    diff \
        <(printf '%s\n' "$APPLE_BEHAVIOR_OUTPUT") \
        <(printf '%s\n' "$REPLACEMENT_BEHAVIOR_OUTPUT") >&2 || true
    fail "Apple and replacement behavior fixtures differ"
fi

replacement_module_flags=()
while IFS= read -r module_directory; do
    replacement_module_flags+=("-I" "$module_directory")
done < <(
    find .build/out/Intermediates.noindex \
        -path '*/Debug/*/Objects-normal/arm64/*.swiftmodule' \
        -type f \
        -exec dirname {} \; | sort -u
)

[[ ${#replacement_module_flags[@]} -gt 0 ]] || fail "replacement module search paths were not found"

expect_typecheck_failure \
    "type 'TimelineReloadPolicy' does not conform to the 'Sendable' protocol" \
    env TOOLCHAINS="$PINNED_TOOLCHAIN" xcrun swiftc \
        -parse-as-library \
        -swift-version 6 \
        -typecheck \
        -sdk "$SDK_PATH" \
        "${replacement_module_flags[@]}" \
        Fixtures/NegativeAPI/TimelineReloadPolicySendable.swift

expect_typecheck_failure \
    "conformance of 'ViewBuilder' to 'Sendable' is unavailable" \
    env TOOLCHAINS="$PINNED_TOOLCHAIN" xcrun swiftc \
        -parse-as-library \
        -swift-version 6 \
        -typecheck \
        -sdk "$SDK_PATH" \
        "${replacement_module_flags[@]}" \
        Fixtures/NegativeAPI/ViewBuilderSendable.swift

TOOLCHAINS="$PINNED_TOOLCHAIN" xcrun swift build \
    --package-path ../OpenCoreGraphics \
    --target OpenCoreGraphics

readonly OPENWIDGETKIT_MODULE_DIRECTORY="$(
    TOOLCHAINS="$PINNED_TOOLCHAIN" xcrun swift build --show-bin-path
)"
readonly OPENCOREGRAPHICS_MODULE_DIRECTORY="$(
    TOOLCHAINS="$PINNED_TOOLCHAIN" xcrun swift build \
        --package-path ../OpenCoreGraphics \
        --show-bin-path
)"

[[ -d "$OPENWIDGETKIT_MODULE_DIRECTORY/WidgetKit.swiftmodule" ]] || \
    fail "replacement WidgetKit module was not found"
[[ -d "$OPENCOREGRAPHICS_MODULE_DIRECTORY/OpenCoreGraphics.swiftmodule" ]] || \
    fail "replacement OpenCoreGraphics module was not found"

TOOLCHAINS="$PINNED_TOOLCHAIN" xcrun swiftc \
    -parse-as-library \
    -swift-version 6 \
    -typecheck \
    -sdk "$SDK_PATH" \
    -I "$OPENWIDGETKIT_MODULE_DIRECTORY" \
    -I "$OPENCOREGRAPHICS_MODULE_DIRECTORY" \
    Fixtures/WorkspaceAPI/FoundationGeometryIdentity.swift

printf 'OpenWidgetKit Apple and replacement API verification passed.\n'
