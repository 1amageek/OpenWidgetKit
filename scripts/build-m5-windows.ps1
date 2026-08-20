param(
    [ValidateSet("x64", "arm64")]
    [string]$Architecture = "x64",
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$ConfigurationTemplate = Join-Path $RepositoryRoot "Windows\Packaging\OpenWidgetProvider.json"
$BridgeProject = Join-Path $RepositoryRoot "Windows\Bridge\OpenWidgetWindowsBridge.vcxproj"
$SwiftRuntimeProject = Join-Path $RepositoryRoot "Windows\Packaging\SwiftRuntime\OpenWidgetSwiftRuntime.wixproj"
$SwiftTriple = if ($Architecture -eq "x64") {
    "x86_64-unknown-windows-msvc"
} else {
    "aarch64-unknown-windows-msvc"
}
$MSBuildPlatform = if ($Architecture -eq "x64") { "x64" } else { "ARM64" }
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $RepositoryRoot ".build\m5-$Architecture"
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$RepositoryRootPath = [IO.Path]::GetFullPath($RepositoryRoot)
$DriveRoot = [IO.Path]::GetPathRoot($OutputDirectory)
if ($OutputDirectory -eq $RepositoryRootPath -or $OutputDirectory -eq $DriveRoot) {
    throw "OutputDirectory must be a dedicated build directory."
}
if (Test-Path $OutputDirectory) {
    if (-not (Test-Path $OutputDirectory -PathType Container)) {
        throw "OutputDirectory exists and is not a directory."
    }
    if (Get-ChildItem -Path $OutputDirectory -Force | Select-Object -First 1) {
        throw "OutputDirectory must not exist or must be empty."
    }
}
$StagingDirectory = Join-Path $OutputDirectory "staging"
$BridgeOutput = Join-Path $OutputDirectory "bridge"
$BridgeIntermediate = Join-Path $OutputDirectory "bridge-obj"
$SwiftRuntimeOutput = Join-Path $OutputDirectory "swift-runtime-msi"
$SwiftRuntimeIntermediate = Join-Path $OutputDirectory "swift-runtime-obj"
$SwiftRuntimeImage = Join-Path $OutputDirectory "swift-runtime-image"
$InspectionDirectory = Join-Path $OutputDirectory "inspection"
$EvidencePath = Join-Path $OutputDirectory "m5-build-evidence.json"
$MSIXPath = Join-Path $OutputDirectory "OpenWidgetKit-$Architecture.msix"

function Invoke-Checked {
    param([string]$FilePath, [string[]]$Arguments)
    & $FilePath @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE."
    }
}

function ConvertTo-BigEndianBytes {
    param([uint32]$Value)
    return [byte[]]@(
        [byte](($Value -shr 24) -band [uint32]0xFF)
        [byte](($Value -shr 16) -band [uint32]0xFF)
        [byte](($Value -shr 8) -band [uint32]0xFF)
        [byte]($Value -band [uint32]0xFF)
    )
}

function Get-PNGCRC32 {
    param([byte[]]$Bytes)
    # PowerShell interprets high-bit hexadecimal literals as signed Int32 values.
    [uint32]$CRC = [uint32]::MaxValue
    [uint32]$Polynomial = 3988292384
    foreach ($Byte in $Bytes) {
        $CRC = $CRC -bxor [uint32]$Byte
        for ($Bit = 0; $Bit -lt 8; $Bit += 1) {
            if (($CRC -band 1) -ne 0) {
                $CRC = [uint32](($CRC -shr 1) -bxor $Polynomial)
            } else {
                $CRC = [uint32]($CRC -shr 1)
            }
        }
    }
    return [uint32]($CRC -bxor [uint32]::MaxValue)
}

function Write-PNGChunk {
    param(
        [IO.MemoryStream]$Stream,
        [string]$Type,
        [byte[]]$Data
    )
    $TypeBytes = [Text.Encoding]::ASCII.GetBytes($Type)
    $CRCInput = [byte[]]::new($TypeBytes.Length + $Data.Length)
    [Array]::Copy($TypeBytes, 0, $CRCInput, 0, $TypeBytes.Length)
    [Array]::Copy($Data, 0, $CRCInput, $TypeBytes.Length, $Data.Length)
    $LengthBytes = ConvertTo-BigEndianBytes -Value $Data.Length
    $CRCBytes = ConvertTo-BigEndianBytes -Value (Get-PNGCRC32 -Bytes $CRCInput)
    $Stream.Write($LengthBytes, 0, $LengthBytes.Length)
    $Stream.Write($TypeBytes, 0, $TypeBytes.Length)
    $Stream.Write($Data, 0, $Data.Length)
    $Stream.Write($CRCBytes, 0, $CRCBytes.Length)
}

