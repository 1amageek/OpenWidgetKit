param(
    [ValidateSet("x64", "arm64")]
    [string]$Architecture = "x64",
    [Parameter(Mandatory = $true)]
    [string]$ConfigurationPath,
    [Parameter(Mandatory = $true)]
    [string]$M5BuildOutputDirectory,
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "OpenWidgetWindowsArtifactTools.ps1")

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw "M6 artifact preparation must run on Windows."
}

function Resolve-ArtifactPath {
    param(
        [string]$Path,
        [string]$BasePath
    )
    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Invoke-Checked {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 120
    )
    $StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = $FilePath
    $StartInfo.UseShellExecute = $false
    foreach ($Argument in $Arguments) {
        $StartInfo.ArgumentList.Add($Argument)
    }

    $Process = [Diagnostics.Process]::new()
    $Process.StartInfo = $StartInfo
    if (-not $Process.Start()) {
        $Process.Dispose()
        throw "Failed to start $FilePath."
    }
    try {
        if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
            $Process.Kill($true)
            $Process.WaitForExit()
            throw "$FilePath exceeded the $TimeoutSeconds-second timeout."
        }
        if ($Process.ExitCode -ne 0) {
            throw "$FilePath failed with exit code $($Process.ExitCode)."
        }
    }
    finally {
        $Process.Dispose()
    }
}

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$ConfigurationPath = Resolve-ArtifactPath `
    -Path $ConfigurationPath `
    -BasePath $RepositoryRoot
$M5BuildOutputDirectory = Resolve-ArtifactPath `
    -Path $M5BuildOutputDirectory `
    -BasePath $RepositoryRoot
$OutputDirectory = Resolve-ArtifactPath `
    -Path $OutputDirectory `
    -BasePath $RepositoryRoot

foreach ($RequiredPath in @($ConfigurationPath, $M5BuildOutputDirectory)) {
    if (-not (Test-Path $RequiredPath)) {
        throw "Required input not found: $RequiredPath"
    }
}
$M5BuildOutputDirectory = [IO.Path]::GetFullPath($M5BuildOutputDirectory)
$M5Prefix = $M5BuildOutputDirectory.TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
) + [IO.Path]::DirectorySeparatorChar
if ($OutputDirectory -eq $M5BuildOutputDirectory `
    -or $OutputDirectory.StartsWith($M5Prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDirectory must not be the M5 build directory or one of its descendants."
}
if (Test-Path $OutputDirectory) {
    if (-not (Test-Path $OutputDirectory -PathType Container)) {
        throw "OutputDirectory exists and is not a directory."
    }
    if (Get-ChildItem -Path $OutputDirectory -Force | Select-Object -First 1) {
        throw "OutputDirectory must not exist or must be empty."
    }
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$Configuration = Get-Content -Raw $ConfigurationPath | ConvertFrom-Json
$M5EvidenceSource = Join-Path `
    $M5BuildOutputDirectory `
    "windows-provider-build-evidence.json"
if (-not (Test-Path $M5EvidenceSource -PathType Leaf)) {
    throw "M5 build evidence was not found."
}
$M5Evidence = Get-Content -Raw $M5EvidenceSource | ConvertFrom-Json
if ($M5Evidence.SchemaVersion -ne 5) {
    throw "M6 preparation requires M5 build evidence schema 5."
}
if ($M5Evidence.Architecture -ne $Architecture) {
    throw "M5 architecture '$($M5Evidence.Architecture)' does not match '$Architecture'."
}
if ($M5Evidence.Signed) {
    throw "M6 preparation requires the preserved unsigned M5 package as its source."
}

$UnsignedPackageName = "$($Configuration.provider.packageName)-$Architecture.msix"
$UnsignedPackagePath = Join-Path $M5BuildOutputDirectory $UnsignedPackageName
Assert-OpenWidgetFileHash `
    -Path $UnsignedPackagePath `
    -ExpectedSHA256 $M5Evidence.MSIXSHA256 | Out-Null
$UnsignedMetadata = Get-OpenWidgetMSIXMetadata -PackagePath $UnsignedPackagePath
if ($UnsignedMetadata.Name -ne $Configuration.provider.packageName `
    -or $UnsignedMetadata.Publisher -ne $Configuration.provider.publisher `
    -or $UnsignedMetadata.Architecture -ne $Architecture `
    -or [Guid]$UnsignedMetadata.ClassID -ne [Guid]$Configuration.provider.classID) {
    throw "The unsigned M5 package metadata does not match the provider configuration."
}
if ($null -eq $UnsignedMetadata.RuntimeDependency `
    -or $UnsignedMetadata.RuntimeDependency.Name -ne $Configuration.build.windowsAppRuntimePackageName `
    -or $UnsignedMetadata.RuntimeDependency.Publisher -ne $Configuration.build.windowsAppRuntimePublisher `
    -or $UnsignedMetadata.RuntimeDependency.MinVersion -ne $Configuration.build.windowsAppRuntimeMinVersion) {
    throw "The unsigned M5 package has an unexpected Windows App Runtime dependency."
}

$RuntimeDependencySource = Join-Path `
    $M5BuildOutputDirectory `
    "runtime-dependencies"
$RuntimeDependencyDestination = Join-Path `
    $OutputDirectory `
    "runtime-dependencies"
New-Item -ItemType Directory -Path $RuntimeDependencyDestination -Force |
    Out-Null
$RuntimePackageEvidence = @(
    $M5Evidence.WindowsAppRuntimePackages | ForEach-Object {
        $SourcePath = Join-Path $RuntimeDependencySource $_.FileName
        Assert-OpenWidgetFileHash `
            -Path $SourcePath `
            -ExpectedSHA256 $_.SHA256 | Out-Null
        $Metadata = Get-OpenWidgetMSIXMetadata -PackagePath $SourcePath
        if ($Metadata.Name -ne $_.IdentityName `
            -or $Metadata.Publisher -ne $_.Publisher `
            -or $Metadata.Version -ne $_.Version `
            -or $Metadata.Architecture -ne $Architecture) {
            throw "Runtime package '$($_.FileName)' does not match its M5 evidence."
        }
        Copy-Item -Path $SourcePath -Destination $RuntimeDependencyDestination
        [PSCustomObject]@{
            FileName = $_.FileName
            IdentityName = $_.IdentityName
            Publisher = $_.Publisher
            Version = $_.Version
            Architecture = $_.Architecture
            SHA256 = $_.SHA256
        }
    }
)
if ($RuntimePackageEvidence.Count -ne 4) {
    throw "The M6 bundle requires all four Windows App Runtime packages."
}

