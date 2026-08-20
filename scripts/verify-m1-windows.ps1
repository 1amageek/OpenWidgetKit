$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedSwiftVersion = "6.4-dev"
$ExpectedTarget = "x86_64-unknown-windows-msvc"
$ExpectedSnapshot = "swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a"
$ExpectedCompilerCommit = "424cae54c1a10da79456ce66f330e6639439368f"
$ExpectedCompilerDisplayCommit = "424cae54c1a10da"
$ExpectedInstallerSHA256 = "17D5EBA8DFDC9E99BF13C0F26169022BE2F816B19E66D883A596D3512CFB0A04"
$RepositoryRoot = Split-Path -Parent $PSScriptRoot

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    throw "M1 Windows verification must run on Windows."
}

Push-Location $RepositoryRoot
try {
    $SwiftVersion = (& swift --version | Out-String).Trim()
    if (-not $SwiftVersion.Contains($ExpectedSwiftVersion)) {
        throw "Expected $ExpectedSwiftVersion from $ExpectedSnapshot. Actual: $SwiftVersion"
    }
    if (-not $SwiftVersion.Contains($ExpectedTarget)) {
        throw "Expected target $ExpectedTarget. Actual: $SwiftVersion"
    }
    if (-not $SwiftVersion.Contains($ExpectedCompilerDisplayCommit)) {
        throw "Unexpected Swift compiler commit. Actual: $SwiftVersion"
    }
    if ($env:M1_SWIFT_INSTALLER_SHA256 -ne $ExpectedInstallerSHA256) {
        throw "The verified installer SHA-256 was not propagated to the M1 gate."
    }

    $TargetInfo = & swift -print-target-info | ConvertFrom-Json
    if ($TargetInfo.swiftCompilerTag -ne $ExpectedSnapshot) {
        throw "Unexpected Swift compiler tag: $($TargetInfo.swiftCompilerTag)"
    }
    if ($TargetInfo.target.unversionedTriple -ne $ExpectedTarget) {
        throw "Unexpected target triple: $($TargetInfo.target.unversionedTriple)"
    }

    & swift build --target OpenWidgetKitAPIFixture | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "The replacement API fixture failed to build."
    }

    $ModuleSearchDirectories = Get-ChildItem -Path .build -Recurse |
        Where-Object { $_.Name -like '*.swiftmodule' } |
        ForEach-Object {
            if ($_.PSIsContainer) {
                $_.Parent.FullName
            }
            else {
                $_.Directory.FullName
            }
        } |
        Sort-Object -Unique
    if (-not $ModuleSearchDirectories) {
        throw "No replacement Swift module search paths were found."
    }
    $BridgeModuleMaps = @(
        Get-ChildItem -Path .build -Recurse -Filter *.modulemap -File |
            Where-Object {
                (Get-Content -Raw -Path $_.FullName).Contains(
                    "module COpenWidgetWindowsBridge"
                )
            } |
            Sort-Object FullName -Unique
    )
    if (-not $BridgeModuleMaps) {
        throw "The COpenWidgetWindowsBridge module map was not found."
    }

    $NegativeArguments = @(
        "-parse-as-library"
        "-swift-version"
        "6"
        "-typecheck"
    )
    foreach ($ModuleSearchDirectory in $ModuleSearchDirectories) {
        $NegativeArguments += @("-I", $ModuleSearchDirectory)
    }
    $NegativeArguments += @(
        "-Xcc",
        "-fmodule-map-file=$($BridgeModuleMaps[0].FullName)"
    )
    $NegativeArguments += "Fixtures/NegativeAPI/TimelineReloadPolicySendable.swift"

    $NegativeOutput = (& swiftc @NegativeArguments 2>&1 | Out-String).Trim()
    $NegativeExitCode = $LASTEXITCODE
    if ($NegativeExitCode -eq 0) {
        throw "The non-Sendable negative fixture unexpectedly typechecked."
    }
    $ExpectedNegativeDiagnostic = "type 'TimelineReloadPolicy' does not conform to the 'Sendable' protocol"
    if (-not $NegativeOutput.Contains($ExpectedNegativeDiagnostic)) {
        throw "The non-Sendable fixture failed unexpectedly: $NegativeOutput"
    }

    & swift build `
        --package-path Fixtures/WorkspaceAPI `
        --target OpenWidgetKitWorkspaceAPIFixture | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "The OpenCoreGraphics identity fixture failed to build."
    }

    $ExpectedBehaviorOutput = @(
        "family:0:systemSmall:systemSmall"
        "family:1:systemMedium:systemMedium"
        "family:2:systemLarge:systemLarge"
        "family-set-count:3"
        "policy:true:false:true:true:false"
        "timeline:1:42.0:true"
        'relevance:{"duration":60,"score":5}'
        "relevance-default-duration:0.0"
    ) -join "`n"
    $BehaviorOutput = @(& swift run OpenWidgetKitBehaviorFixture)
    if ($LASTEXITCODE -ne 0) {
        throw "The replacement behavior fixture failed to run."
    }
    $BehaviorOutput = @(
        $BehaviorOutput | Where-Object { $_ -match '^(family|family-set-count|policy|timeline|relevance|relevance-default-duration):' }
    ) -join "`n"
    if ($BehaviorOutput -ne $ExpectedBehaviorOutput) {
        throw "Unexpected replacement behavior output: $BehaviorOutput"
    }

    $SearchRoots = @(
        $env:SDKROOT
        $TargetInfo.paths.runtimeLibraryPaths
        $TargetInfo.paths.runtimeLibraryImportPaths
        $TargetInfo.paths.runtimeResourcePath
    ) | Where-Object { $_ } | Sort-Object -Unique

    $FoundationArtifacts = @(foreach ($Path in $SearchRoots) {
        if (Test-Path $Path) {
            Get-ChildItem -Path $Path -Recurse -File |
                Where-Object {
                    $_.Name -match '^Foundation(?:Essentials|Internationalization)?\.dll$' -or
                    $_.Name -match '^Foundation(?:Essentials|Internationalization)?\.swift(?:module|interface|doc|sourceinfo)$' -or
                    $_.FullName -match '[\\/]Foundation(?:Essentials|Internationalization)?\.swiftmodule[\\/]'
                } |
                ForEach-Object {
                    [PSCustomObject]@{
                        Path = $_.FullName
                        SHA256 = (Get-FileHash -Algorithm SHA256 -Path $_.FullName).Hash
                    }
                }
        }
    })
    $FoundationArtifacts = @($FoundationArtifacts | Sort-Object Path -Unique)

    if (-not $FoundationArtifacts) {
        throw "No Foundation runtime or module artifacts were found in the pinned toolchain."
    }
    foreach ($RequiredDLL in @(
        "Foundation.dll",
        "FoundationEssentials.dll",
        "FoundationInternationalization.dll"
    )) {
        if (-not ($FoundationArtifacts | Where-Object { $_.Path -like "*$RequiredDLL" })) {
            throw "The pinned distribution does not contain $RequiredDLL."
        }
    }
    $FoundationModuleArtifacts = @(
        $FoundationArtifacts | Where-Object {
            $_.Path -match '\.swift(?:module|interface|doc|sourceinfo)$' -or
            $_.Path -match '[\\/]Foundation(?:Essentials|Internationalization)?\.swiftmodule[\\/]'
        }
    )
    if (-not $FoundationModuleArtifacts) {
        throw "No Foundation module artifacts were found in the pinned Windows SDK."
    }

    $Evidence = [PSCustomObject]@{
        Snapshot = $ExpectedSnapshot
        CompilerTag = $TargetInfo.swiftCompilerTag
        CompilerCommit = $ExpectedCompilerCommit
        InstallerSHA256 = $env:M1_SWIFT_INSTALLER_SHA256
        SwiftVersion = $SwiftVersion
        Target = $TargetInfo.target
        SDKRoot = $env:SDKROOT
        RunnerImage = $env:ImageOS
        RunnerImageVersion = $env:ImageVersion
        GitHubRepository = $env:GITHUB_REPOSITORY
        GitHubRunID = $env:GITHUB_RUN_ID
        GitHubHeadSHA = $env:GITHUB_SHA
        BehaviorOutput = $BehaviorOutput
        NegativeConformanceDiagnostic = $ExpectedNegativeDiagnostic
        SearchRoots = $SearchRoots
        FoundationArtifacts = $FoundationArtifacts
    }

    $Evidence | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}