function Write-SolidPNG {
    param(
        [string]$Path,
        [int]$Width,
        [int]$Height
    )
    if ($Width -le 0 -or $Height -le 0) {
        throw "PNG dimensions must be positive."
    }
    $RowLength = 1 + ($Width * 4)
    $Raw = [byte[]]::new($RowLength * $Height)
    for ($Y = 0; $Y -lt $Height; $Y += 1) {
        $RowOffset = $Y * $RowLength
        for ($X = 0; $X -lt $Width; $X += 1) {
            $PixelOffset = $RowOffset + 1 + ($X * 4)
            $Raw[$PixelOffset] = 0x24
            $Raw[$PixelOffset + 1] = 0x78
            $Raw[$PixelOffset + 2] = 0xD4
            $Raw[$PixelOffset + 3] = 0xFF
        }
    }
    $CompressedStream = [IO.MemoryStream]::new()
    $Compressor = [IO.Compression.ZLibStream]::new(
        $CompressedStream,
        [IO.Compression.CompressionLevel]::SmallestSize,
        $true
    )
    try {
        $Compressor.Write($Raw, 0, $Raw.Length)
    }
    finally {
        $Compressor.Dispose()
    }
    $Header = [byte[]]::new(13)
    [Array]::Copy((ConvertTo-BigEndianBytes -Value $Width), 0, $Header, 0, 4)
    [Array]::Copy((ConvertTo-BigEndianBytes -Value $Height), 0, $Header, 4, 4)
    $Header[8] = 8
    $Header[9] = 6
    $PNG = [IO.MemoryStream]::new()
    try {
        $Signature = [byte[]]@(137, 80, 78, 71, 13, 10, 26, 10)
        $PNG.Write($Signature, 0, $Signature.Length)
        Write-PNGChunk -Stream $PNG -Type "IHDR" -Data $Header
        Write-PNGChunk -Stream $PNG -Type "IDAT" -Data $CompressedStream.ToArray()
        Write-PNGChunk -Stream $PNG -Type "IEND" -Data ([byte[]]::new(0))
        [IO.File]::WriteAllBytes($Path, $PNG.ToArray())
    }
    finally {
        $PNG.Dispose()
        $CompressedStream.Dispose()
    }
}

