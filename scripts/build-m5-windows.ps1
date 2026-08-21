param(
    [ValidateSet("x64", "arm64")]
    [string]$Architecture = "x64",
    [Parameter(Mandatory = $true)]
    [string]$ConfigurationPath,
    [Parameter(Mandatory = $true)]
    [string]$ProviderPackageDirectory,
    [Parameter(Mandatory = $true)]
    [string]$ProviderProduct,
    [string]$AssetRoot = "",
    [switch]$GenerateFixtureAssets,
    [string]$SigningCertificatePath = "",
    [string]$SigningPasswordEnvironmentVariable = "",
    [string]$TimestampURL = "",
    [switch]$AllowUnsigned,
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "OpenWidgetWindowsArtifactTools.ps1")

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$BridgeProject = Join-Path $RepositoryRoot "Windows\Bridge\OpenWidgetWindowsBridge.vcxproj"
$ConfigurationPath = if ([IO.Path]::IsPathRooted($ConfigurationPath)) {
    [IO.Path]::GetFullPath($ConfigurationPath)
} else {
    [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $ConfigurationPath))
}
$ProviderPackageDirectory = if ([IO.Path]::IsPathRooted($ProviderPackageDirectory)) {
    [IO.Path]::GetFullPath($ProviderPackageDirectory)
} else {
    [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $ProviderPackageDirectory))
}
if (-not [string]::IsNullOrWhiteSpace($AssetRoot)) {
    $AssetRoot = if ([IO.Path]::IsPathRooted($AssetRoot)) {
        [IO.Path]::GetFullPath($AssetRoot)
    } else {
        [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $AssetRoot))
    }
}
if (-not (Test-Path $ConfigurationPath -PathType Leaf)) {
    throw "ConfigurationPath must identify an existing provider configuration."
}
if (-not (Test-Path $ProviderPackageDirectory -PathType Container)) {
    throw "ProviderPackageDirectory must identify an existing Swift package."
}
if (-not $ProviderProduct) {
    throw "ProviderProduct must be nonempty."
}
$HasAssetRoot = -not [string]::IsNullOrWhiteSpace($AssetRoot)
if ([bool]$GenerateFixtureAssets -eq $HasAssetRoot) {
    throw "Select exactly one asset source: AssetRoot or GenerateFixtureAssets."
}
if ($SigningCertificatePath) {
    $SigningCertificatePath = if ([IO.Path]::IsPathRooted($SigningCertificatePath)) {
        [IO.Path]::GetFullPath($SigningCertificatePath)
    } else {
        [IO.Path]::GetFullPath(
            (Join-Path $RepositoryRoot $SigningCertificatePath)
        )
    }
    if ($AllowUnsigned) {
        throw "AllowUnsigned cannot be combined with signing inputs."
    }
    if (-not (Test-Path $SigningCertificatePath -PathType Leaf)) {
        throw "SigningCertificatePath must identify an existing PFX file."
    }
    if (-not $SigningPasswordEnvironmentVariable -or -not $TimestampURL) {
        throw "Signed packages require a password environment variable and TimestampURL."
    }
    if ($SigningPasswordEnvironmentVariable -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        throw "SigningPasswordEnvironmentVariable is not a valid environment variable name."
    }
    $TimestampURI = [Uri]$TimestampURL
    if (-not $TimestampURI.IsAbsoluteUri -or $TimestampURI.Scheme -ne "https") {
        throw "TimestampURL must be an absolute HTTPS URL."
    }
} elseif (-not $AllowUnsigned) {
    throw "Provide signing inputs or explicitly select AllowUnsigned for a non-distributable fixture."
} elseif ($SigningPasswordEnvironmentVariable -or $TimestampURL) {
    throw "SigningPasswordEnvironmentVariable and TimestampURL require SigningCertificatePath."
}
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
$SwiftScratchDirectory = Join-Path $OutputDirectory "swift-build"
$BridgeOutput = Join-Path $OutputDirectory "bridge"
$BridgeIntermediate = Join-Path $OutputDirectory "bridge-obj"
$WixToolDirectory = Join-Path $OutputDirectory "wixtoolset"
$WixPackageContent = Join-Path $WixToolDirectory "package"
$SwiftRuntimeImage = Join-Path $OutputDirectory "swift-runtime-image"
$SwiftRuntimeIntermediate = Join-Path $OutputDirectory "swift-runtime-obj"
$InspectionDirectory = Join-Path $OutputDirectory "inspection"
$RuntimeDependencyDirectory = Join-Path $OutputDirectory "runtime-dependencies"
$EvidencePath = Join-Path $OutputDirectory "windows-provider-build-evidence.json"

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