$VisualCppSource = Join-Path `
    $RuntimeDependencySource `
    $M5Evidence.VisualCppRedistributable.FileName
Assert-OpenWidgetFileHash `
    -Path $VisualCppSource `
    -ExpectedSHA256 $M5Evidence.VisualCppRedistributable.SHA256 | Out-Null
Copy-Item -Path $VisualCppSource -Destination $RuntimeDependencyDestination
foreach ($NoticeName in @("WindowsAppSDK-license.txt", "WindowsAppSDK-NOTICE.txt")) {
    $NoticeSource = Join-Path $RuntimeDependencySource $NoticeName
    if (-not (Test-Path $NoticeSource -PathType Leaf)) {
        throw "Windows App SDK redistribution notice not found: $NoticeName"
    }
    Copy-Item -Path $NoticeSource -Destination $RuntimeDependencyDestination
}

$M5EvidenceDestination = Join-Path `
    $OutputDirectory `
    "m5-windows-build-evidence.json"
Copy-Item -Path $M5EvidenceSource -Destination $M5EvidenceDestination
$RunbookSource = Join-Path $RepositoryRoot "M6_WINDOWS_RUNBOOK.md"
if (-not (Test-Path $RunbookSource -PathType Leaf)) {
    throw "M6_WINDOWS_RUNBOOK.md must exist before preparing the resume bundle."
}
Copy-Item -Path $RunbookSource -Destination $OutputDirectory
$HostScriptNames = @(
    "start-m6-windows.ps1",
    "OpenWidgetWindowsArtifactTools.ps1"
)
foreach ($HostScriptName in $HostScriptNames) {
    $HostScriptSource = Join-Path $PSScriptRoot $HostScriptName
    if (-not (Test-Path $HostScriptSource -PathType Leaf)) {
        throw "Required M6 host script not found: $HostScriptName"
    }
    Copy-Item -Path $HostScriptSource -Destination $OutputDirectory
}

$SignedPackageName = "$($Configuration.provider.packageName)-$Architecture-development.msix"
$SignedPackagePath = Join-Path $OutputDirectory $SignedPackageName
$CertificatePath = Join-Path `
    $OutputDirectory `
    "$($Configuration.provider.packageName)-development.cer"