function Write-FixtureAssets {
    param([string]$Root)
    $AssetDirectory = Join-Path $Root "Assets"
    New-Item -ItemType Directory -Path $AssetDirectory -Force | Out-Null
    foreach ($Asset in @(
        @{ Name = "Square44Logo.png"; Width = 44; Height = 44 },
        @{ Name = "Square150Logo.png"; Width = 150; Height = 150 },
        @{ Name = "StoreLogo.png"; Width = 50; Height = 50 },
        @{ Name = "WidgetIcon.png"; Width = 50; Height = 50 },
        @{ Name = "WidgetScreenshot.png"; Width = 600; Height = 400 }
    )) {
        Write-SolidPNG `
            -Path (Join-Path $AssetDirectory $Asset.Name) `
            -Width $Asset.Width `
            -Height $Asset.Height
    }
}

function Assert-PEMachine {
    param(
        [string[]]$Files,
        [string]$TargetArchitecture
    )
    $MachinePattern = if ($TargetArchitecture -eq "x64") {
        '(?im)^\s*8664 machine \(x64\)'
    } else {
        '(?im)^\s*AA64 machine \(ARM64\)'
    }
    foreach ($File in $Files) {
        $Headers = (& dumpbin /nologo /headers $File | Out-String)
        if ($LASTEXITCODE -ne 0 -or $Headers -notmatch $MachinePattern) {
            throw "'$File' does not contain the expected $TargetArchitecture PE machine."
        }
    }
}

function Assert-RuntimeDependencyClosure {
    param(
        [string[]]$EntryPoints,
        [object[]]$RuntimeFiles
    )
    $RuntimeByName = @{}
    foreach ($RuntimeFile in $RuntimeFiles) {
        $Key = $RuntimeFile.Name.ToLowerInvariant()
        if ($RuntimeByName.ContainsKey($Key)) {
            throw "The Swift runtime administrative image contains duplicate '$($RuntimeFile.Name)' files."
        }
        $RuntimeByName[$Key] = $RuntimeFile.Source
    }
    $Pending = [Collections.Generic.Queue[string]]::new()
    foreach ($EntryPoint in $EntryPoints) {
        $Pending.Enqueue($EntryPoint)
    }
    $Inspected = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    while ($Pending.Count -gt 0) {
        $Binary = $Pending.Dequeue()
        if (-not $Inspected.Add($Binary)) { continue }
        $Dependents = (& dumpbin /nologo /dependents $Binary | Out-String) -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^[A-Za-z0-9_.+-]+\.dll$' } |
            Sort-Object -Unique
        foreach ($Dependent in $Dependents) {
            $Key = $Dependent.ToLowerInvariant()
            if ($RuntimeByName.ContainsKey($Key)) {
                $Pending.Enqueue($RuntimeByName[$Key])
            } elseif ($Dependent -match '^(Foundation|swift|dispatch|BlocksRuntime|icu|_Foundation)') {
                throw "The Swift redistributable does not close runtime dependency '$Dependent'."
            }
        }
    }
}

function Expand-SwiftRuntimeRedistributable {
    param(
        [string]$TargetArchitecture,
        [object]$BuildConfiguration,
        [string]$Destination
    )
    $SDKDirectory = [IO.DirectoryInfo]::new([IO.Path]::GetFullPath($env:SDKROOT))
    $PlatformVersionDirectory = $SDKDirectory.Parent.Parent.Parent.Parent
    if ($null -eq $PlatformVersionDirectory) {
        throw "SDKROOT does not have the expected Swift platform layout."
    }
    $SwiftInstallDirectory = $PlatformVersionDirectory.Parent.Parent
    if ($null -eq $SwiftInstallDirectory) {
        throw "The Swift installation root could not be derived from SDKROOT."
    }
    $RedistributablesDirectory = Join-Path `
        $SwiftInstallDirectory.FullName `
        "Redistributables\$($PlatformVersionDirectory.Name)"
    $MergeModuleArchitecture = if ($TargetArchitecture -eq "x64") {
        "amd64"
    } else {
        "arm64"
    }
    # Swift 6.4 names the merge module for the dynamically linked runtime
    # `rtl.shared`. The merge consumes that runtime into this application's
    # private installation directory; `shared` describes Swift linkage, not a
    # machine-wide installation policy.
    $MergeModuleName = "rtl.shared.$MergeModuleArchitecture.msm"
    $MergeModules = @(
        Get-ChildItem -Path $RedistributablesDirectory `
            -Filter $MergeModuleName -File -Recurse -ErrorAction SilentlyContinue
    )
    if ($MergeModules.Count -ne 1) {
        $AvailableMergeModules = @(
            Get-ChildItem -Path $SwiftInstallDirectory.FullName `
                -Filter "*.msm" -File -Recurse -ErrorAction SilentlyContinue |
                ForEach-Object { $_.FullName }
        ) -join "; "
        throw "Expected one '$MergeModuleName' in '$RedistributablesDirectory'; found $($MergeModules.Count). Available merge modules: $AvailableMergeModules"
    }
    $MergeModule = $MergeModules[0]

    [xml]$RuntimeProjectDocument = Get-Content -Raw $SwiftRuntimeProject
    $ExpectedWixSDK = "WixToolset.Sdk/$($BuildConfiguration.wixToolsetSDKVersion)"
    if ($RuntimeProjectDocument.Project.Sdk -ne $ExpectedWixSDK) {
        throw "The Swift runtime WiX project does not match the configured SDK pin."
    }

    Invoke-Checked msbuild @(
        $SwiftRuntimeProject,
        "/restore",
        "/p:Configuration=Release",
        "/p:Platform=$MSBuildPlatform",
        "/p:SwiftRuntimeMergeModule=$($MergeModule.FullName)",
        "/p:OutputPath=$SwiftRuntimeOutput\",
        "/p:BaseIntermediateOutputPath=$SwiftRuntimeIntermediate\",
        "/p:RestoreForceEvaluate=true"
    )
    $NuGetRoot = if ($env:NUGET_PACKAGES) {
        $env:NUGET_PACKAGES
    } else {
        Join-Path $env:USERPROFILE ".nuget\packages"
    }
    $WixPackagePath = Join-Path $NuGetRoot `
        "wixtoolset.sdk\$($BuildConfiguration.wixToolsetSDKVersion)\wixtoolset.sdk.$($BuildConfiguration.wixToolsetSDKVersion).nupkg"
    if (-not (Test-Path $WixPackagePath)) {
        throw "The pinned WiX Toolset SDK package was not restored."
    }
    $WixPackageHash = (Get-FileHash -Algorithm SHA256 -Path $WixPackagePath).Hash
    if ($WixPackageHash -ne "917009BEF10F430EE72C4401F70FFCB36562A53F41EA027B8DCACBA5E9886A6F") {
        throw "WiX Toolset SDK package hash mismatch: $WixPackageHash"
    }
    $RuntimeMSIs = @(
        Get-ChildItem -Path $SwiftRuntimeOutput -Filter "*.msi" -File -Recurse
    )
    if ($RuntimeMSIs.Count -ne 1) {
        throw "Expected one Swift runtime administrative MSI; found $($RuntimeMSIs.Count)."
    }
    New-Item -ItemType Directory -Path $SwiftRuntimeImage -Force | Out-Null
    & msiexec.exe @(
        "/a", $RuntimeMSIs[0].FullName, "/qn", "/norestart",
        "TARGETDIR=$SwiftRuntimeImage"
    )
    if ($LASTEXITCODE -notin @(0, 3010)) {
        throw "Swift runtime administrative extraction failed with exit code $LASTEXITCODE."
    }
    $SwiftCoreFiles = @(
        Get-ChildItem -Path $SwiftRuntimeImage -Filter "swiftCore.dll" -File -Recurse
    )
    if ($SwiftCoreFiles.Count -ne 1) {
        throw "Expected one swiftCore.dll in the Swift runtime administrative image; found $($SwiftCoreFiles.Count)."
    }
    $PayloadRoot = $SwiftCoreFiles[0].Directory.Parent.FullName
    $PayloadItems = @(Get-ChildItem -Path $PayloadRoot -Force)
    if (-not $PayloadItems) {
        throw "The Swift runtime administrative image is empty."
    }
    $PayloadItems | Copy-Item -Destination $Destination -Recurse

    $RuntimeFiles = @(
        Get-ChildItem -Path $PayloadRoot -Filter "*.dll" -File -Recurse |
            ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.Name
                    Source = $_.FullName
                    Path = [IO.Path]::GetRelativePath(
                        $PayloadRoot,
                        $_.FullName
                    ).Replace("\", "/")
                    SHA256 = (Get-FileHash -Algorithm SHA256 -Path $_.FullName).Hash
                }
            } | Sort-Object Path
    )
    if (-not $RuntimeFiles) {
        throw "The Swift runtime administrative image contains no DLLs."
    }
    Assert-PEMachine `
        -Files @($RuntimeFiles | ForEach-Object { $_.Source }) `
        -TargetArchitecture $TargetArchitecture

    return [PSCustomObject]@{
        MergeModule = [PSCustomObject]@{
            Name = $MergeModule.Name
            SHA256 = (Get-FileHash -Algorithm SHA256 -Path $MergeModule.FullName).Hash
        }
        WixToolsetSDK = [PSCustomObject]@{
            Version = $BuildConfiguration.wixToolsetSDKVersion
            SHA256 = $WixPackageHash
        }
        Files = $RuntimeFiles
    }
}

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    throw "M5 packaging must run on Windows."
}