function Copy-ConfiguredAssets {
    param(
        [object]$Configuration,
        [string]$SourceRoot,
        [string]$DestinationRoot
    )
    $SourceRootPath = [IO.Path]::GetFullPath($SourceRoot)
    $SourceRootPrefix = $SourceRootPath.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    $AssetPaths = @(
        $Configuration.provider.square44Logo
        $Configuration.provider.square150Logo
        $Configuration.provider.storeLogo
        $Configuration.definitions | ForEach-Object {
            $_.icon
            $_.screenshot
        }
        $Configuration.resources | ForEach-Object { $_.path }
    ) | Sort-Object -Unique
    foreach ($RelativePath in $AssetPaths) {
        $PlatformPath = $RelativePath.Replace(
            [char]'/',
            [IO.Path]::DirectorySeparatorChar
        )
        $SourcePath = [IO.Path]::GetFullPath((Join-Path $SourceRootPath $PlatformPath))
        if (-not $SourcePath.StartsWith(
            $SourceRootPrefix,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Configured asset '$RelativePath' escapes AssetRoot."
        }
        if (-not (Test-Path $SourcePath -PathType Leaf)) {
            throw "Configured asset '$RelativePath' was not found under AssetRoot."
        }
        $DestinationPath = Join-Path $DestinationRoot $PlatformPath
        $DestinationDirectory = Split-Path -Parent $DestinationPath
        New-Item -ItemType Directory -Path $DestinationDirectory -Force |
            Out-Null
        Copy-Item -Path $SourcePath -Destination $DestinationPath
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

function Get-PEMachine {
    param([string]$File)
    $Headers = (& dumpbin /nologo /headers $File | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect the PE machine for '$File'."
    }
    if ($Headers -match '(?im)^\s*8664 machine \(x64\)') {
        return "x64"
    }
    if ($Headers -match '(?im)^\s*AA64 machine \(ARM64\)') {
        return "arm64"
    }
    if ($Headers -match '(?im)^\s*14C machine \(x86\)') {
        return "x86"
    }
    throw "'$File' has an unsupported PE machine."
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
            throw "The Swift runtime merge module contains duplicate '$($RuntimeFile.Name)' files."
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

function Export-ZipEntry {
    param(
        [IO.Compression.ZipArchive]$Archive,
        [string]$EntryPath,
        [string]$DestinationPath
    )
    $Entry = $Archive.GetEntry($EntryPath)
    if ($null -eq $Entry) {
        throw "The archive is missing '$EntryPath'."
    }
    $DestinationDirectory = Split-Path -Parent $DestinationPath
    New-Item -ItemType Directory -Path $DestinationDirectory -Force |
        Out-Null
    [IO.Compression.ZipFileExtensions]::ExtractToFile(
        $Entry,
        $DestinationPath,
        $true
    )
}

function Export-WindowsAppRuntimeDependencies {
    param(
        [string]$RuntimeNuGetPackage,
        [string]$TargetArchitecture,
        [object]$BuildConfiguration,
        [string]$Destination
    )
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $Archive = [IO.Compression.ZipFile]::OpenRead($RuntimeNuGetPackage)
    try {
        $RuntimeFolder = "tools/MSIX/win10-$TargetArchitecture"
        $PackageNames = @(
            "Microsoft.WindowsAppRuntime.2.msix",
            "Microsoft.WindowsAppRuntime.Main.2.msix",
            "Microsoft.WindowsAppRuntime.Singleton.2.msix",
            "Microsoft.WindowsAppRuntime.DDLM.2.msix"
        )
        foreach ($PackageName in $PackageNames) {
            Export-ZipEntry `
                -Archive $Archive `
                -EntryPath "$RuntimeFolder/$PackageName" `
                -DestinationPath (Join-Path $Destination $PackageName)
        }
        Export-ZipEntry `
            -Archive $Archive `
            -EntryPath "license.txt" `
            -DestinationPath (Join-Path $Destination "WindowsAppSDK-license.txt")
        Export-ZipEntry `
            -Archive $Archive `
            -EntryPath "NOTICE.txt" `
            -DestinationPath (Join-Path $Destination "WindowsAppSDK-NOTICE.txt")
    }
    finally {
        $Archive.Dispose()
    }

    $RuntimePackages = @(
        $PackageNames | ForEach-Object {
            $PackagePath = Join-Path $Destination $_
            Invoke-Checked signtool @("verify", "/pa", "/all", $PackagePath)
            $Identity = Get-OpenWidgetMSIXMetadata -PackagePath $PackagePath
            if ($Identity.Architecture -ne $TargetArchitecture) {
                throw "The Windows App Runtime package '$($_)' has architecture '$($Identity.Architecture)' instead of '$TargetArchitecture'."
            }
            if ($Identity.Publisher -ne $BuildConfiguration.windowsAppRuntimePublisher) {
                throw "The Windows App Runtime package '$($_)' has an unexpected publisher."
            }
            if ($_ -eq "Microsoft.WindowsAppRuntime.2.msix" `
                -and ($Identity.Name -ne $BuildConfiguration.windowsAppRuntimePackageName `
                    -or [Version]$Identity.Version -lt [Version]$BuildConfiguration.windowsAppRuntimeMinVersion)) {
                throw "The Windows App Runtime framework package does not satisfy the manifest dependency."
            }
            [PSCustomObject]@{
                FileName = $_
                IdentityName = $Identity.Name
                Publisher = $Identity.Publisher
                Version = $Identity.Version
                Architecture = $Identity.Architecture
                SHA256 = (Get-FileHash -Algorithm SHA256 -Path $PackagePath).Hash
            }
        }
    )
    return $RuntimePackages
}

function Export-VisualCppRedistributable {
    param(
        [string]$TargetArchitecture,
        [string]$Destination
    )
    if (-not $env:VCToolsRedistDir `
        -or -not (Test-Path $env:VCToolsRedistDir -PathType Container)) {
        throw "VCToolsRedistDir must identify the Visual C++ redistributable directory."
    }
    $FileName = "vc_redist.$TargetArchitecture.exe"
    $Candidates = @(
        Get-ChildItem -Path $env:VCToolsRedistDir `
            -Filter $FileName -File -Recurse
    )
    if ($Candidates.Count -ne 1) {
        throw "Expected exactly one '$FileName' under VCToolsRedistDir; found $($Candidates.Count)."
    }
    $DestinationPath = Join-Path $Destination $FileName
    Copy-Item -Path $Candidates[0].FullName -Destination $DestinationPath
    Invoke-Checked signtool @("verify", "/pa", "/all", $DestinationPath)
    $Version = [Diagnostics.FileVersionInfo]::GetVersionInfo($DestinationPath)
    return [PSCustomObject]@{
        FileName = $FileName
        FileVersion = $Version.FileVersion
        ProductVersion = $Version.ProductVersion
        PayloadArchitecture = $TargetArchitecture
        BootstrapperPEMachine = Get-PEMachine -File $DestinationPath
        SHA256 = (Get-FileHash -Algorithm SHA256 -Path $DestinationPath).Hash
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

    New-Item -ItemType Directory -Path $WixToolDirectory -Force | Out-Null
    $WixPackagePath = Join-Path $WixToolDirectory "wixtoolset.sdk.zip"
    $WixPackageURI = "https://api.nuget.org/v3-flatcontainer/wixtoolset.sdk/$($BuildConfiguration.wixToolsetSDKVersion)/wixtoolset.sdk.$($BuildConfiguration.wixToolsetSDKVersion).nupkg"
    Invoke-WebRequest -Uri $WixPackageURI -OutFile $WixPackagePath
    $WixPackageHash = (Get-FileHash -Algorithm SHA256 -Path $WixPackagePath).Hash
    if ($WixPackageHash -ne "917009BEF10F430EE72C4401F70FFCB36562A53F41EA027B8DCACBA5E9886A6F") {
        throw "WiX Toolset SDK package hash mismatch: $WixPackageHash"
    }
    Expand-Archive -Path $WixPackagePath -DestinationPath $WixPackageContent
    $WixExecutable = Join-Path $WixPackageContent "tools\net472\x64\wix.exe"
    if (-not (Test-Path $WixExecutable -PathType Leaf)) {
        throw "The pinned WiX Toolset SDK does not contain its x64 command-line tool."
    }
    New-Item -ItemType Directory -Path $SwiftRuntimeIntermediate -Force | Out-Null
    $DecompiledModule = Join-Path $SwiftRuntimeIntermediate "SwiftRuntime.wxs"
    Invoke-Checked $WixExecutable @(
        "msi", "decompile", $MergeModule.FullName,
        "-type", "msm",
        "-intermediateFolder", $SwiftRuntimeIntermediate,
        "-o", $DecompiledModule,
        "-x", $SwiftRuntimeImage
    )

    [xml]$ModuleDocument = Get-Content -Raw $DecompiledModule
    $ModuleNamespaces = [Xml.XmlNamespaceManager]::new($ModuleDocument.NameTable)
    $ModuleNamespaces.AddNamespace("wix", "http://wixtoolset.org/schemas/v4/wxs")
    $RuntimeFiles = @(
        $ModuleDocument.SelectNodes("//wix:File", $ModuleNamespaces) |
            ForEach-Object {
                $Name = $_.GetAttribute("Name")
                if ($Name.EndsWith(".dll", [StringComparison]::OrdinalIgnoreCase)) {
                    if ([String]::IsNullOrWhiteSpace($Name) `
                        -or [IO.Path]::GetFileName($Name) -ne $Name) {
                        throw "The Swift runtime merge module has an invalid package file name '$Name'."
                    }
                    $Source = $_.GetAttribute("Source")
                    if ($Source -notmatch '^SourceDir[\\/]') {
                        throw "The Swift runtime merge module has an unexpected extracted source '$Source'."
                    }
                    $RuntimeImageRoot = [IO.Path]::GetFullPath($SwiftRuntimeImage) + `
                        [IO.Path]::DirectorySeparatorChar
                    $ExtractedPath = [IO.Path]::GetFullPath((Join-Path `
                        $SwiftRuntimeImage `
                        ($Source -replace '^SourceDir[\\/]', '')
                    ))
                    if (-not $ExtractedPath.StartsWith(
                        $RuntimeImageRoot,
                        [StringComparison]::OrdinalIgnoreCase
                    )) {
                        throw "The Swift runtime merge module source escapes its extraction root: '$Source'."
                    }
                    if (-not (Test-Path $ExtractedPath -PathType Leaf)) {
                        throw "The Swift runtime merge module did not extract '$Name'."
                    }
                    $DestinationPath = Join-Path $Destination $Name
                    if (Test-Path $DestinationPath) {
                        throw "The Swift runtime merge module contains duplicate package file '$Name'."
                    }
                    Copy-Item -Path $ExtractedPath -Destination $DestinationPath
                    [PSCustomObject]@{
                        Name = $Name
                        Source = $DestinationPath
                        Path = $Name
                        SHA256 = (Get-FileHash -Algorithm SHA256 -Path $DestinationPath).Hash
                    }
                }
            } | Sort-Object Path
    )
    if (-not $RuntimeFiles) {
        throw "The Swift runtime merge module contains no DLLs."
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
    $Configuration = Get-Content -Raw $ConfigurationPath | ConvertFrom-Json
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
    if (-not $env:OPENWIDGET_SWIFT_INSTALLER_SHA256 `
        -or $env:OPENWIDGET_SWIFT_INSTALLER_SHA256 -notmatch '^[A-F0-9]{64}$') {
        throw "OPENWIDGET_SWIFT_INSTALLER_SHA256 must identify the verified Swift installer."
    }
    $SwiftVersion = (& swift --version | Out-String).Trim()
    if (-not $SwiftVersion.Contains("Swift version 6.4-dev")) {
        throw "The configured Swift 6.4 development snapshot is not active: $SwiftVersion"
    }
    $HostTargetInfo = & swift -print-target-info | ConvertFrom-Json
    if ($HostTargetInfo.target.unversionedTriple -ne $SwiftTriple) {
        throw "M5 requires a native Swift host matching $SwiftTriple; found $($HostTargetInfo.target.unversionedTriple)."
    }
    $TargetInfo = & swift -print-target-info -target $SwiftTriple | ConvertFrom-Json
    if ($TargetInfo.target.unversionedTriple -ne $SwiftTriple) {
        throw "Swift target mismatch: $($TargetInfo.target.unversionedTriple)"
    }
    Invoke-Checked swift @(
        "run", "-c", "release", "openwidget-packager",
        "validate-metadata", $ConfigurationPath
    )
    $MSIXPath = Join-Path $OutputDirectory `
        "$($Configuration.provider.packageName)-$Architecture.msix"
    New-Item -ItemType Directory -Path $StagingDirectory -Force | Out-Null
    if ($GenerateFixtureAssets) {
        Write-FixtureAssets -Root $StagingDirectory
    } else {
        Copy-ConfiguredAssets `
            -Configuration $Configuration `
            -SourceRoot $AssetRoot `
            -DestinationRoot $StagingDirectory
    }

    $StagedConfiguration = Join-Path $StagingDirectory "OpenWidgetProvider.json"
    $Configuration | ConvertTo-Json -Depth 12 |
        Set-Content -Path $StagedConfiguration -Encoding utf8NoBOM
    $PublicDirectory = Join-Path $StagingDirectory "Public"
    New-Item -ItemType Directory -Path $PublicDirectory -Force | Out-Null
    Copy-Item -Path $StagedConfiguration -Destination $PublicDirectory

    Invoke-Checked swift @(
        "build", "--package-path", $ProviderPackageDirectory,
        "--scratch-path", $SwiftScratchDirectory,
        "-c", "release", "--triple", $SwiftTriple,
        "--product", $ProviderProduct
    )
    $ProviderExecutableName = [IO.Path]::GetFileName(
        $Configuration.provider.executable
    )
    $SwiftExecutables = @(
        Get-ChildItem -Path $SwiftScratchDirectory `
            -Filter $ProviderExecutableName -File -Recurse
    )
    if ($SwiftExecutables.Count -ne 1) {
        throw "Expected one '$ProviderExecutableName' for $SwiftTriple in the isolated SwiftPM build root; found $($SwiftExecutables.Count)."
    }
    $SwiftExecutable = $SwiftExecutables[0].FullName
    $StagedProviderExecutable = Join-Path $StagingDirectory `
        $Configuration.provider.executable.Replace(
            [char]'/',
            [IO.Path]::DirectorySeparatorChar
        )
    New-Item -ItemType Directory `
        -Path (Split-Path -Parent $StagedProviderExecutable) -Force |
        Out-Null
    Copy-Item $SwiftExecutable $StagedProviderExecutable
    Get-ChildItem -Path $SwiftExecutables[0].DirectoryName `
        -Filter "*.resources" -Directory |
        Copy-Item -Destination $StagingDirectory -Recurse

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
    $WindowsAppRuntimePackages = Export-WindowsAppRuntimeDependencies `
        -RuntimeNuGetPackage $PinnedPackages[3].Path `
        -TargetArchitecture $Architecture `
        -BuildConfiguration $Configuration.build `
        -Destination $RuntimeDependencyDirectory
    $VisualCppRedistributable = Export-VisualCppRedistributable `
        -TargetArchitecture $Architecture `
        -Destination $RuntimeDependencyDirectory
    if (-not (Test-Path $BridgeOutput -PathType Container)) {
        throw "The C++/WinRT bridge output directory was not found."
    }
    $BuiltBridge = Join-Path $BridgeOutput "OpenWidgetWindowsBridge.dll"
    if (-not (Test-Path $BuiltBridge -PathType Leaf)) {
        throw "OpenWidgetWindowsBridge.dll was not staged."
    }
    $StagedBridge = Join-Path $StagingDirectory `
        $Configuration.provider.bridgeDLL.Replace(
            [char]'/',
            [IO.Path]::DirectorySeparatorChar
        )
    New-Item -ItemType Directory -Path (Split-Path -Parent $StagedBridge) -Force |
        Out-Null
    Copy-Item -Path $BuiltBridge -Destination $StagedBridge
    Get-ChildItem -Path $BridgeOutput -Filter "*.pri" -File |
        Copy-Item -Destination $StagingDirectory

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
            $SwiftExecutable,
            $StagedBridge
        ) `
        -TargetArchitecture $Architecture
    Assert-RuntimeDependencyClosure `
        -EntryPoints @(
            $SwiftExecutable,
            $StagedBridge
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
    if ($SigningCertificatePath) {
        $SigningPassword = [Environment]::GetEnvironmentVariable(
            $SigningPasswordEnvironmentVariable
        )
        if (-not $SigningPassword) {
            throw "The configured signing password environment variable is empty."
        }
        try {
            Invoke-Checked signtool @(
                "sign", "/fd", "SHA256",
                "/f", $SigningCertificatePath,
                "/p", $SigningPassword,
                "/tr", $TimestampURL,
                "/td", "SHA256",
                $MSIXPath
            )
        }
        finally {
            $SigningPassword = $null
        }
        Invoke-Checked signtool @("verify", "/pa", "/all", $MSIXPath)
    }
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
        SchemaVersion = 5
        Architecture = $Architecture
        SwiftTriple = $SwiftTriple
        ProviderProduct = $ProviderProduct
        Signed = [bool]$SigningCertificatePath
        SwiftVersion = $SwiftVersion
        SwiftSnapshot = $Configuration.build.swiftSnapshot
        SwiftToolchainIdentifier = $Configuration.build.swiftToolchainIdentifier
        SwiftInstallerSHA256 = $env:OPENWIDGET_SWIFT_INSTALLER_SHA256
        RunnerImage = $env:ImageOS
        RunnerImageVersion = $env:ImageVersion
        GitHubRepository = $env:GITHUB_REPOSITORY
        GitHubRunID = $env:GITHUB_RUN_ID
        GitHubHeadSHA = $env:GITHUB_SHA
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
        WindowsAppRuntimePackages = $WindowsAppRuntimePackages
        VisualCppRedistributable = $VisualCppRedistributable
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
            -Path $StagedBridge).Hash
        ProviderSHA256 = (Get-FileHash -Algorithm SHA256 `
            -Path $StagedProviderExecutable).Hash
        MSIXSHA256 = (Get-FileHash -Algorithm SHA256 -Path $MSIXPath).Hash
    }
    $Evidence | ConvertTo-Json -Depth 8 |
        Set-Content -Path $EvidencePath -Encoding utf8NoBOM
    $Evidence | ConvertTo-Json -Depth 8
}
finally {
    Pop-Location
}