$Certificate = $null
try {
    $Certificate = New-SelfSignedCertificate `
        -Type Custom `
        -Subject $Configuration.provider.publisher `
        -FriendlyName "OpenWidgetKit M6 development signing" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -HashAlgorithm SHA256 `
        -KeyUsage DigitalSignature `
        -KeyExportPolicy NonExportable `
        -NotBefore (Get-Date).AddMinutes(-5) `
        -NotAfter (Get-Date).AddDays(180) `
        -TextExtension @(
            "2.5.29.37={text}1.3.6.1.5.5.7.3.3",
            "2.5.29.19={text}"
        )
    if ($Certificate.Subject -ne $Configuration.provider.publisher) {
        throw "The development certificate subject does not match the manifest publisher."
    }
    Export-Certificate `
        -Cert $Certificate `
        -FilePath $CertificatePath `
        -Type CERT | Out-Null
    $PublicCertificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $CertificatePath
    )
    if ($PublicCertificate.HasPrivateKey) {
        throw "The exported development certificate must not contain a private key."
    }

    Copy-Item -Path $UnsignedPackagePath -Destination $SignedPackagePath
    Invoke-Checked signtool @(
        "sign", "/fd", "SHA256",
        "/sha1", $Certificate.Thumbprint,
        $SignedPackagePath
    )

    $Signature = Get-AuthenticodeSignature -FilePath $SignedPackagePath
    if ($null -eq $Signature.SignerCertificate `
        -or $Signature.SignerCertificate.Thumbprint -ne $Certificate.Thumbprint) {
        throw "The development MSIX signer does not match the exported certificate."
    }
    if ($Signature.Status -eq [Management.Automation.SignatureStatus]::HashMismatch `
        -or $Signature.Status -eq [Management.Automation.SignatureStatus]::NotSigned) {
        throw "The development MSIX failed signature integrity validation."
    }

    $Evidence = [PSCustomObject]@{
        SchemaVersion = 1
        Purpose = "OpenWidgetKit M6 real-host continuation bundle"
        DevelopmentOnly = $true
        Architecture = $Architecture
        GitHubRepository = $env:GITHUB_REPOSITORY
        GitHubRunID = $env:GITHUB_RUN_ID
        GitHubHeadSHA = $env:GITHUB_SHA
        SourceM5EvidenceSHA256 = (Get-FileHash `
            -Algorithm SHA256 `
            -Path $M5EvidenceDestination).Hash
        UnsignedSource = [PSCustomObject]@{
            FileName = $UnsignedPackageName
            SHA256 = $M5Evidence.MSIXSHA256
        }
        SignedPackage = [PSCustomObject]@{
            FileName = $SignedPackageName
            SHA256 = (Get-FileHash `
                -Algorithm SHA256 `
                -Path $SignedPackagePath).Hash
            IdentityName = $UnsignedMetadata.Name
            Publisher = $UnsignedMetadata.Publisher
            Version = $UnsignedMetadata.Version
            Architecture = $UnsignedMetadata.Architecture
            ApplicationID = $UnsignedMetadata.ApplicationID
            Executable = $UnsignedMetadata.Executable
            ClassID = $UnsignedMetadata.ClassID
        }
        SigningCertificate = [PSCustomObject]@{
            FileName = [IO.Path]::GetFileName($CertificatePath)
            SHA256 = (Get-FileHash `
                -Algorithm SHA256 `
                -Path $CertificatePath).Hash
            Thumbprint = $Certificate.Thumbprint
            Subject = $Certificate.Subject
            NotBefore = $Certificate.NotBefore.ToUniversalTime().ToString("o")
            NotAfter = $Certificate.NotAfter.ToUniversalTime().ToString("o")
            EnhancedKeyUsage = "1.3.6.1.5.5.7.3.3"
            PrivateKeyExported = $false
            CIValidation = "integrityAndSignerMatch"
            CIAuthenticodeStatus = $Signature.Status.ToString()
        }
        WindowsAppRuntimePackages = $RuntimePackageEvidence
        VisualCppRedistributable = [PSCustomObject]@{
            FileName = $M5Evidence.VisualCppRedistributable.FileName
            FileVersion = $M5Evidence.VisualCppRedistributable.FileVersion
            ProductVersion = $M5Evidence.VisualCppRedistributable.ProductVersion
            PayloadArchitecture = $M5Evidence.VisualCppRedistributable.PayloadArchitecture
            BootstrapperPEMachine = $M5Evidence.VisualCppRedistributable.BootstrapperPEMachine
            SHA256 = $M5Evidence.VisualCppRedistributable.SHA256
        }
        HostScripts = @(
            $HostScriptNames | ForEach-Object {
                $HostScriptPath = Join-Path $OutputDirectory $_
                [PSCustomObject]@{
                    FileName = $_
                    SHA256 = (Get-FileHash `
                        -Algorithm SHA256 `
                        -Path $HostScriptPath).Hash
                }
            }
        )
        RealHostVerification = [PSCustomObject]@{
            Installation = "notRun"
            COMActivation = "notRun"
            WidgetsBoard = "notRun"
        }
    }
    $EvidencePath = Join-Path `
        $OutputDirectory `
        "m6-windows-resume-evidence.json"
    $Evidence | ConvertTo-Json -Depth 8 |
        Set-Content -Path $EvidencePath -Encoding utf8NoBOM
    $Evidence | ConvertTo-Json -Depth 8
}
finally {
    if ($null -ne $Certificate) {
        $PrivateCertificatePath = "Cert:\CurrentUser\My\$($Certificate.Thumbprint)"
        if (Test-Path $PrivateCertificatePath) {
            Remove-Item -LiteralPath $PrivateCertificatePath -Force
        }
    }
}