Push-Location $RepositoryRoot
try {
    $Configuration = Get-Content -Raw $ConfigurationTemplate | ConvertFrom-Json
    $Configuration.provider.architecture = $Architecture
    if ($Configuration.build.foundationLinkMode -ne "dynamic") {
        throw "The M5 packaging gate currently requires dynamic Foundation linkage."
    }
    if (-not $env:OPENWIDGET_SWIFT_SNAPSHOT) {
        throw "OPENWIDGET_SWIFT_SNAPSHOT must identify the verified Swift installer."
    }
    if ($env:OPENWIDGET_SWIFT_SNAPSHOT -ne $Configuration.build.swiftSnapshot) {
        throw "Swift snapshot provenance mismatch: $env:OPENWIDGET_SWIFT_SNAPSHOT"
    }
    if (-not $env:OPENWIDGET_SWIFT_TOOLCHAIN_IDENTIFIER) {
        throw "OPENWIDGET_SWIFT_TOOLCHAIN_IDENTIFIER must identify the active toolchain."
    }
    if ($env:OPENWIDGET_SWIFT_TOOLCHAIN_IDENTIFIER -ne $Configuration.build.swiftToolchainIdentifier) {
        throw "Swift toolchain provenance mismatch: $env:OPENWIDGET_SWIFT_TOOLCHAIN_IDENTIFIER"
    }
    $SwiftVersion = (& swift --version | Out-String).Trim()
    if (-not $SwiftVersion.Contains("Swift version 6.4-dev")) {
        throw "The configured Swift 6.4 development snapshot is not active: $SwiftVersion"
    }
    $TargetInfo = & swift -print-target-info -target $SwiftTriple | ConvertFrom-Json
    if ($TargetInfo.target.unversionedTriple -ne $SwiftTriple) {
        throw "Swift target mismatch: $($TargetInfo.target.unversionedTriple)"
    }
    Invoke-Checked swift @(
        "run", "-c", "release", "openwidget-packager",
        "validate-metadata", $ConfigurationTemplate
    )
    New-Item -ItemType Directory -Path $StagingDirectory -Force | Out-Null
    Write-FixtureAssets -Root $StagingDirectory

    $StagedConfiguration = Join-Path $StagingDirectory "OpenWidgetProvider.json"
    $Configuration | ConvertTo-Json -Depth 12 |
        Set-Content -Path $StagedConfiguration -Encoding utf8NoBOM
    $PublicDirectory = Join-Path $StagingDirectory "Public"
    New-Item -ItemType Directory -Path $PublicDirectory -Force | Out-Null
    Copy-Item -Path $StagedConfiguration -Destination $PublicDirectory

    Invoke-Checked swift @(
        "build", "-c", "release", "--triple", $SwiftTriple,
        "--product", "OpenWidgetWindowsProviderFixture"
    )
    $SwiftExecutable = Get-ChildItem -Path (Join-Path $RepositoryRoot ".build") `
        -Filter "OpenWidgetWindowsProviderFixture.exe" -File -Recurse |
        Where-Object { $_.FullName -match 'release' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $SwiftExecutable) {
        throw "The Swift provider executable was not produced."
    }
    Copy-Item $SwiftExecutable.FullName $StagingDirectory

    Invoke-Checked msbuild @(
        $BridgeProject,
        "/restore",
        "/p:Configuration=Release",
        "/p:Platform=$MSBuildPlatform",
        "/p:OpenWidgetWindowsAppSDKVersion=$($Configuration.build.windowsAppSDKVersion)",
        "/p:OpenWidgetWidgetsPackageVersion=$($Configuration.build.widgetsPackageVersion)",
        "/p:OpenWidgetCppWinRTVersion=$($Configuration.build.cppWinRTVersion)",
        "/p:OpenWidgetVisualCToolset=$($Configuration.build.visualCToolset)",
        "/p:OpenWidgetWindowsSDKVersion=$($Configuration.build.windowsSDKVersion)",
        "/p:OutDir=$BridgeOutput\",
        "/p:BaseIntermediateOutputPath=$BridgeIntermediate\",
        "/p:RestoreForceEvaluate=true"
    )
    $AssetsFile = Get-ChildItem -Path $BridgeIntermediate `
        -Filter "project.assets.json" -File -Recurse |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $AssetsFile) {
        throw "NuGet did not produce project.assets.json for the bridge."
    }
    $Assets = Get-Content -Raw $AssetsFile.FullName | ConvertFrom-Json -AsHashtable
    foreach ($ExpectedPackage in @(
        "Microsoft.WindowsAppSDK/$($Configuration.build.windowsAppSDKVersion)",
        "Microsoft.WindowsAppSDK.Widgets/$($Configuration.build.widgetsPackageVersion)",
        "Microsoft.Windows.CppWinRT/$($Configuration.build.cppWinRTVersion)",
        "Microsoft.WindowsAppSDK.Runtime/$($Configuration.build.windowsAppSDKVersion)"
    )) {
        if (-not $Assets.libraries.ContainsKey($ExpectedPackage)) {
            throw "NuGet resolved an unexpected Windows App SDK graph; missing $ExpectedPackage."
        }
    }
    $NuGetRoot = if ($env:NUGET_PACKAGES) {
        $env:NUGET_PACKAGES
    } else {
        Join-Path $env:USERPROFILE ".nuget\packages"
    }
    $PinnedPackages = @(
        @{
            Path = Join-Path $NuGetRoot "microsoft.windowsappsdk\$($Configuration.build.windowsAppSDKVersion)\microsoft.windowsappsdk.$($Configuration.build.windowsAppSDKVersion).nupkg"
            SHA256 = "9C9A0DC48EE023B829313E7B8E4FA91818D2E4C09CD5303FB2C3805F3097617B"
        },
        @{
            Path = Join-Path $NuGetRoot "microsoft.windowsappsdk.widgets\$($Configuration.build.widgetsPackageVersion)\microsoft.windowsappsdk.widgets.$($Configuration.build.widgetsPackageVersion).nupkg"
            SHA256 = "7F1B585EF8F012784D2CB91B86E809814CECCAB74183A5979EF45DB141779CB5"
        },
        @{
            Path = Join-Path $NuGetRoot "microsoft.windows.cppwinrt\$($Configuration.build.cppWinRTVersion)\microsoft.windows.cppwinrt.$($Configuration.build.cppWinRTVersion).nupkg"
            SHA256 = "A99ECA1C244DD730B31554E6D4850E685F40BFB7CB0BD1CFB1561169FC3B692B"
        },
        @{
            Path = Join-Path $NuGetRoot "microsoft.windowsappsdk.runtime\$($Configuration.build.windowsAppSDKVersion)\microsoft.windowsappsdk.runtime.$($Configuration.build.windowsAppSDKVersion).nupkg"
            SHA256 = "F15C6C682A81A019E13BEAEE512DE9FB83FFD5A1F3E83B99209B6860A7AEBBA2"
        }
    )
    foreach ($Package in $PinnedPackages) {
        if (-not (Test-Path $Package.Path)) {
            throw "Pinned NuGet package was not found: $($Package.Path)"
        }
        $ActualPackageHash = (Get-FileHash -Algorithm SHA256 -Path $Package.Path).Hash
        if ($ActualPackageHash -ne $Package.SHA256) {
            throw "NuGet package hash mismatch for $($Package.Path): $ActualPackageHash"
        }
    }
    if (-not (Test-Path $BridgeOutput -PathType Container)) {
        throw "The C++/WinRT bridge output directory was not found."
    }
    Get-ChildItem -Path $BridgeOutput -File |
        Where-Object { $_.Extension -in @(".dll", ".pri") } |
        Copy-Item -Destination $StagingDirectory
    if (-not (Test-Path (Join-Path $StagingDirectory "OpenWidgetWindowsBridge.dll"))) {
        throw "OpenWidgetWindowsBridge.dll was not staged."
    }

    $RuntimePayload = Expand-SwiftRuntimeRedistributable `
        -TargetArchitecture $Architecture `
        -BuildConfiguration $Configuration.build `
        -Destination $StagingDirectory
    $RuntimeFiles = @($RuntimePayload.Files)
    $RequiredFoundationDLLs = @(
        "Foundation.dll",
        "FoundationEssentials.dll",
        "FoundationInternationalization.dll"
    )
    $RequiredFoundationPaths = @()
    foreach ($RequiredFoundationDLL in $RequiredFoundationDLLs) {
        $Matches = @(
            $RuntimeFiles | Where-Object { $_.Name -eq $RequiredFoundationDLL }
        )
        if ($Matches.Count -ne 1) {
            throw "The provider package is missing $RequiredFoundationDLL from the pinned toolchain."
        }
        $RequiredFoundationPaths += $Matches[0].Path.Replace("/", "\")
    }
    Assert-PEMachine `
        -Files @(
            $SwiftExecutable.FullName,
            (Join-Path $StagingDirectory "OpenWidgetWindowsBridge.dll")
        ) `
        -TargetArchitecture $Architecture
    Assert-RuntimeDependencyClosure `
        -EntryPoints @(
            $SwiftExecutable.FullName,
            (Join-Path $StagingDirectory "OpenWidgetWindowsBridge.dll")
        ) `
        -RuntimeFiles $RuntimeFiles

    Invoke-Checked swift @(
        "run", "-c", "release", "openwidget-packager",
        "generate", $StagedConfiguration,
        $StagingDirectory,
        (Join-Path $StagingDirectory "AppxManifest.xml")
    )
    Invoke-Checked makeappx @(
        "pack", "/d", $StagingDirectory, "/p", $MSIXPath, "/o"
    )
    Invoke-Checked makeappx @(
        "unpack", "/p", $MSIXPath, "/d", $InspectionDirectory, "/o"
    )
    $RequiredPackageFiles = @(
        "AppxManifest.xml",
        "OpenWidgetProvider.json",
        "Public\OpenWidgetProvider.json",
        $Configuration.provider.executable,
        $Configuration.provider.bridgeDLL
    ) + $RequiredFoundationPaths
    foreach ($RelativePath in $RequiredPackageFiles) {
        if (-not (Test-Path (Join-Path $InspectionDirectory $RelativePath) -PathType Leaf)) {
            throw "The expanded MSIX is missing '$RelativePath'."
        }
    }
    $ExpandedManifestPath = Join-Path $InspectionDirectory "AppxManifest.xml"
    [xml]$ExpandedManifest = Get-Content -Raw $ExpandedManifestPath
    $ManifestNamespaces = [Xml.XmlNamespaceManager]::new($ExpandedManifest.NameTable)
    $ManifestNamespaces.AddNamespace(
        "foundation",
        "http://schemas.microsoft.com/appx/manifest/foundation/windows10"
    )
    $RuntimeDependency = $ExpandedManifest.SelectSingleNode(
        "/foundation:Package/foundation:Dependencies/foundation:PackageDependency",
        $ManifestNamespaces
    )
    if ($null -eq $RuntimeDependency `
        -or $RuntimeDependency.GetAttribute("Name") -ne $Configuration.build.windowsAppRuntimePackageName `
        -or $RuntimeDependency.GetAttribute("Publisher") -ne $Configuration.build.windowsAppRuntimePublisher `
        -or $RuntimeDependency.GetAttribute("MinVersion") -ne $Configuration.build.windowsAppRuntimeMinVersion) {
        throw "The expanded MSIX has an unexpected Windows App Runtime dependency."
    }
    $PackageFiles = Get-ChildItem -Path $InspectionDirectory -File -Recurse |
        ForEach-Object {
            [PSCustomObject]@{
                Path = [IO.Path]::GetRelativePath(
                    $InspectionDirectory,
                    $_.FullName
                ).Replace("\", "/")
                SHA256 = (Get-FileHash -Algorithm SHA256 -Path $_.FullName).Hash
            }
        } | Sort-Object Path

    $Evidence = [PSCustomObject]@{
        SchemaVersion = 2
        Architecture = $Architecture
        SwiftTriple = $SwiftTriple
        SwiftVersion = $SwiftVersion
        SwiftSnapshot = $Configuration.build.swiftSnapshot
        SwiftToolchainIdentifier = $Configuration.build.swiftToolchainIdentifier
        WindowsAppSDKVersion = $Configuration.build.windowsAppSDKVersion
        WidgetsPackageVersion = $Configuration.build.widgetsPackageVersion
        CppWinRTVersion = $Configuration.build.cppWinRTVersion
        WixToolsetSDK = $RuntimePayload.WixToolsetSDK
        SwiftRuntimeMergeModule = $RuntimePayload.MergeModule
        WindowsAppRuntimeDependency = [PSCustomObject]@{
            Name = $Configuration.build.windowsAppRuntimePackageName
            Publisher = $Configuration.build.windowsAppRuntimePublisher
            MinVersion = $Configuration.build.windowsAppRuntimeMinVersion
        }
        VisualCToolset = $Configuration.build.visualCToolset
        WindowsSDKVersion = $Configuration.build.windowsSDKVersion
        FoundationLinkMode = $Configuration.build.foundationLinkMode
        RuntimeFiles = @(
            $RuntimeFiles | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.Name
                    Path = $_.Path
                    SHA256 = $_.SHA256
                }
            }
        )
        PackageFiles = $PackageFiles
        BridgeSHA256 = (Get-FileHash -Algorithm SHA256 `
            -Path (Join-Path $StagingDirectory "OpenWidgetWindowsBridge.dll")).Hash
        ProviderSHA256 = (Get-FileHash -Algorithm SHA256 `
            -Path (Join-Path $StagingDirectory $Configuration.provider.executable)).Hash
        MSIXSHA256 = (Get-FileHash -Algorithm SHA256 -Path $MSIXPath).Hash
    }
    $Evidence | ConvertTo-Json -Depth 8 |
        Set-Content -Path $EvidencePath -Encoding utf8NoBOM
    $Evidence | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}
