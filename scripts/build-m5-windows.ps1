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

function Get-ToolchainRuntimeFiles {
    param(
        [string]$Executable,
        [object]$TargetInfo,
        [string]$Destination
    )
    $SearchRoots = @(
        $TargetInfo.paths.runtimeLibraryPaths
        $TargetInfo.paths.runtimeLibraryImportPaths
        $TargetInfo.paths.runtimeResourcePath
        $env:SDKROOT
    ) | Where-Object { $_ -and (Test-Path $_) } | Sort-Object -Unique
    $Pending = [Collections.Generic.Queue[string]]::new()
    $Pending.Enqueue($Executable)
    $Resolved = @{}
    while ($Pending.Count -gt 0) {
        $Binary = $Pending.Dequeue()
        $Dependents = (& dumpbin /nologo /dependents $Binary | Out-String) -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^[A-Za-z0-9_.+-]+\.dll$' } |
            Sort-Object -Unique
        foreach ($Dependent in $Dependents) {
            if ($Resolved.ContainsKey($Dependent)) { continue }
            $Matches = @(
                foreach ($Root in $SearchRoots) {
                    Get-ChildItem -Path $Root -Filter $Dependent -File -Recurse -ErrorAction SilentlyContinue
                }
            ) | Sort-Object FullName -Unique
            if (-not $Matches) {
                if ($Dependent -match '^(Foundation|swift|dispatch|BlocksRuntime|icu)') {
                    throw "Toolchain runtime dependency '$Dependent' was not found."
                }
                continue
            }
            $Hashes = @($Matches | ForEach-Object {
                (Get-FileHash -Algorithm SHA256 -Path $_.FullName).Hash
            } | Sort-Object -Unique)
            if ($Hashes.Count -ne 1) {
                throw "Mixed toolchain runtime versions were found for '$Dependent'."
            }
            $Source = $Matches[0].FullName
            $Target = Join-Path $Destination $Dependent
            if (Test-Path $Target) {
                $ExistingHash = (Get-FileHash -Algorithm SHA256 -Path $Target).Hash
                if ($ExistingHash -ne $Hashes[0]) {
                    throw "Staging already contains a different '$Dependent'."
                }
            } else {
                Copy-Item -Path $Source -Destination $Target
            }
            $Resolved[$Dependent] = [PSCustomObject]@{
                Name = $Dependent
                Source = $Source
                SHA256 = $Hashes[0]
            }
            $Pending.Enqueue($Source)
        }
    }
    return @($Resolved.Values | Sort-Object Name)
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
        "Microsoft.WindowsAppSDK.Widgets/$($Configuration.build.widgetsPackageVersion)"
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

    $RuntimeFiles = Get-ToolchainRuntimeFiles `
        -Executable $SwiftExecutable.FullName `
        -TargetInfo $TargetInfo `
        -Destination $StagingDirectory
    $RequiredFoundationDLLs = @(
        "Foundation.dll",
        "FoundationEssentials.dll",
        "FoundationInternationalization.dll"
    )
    foreach ($RequiredFoundationDLL in $RequiredFoundationDLLs) {
        if (-not ($RuntimeFiles | Where-Object { $_.Name -eq $RequiredFoundationDLL })) {
            throw "The provider package is missing $RequiredFoundationDLL from the pinned toolchain."
        }
    }

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
    ) + $RequiredFoundationDLLs
    foreach ($RelativePath in $RequiredPackageFiles) {
        if (-not (Test-Path (Join-Path $InspectionDirectory $RelativePath) -PathType Leaf)) {
            throw "The expanded MSIX is missing '$RelativePath'."
        }
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
        SchemaVersion = 1
        Architecture = $Architecture
        SwiftTriple = $SwiftTriple
        SwiftVersion = $SwiftVersion
        SwiftSnapshot = $Configuration.build.swiftSnapshot
        SwiftToolchainIdentifier = $Configuration.build.swiftToolchainIdentifier
        WindowsAppSDKVersion = $Configuration.build.windowsAppSDKVersion
        WidgetsPackageVersion = $Configuration.build.widgetsPackageVersion
        VisualCToolset = $Configuration.build.visualCToolset
        WindowsSDKVersion = $Configuration.build.windowsSDKVersion
        FoundationLinkMode = $Configuration.build.foundationLinkMode
        RuntimeFiles = $RuntimeFiles
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
