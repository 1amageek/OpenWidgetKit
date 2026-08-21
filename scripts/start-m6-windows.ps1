param(
    [string]$BundleDirectory = ".",
    [switch]$ValidateArtifactOnly,
    [switch]$ReplaceExisting,
    [string]$EvidenceOutputPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "OpenWidgetWindowsArtifactTools.ps1")

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw "M6 host preparation must run on Windows."
}

function Write-UTF8JSON {
    param(
        [object]$Value,
        [string]$Path
    )
    $Parent = Split-Path -Parent $Path
    if ($Parent) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }
    $JSON = $Value | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText(
        $Path,
        $JSON,
        [Text.UTF8Encoding]::new($false)
    )
}

function Test-IsAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
    return $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Get-NativeArchitecture {
    $ArchitectureName = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    switch ($ArchitectureName) {
        "X64" { return "x64" }
        "Arm64" { return "arm64" }
        default { throw "Unsupported Windows architecture: $ArchitectureName" }
    }
}

function Invoke-VisualCppRedistributable {
    param([string]$InstallerPath)
    $Process = Start-Process `
        -FilePath $InstallerPath `
        -ArgumentList @("/install", "/quiet", "/norestart") `
        -Wait `
        -PassThru
    if ($Process.ExitCode -notin @(0, 1638, 3010)) {
        throw "Visual C++ Redistributable failed with exit code $($Process.ExitCode)."
    }
    foreach ($RuntimeFile in @(
        "MSVCP140.dll",
        "VCRUNTIME140.dll",
        "VCRUNTIME140_1.dll"
    )) {
        $RuntimePath = Join-Path $env:WINDIR "System32\$RuntimeFile"
        if (-not (Test-Path $RuntimePath -PathType Leaf)) {
            throw "Visual C++ runtime installation did not provide $RuntimeFile."
        }
    }
    return $Process.ExitCode
}

function Install-WindowsAppRuntimePackages {
    param(
        [object[]]$Packages,
        [string]$DependencyDirectory
    )
    $Results = @()
    foreach ($Package in $Packages) {
        $Installed = @(
            Get-AppxPackage -Name $Package.IdentityName -ErrorAction SilentlyContinue
        ) | Sort-Object Version -Descending | Select-Object -First 1
        if ($null -ne $Installed `
            -and [Version]$Installed.Version -ge [Version]$Package.Version) {
            $Results += [PSCustomObject]@{
                IdentityName = $Package.IdentityName
                RequiredVersion = $Package.Version
                InstalledVersion = [string]$Installed.Version
                Action = "alreadySatisfied"
            }
            continue
        }
        Add-AppxPackage -Path (Join-Path $DependencyDirectory $Package.FileName)
        $Installed = Get-AppxPackage -Name $Package.IdentityName |
            Sort-Object Version -Descending |
            Select-Object -First 1
        if ($null -eq $Installed `
            -or [Version]$Installed.Version -lt [Version]$Package.Version) {
            throw "Windows App Runtime dependency '$($Package.IdentityName)' was not installed."
        }
        $Results += [PSCustomObject]@{
            IdentityName = $Package.IdentityName
            RequiredVersion = $Package.Version
            InstalledVersion = [string]$Installed.Version
            Action = "installed"
        }
    }
    return $Results
}

function Invoke-PackagedCOMProbe {
    param(
        [string]$ClassID,
        [int]$TimeoutSeconds = 30
    )
    $Probe = Start-Job -ArgumentList $ClassID -ScriptBlock {
        param([string]$ProbeClassID)
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

internal static class OpenWidgetPackagedCOMProbe
{
    private const uint COINIT_MULTITHREADED = 0;
    private const uint CLSCTX_LOCAL_SERVER = 4;
    private const int RPC_E_CHANGED_MODE = unchecked((int)0x80010106);

    [DllImport("ole32.dll")]
    private static extern int CoInitializeEx(IntPtr reserved, uint apartment);

    [DllImport("ole32.dll")]
    private static extern void CoUninitialize();

    [DllImport("ole32.dll", PreserveSig = true)]
    private static extern int CoCreateInstance(
        ref Guid classID,
        IntPtr outer,
        uint context,
        ref Guid interfaceID,
        out IntPtr instance
    );

    internal static int Activate(string classID)
    {
        int initialization = CoInitializeEx(IntPtr.Zero, COINIT_MULTITHREADED);
        bool mustUninitialize = initialization >= 0;
        if (initialization < 0 && initialization != RPC_E_CHANGED_MODE)
        {
            return initialization;
        }
        IntPtr instance = IntPtr.Zero;
        try
        {
            Guid classIdentifier = new Guid(classID);
            Guid unknownIdentifier = new Guid("00000000-0000-0000-C000-000000000046");
            int result = CoCreateInstance(
                ref classIdentifier,
                IntPtr.Zero,
                CLSCTX_LOCAL_SERVER,
                ref unknownIdentifier,
                out instance
            );
            if (instance != IntPtr.Zero)
            {
                Marshal.Release(instance);
            }
            return result;
        }
        finally
        {
            if (mustUninitialize)
            {
                CoUninitialize();
            }
        }
    }
}
"@
        [OpenWidgetPackagedCOMProbe]::Activate($ProbeClassID)
    }
    try {
        $Completed = Wait-Job -Job $Probe -Timeout $TimeoutSeconds
        if ($null -eq $Completed) {
            Stop-Job -Job $Probe
            throw "Packaged COM activation exceeded $TimeoutSeconds seconds."
        }
        if ($Probe.State -ne "Completed") {
            $Failure = Receive-Job -Job $Probe -ErrorAction SilentlyContinue |
                Out-String
            throw "Packaged COM activation job failed: $Failure"
        }
        $HRESULT = [int](Receive-Job -Job $Probe)
        if ($HRESULT -ne 0) {
            $UnsignedHRESULT = [BitConverter]::ToUInt32(
                [BitConverter]::GetBytes($HRESULT),
                0
            )
            throw ("Packaged COM activation failed with HRESULT 0x{0:X8}." -f $UnsignedHRESULT)
        }
        return "0x00000000"
    }
    finally {
        Remove-Job -Job $Probe -Force -ErrorAction SilentlyContinue
    }
}

$BundleDirectory = [IO.Path]::GetFullPath($BundleDirectory)
if (-not (Test-Path $BundleDirectory -PathType Container)) {
    throw "BundleDirectory must identify an extracted M6 resume bundle."
}
$ResumeEvidencePath = Join-Path `
    $BundleDirectory `
    "m6-windows-resume-evidence.json"
if (-not (Test-Path $ResumeEvidencePath -PathType Leaf)) {
    throw "The M6 resume evidence file was not found."
}
if (-not $EvidenceOutputPath) {
    $EvidenceOutputPath = Join-Path `
        $BundleDirectory `
        "m6-windows-host-evidence.json"
} elseif (-not [IO.Path]::IsPathRooted($EvidenceOutputPath)) {
    $EvidenceOutputPath = [IO.Path]::GetFullPath(
        (Join-Path $BundleDirectory $EvidenceOutputPath)
    )
}

$StartedAt = [DateTime]::UtcNow
$CertificateImportedThisRun = $false
$ProviderInstalledThisRun = $false
$HostEvidence = [ordered]@{
    SchemaVersion = 1
    StartedAt = $StartedAt.ToString("o")
    CompletedAt = $null
    Mode = if ($ValidateArtifactOnly) {
        "artifactValidation"
    } else {
        "installAndCOMProbe"
    }
    Result = "failed"
    Failure = $null
    Architecture = $null
    ArtifactValidation = "notRun"
    PrerequisiteValidation = "notRun"
    VisualCppRedistributable = "notRun"
    WindowsAppRuntime = "notRun"
    ProviderInstallation = "notRun"
    COMActivation = "notRun"
    WidgetsBoard = "notRun"
}

try {
    $ResumeEvidence = Get-Content -Raw $ResumeEvidencePath | ConvertFrom-Json
    if ($ResumeEvidence.SchemaVersion -ne 1 `
        -or -not $ResumeEvidence.DevelopmentOnly) {
        throw "The bundle is not a schema-1 development-only M6 resume bundle."
    }
    $HostEvidence.Architecture = $ResumeEvidence.Architecture
    $SignedPackagePath = Join-Path `
        $BundleDirectory `
        $ResumeEvidence.SignedPackage.FileName
    $CertificatePath = Join-Path `
        $BundleDirectory `
        $ResumeEvidence.SigningCertificate.FileName
    $DependencyDirectory = Join-Path $BundleDirectory "runtime-dependencies"
    Assert-OpenWidgetFileHash `
        -Path $SignedPackagePath `
        -ExpectedSHA256 $ResumeEvidence.SignedPackage.SHA256 | Out-Null
    Assert-OpenWidgetFileHash `
        -Path $CertificatePath `
        -ExpectedSHA256 $ResumeEvidence.SigningCertificate.SHA256 | Out-Null
    foreach ($HostScript in $ResumeEvidence.HostScripts) {
        Assert-OpenWidgetFileHash `
            -Path (Join-Path $BundleDirectory $HostScript.FileName) `
            -ExpectedSHA256 $HostScript.SHA256 | Out-Null
    }
    $PackageMetadata = Get-OpenWidgetMSIXMetadata `
        -PackagePath $SignedPackagePath
    foreach ($Property in @(
        "Name", "Publisher", "Version", "Architecture",
        "ApplicationID", "Executable", "ClassID"
    )) {
        $EvidenceProperty = if ($Property -eq "Name") {
            "IdentityName"
        } else {
            $Property
        }
        if ($PackageMetadata.$Property -ne $ResumeEvidence.SignedPackage.$EvidenceProperty) {
            throw "Signed package metadata mismatch for '$Property'."
        }
    }
    $Certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $CertificatePath
    )
    if ($Certificate.HasPrivateKey `
        -or $Certificate.Thumbprint -ne $ResumeEvidence.SigningCertificate.Thumbprint `
        -or $Certificate.Subject -ne $ResumeEvidence.SigningCertificate.Subject `
        -or $Certificate.Subject -ne $PackageMetadata.Publisher) {
        throw "The public development certificate does not match the package signer evidence."
    }
    if ($Certificate.NotAfter.ToUniversalTime() -le [DateTime]::UtcNow) {
        throw "The development certificate has expired; generate a fresh resume bundle."
    }
    $Signature = Get-AuthenticodeSignature -FilePath $SignedPackagePath
    if ($null -eq $Signature.SignerCertificate `
        -or $Signature.SignerCertificate.Thumbprint -ne $Certificate.Thumbprint `
        -or $Signature.Status -eq [Management.Automation.SignatureStatus]::HashMismatch `
        -or $Signature.Status -eq [Management.Automation.SignatureStatus]::NotSigned) {
        throw "The development MSIX signature does not match the exported certificate."
    }
    foreach ($RuntimePackage in $ResumeEvidence.WindowsAppRuntimePackages) {
        $RuntimePath = Join-Path $DependencyDirectory $RuntimePackage.FileName
        Assert-OpenWidgetFileHash `
            -Path $RuntimePath `
            -ExpectedSHA256 $RuntimePackage.SHA256 | Out-Null
        $RuntimeMetadata = Get-OpenWidgetMSIXMetadata -PackagePath $RuntimePath
        if ($RuntimeMetadata.Name -ne $RuntimePackage.IdentityName `
            -or $RuntimeMetadata.Publisher -ne $RuntimePackage.Publisher `
            -or $RuntimeMetadata.Version -ne $RuntimePackage.Version `
            -or $RuntimeMetadata.Architecture -ne $ResumeEvidence.Architecture) {
            throw "Windows App Runtime package '$($RuntimePackage.FileName)' failed metadata validation."
        }
    }
    if (@($ResumeEvidence.WindowsAppRuntimePackages).Count -ne 4) {
        throw "The bundle does not contain all four Windows App Runtime packages."
    }
    $VisualCppPath = Join-Path `
        $DependencyDirectory `
        $ResumeEvidence.VisualCppRedistributable.FileName
    Assert-OpenWidgetFileHash `
        -Path $VisualCppPath `
        -ExpectedSHA256 $ResumeEvidence.VisualCppRedistributable.SHA256 | Out-Null
    $VisualCppSignature = Get-AuthenticodeSignature -FilePath $VisualCppPath
    if ($VisualCppSignature.Status -ne [Management.Automation.SignatureStatus]::Valid) {
        throw "The Visual C++ Redistributable signature is not valid."
    }
    $HostEvidence.ArtifactValidation = "passed"

    if ($ValidateArtifactOnly) {
        $HostEvidence.Result = "passed"
        return
    }
    if (-not (Test-IsAdministrator)) {
        throw "Run this script from an elevated Windows PowerShell session."
    }
    $OperatingSystem = Get-CimInstance Win32_OperatingSystem
    if ($OperatingSystem.ProductType -ne 1 `
        -or [int]$OperatingSystem.BuildNumber -lt 22000) {
        throw "M6 requires Windows 11 client build 22000 or newer."
    }
    $NativeArchitecture = Get-NativeArchitecture
    if ($NativeArchitecture -ne $ResumeEvidence.Architecture) {
        throw "Bundle architecture '$($ResumeEvidence.Architecture)' does not match native host architecture '$NativeArchitecture'."
    }
    $WidgetsBoardPackage = Get-AppxPackage `
        -AllUsers `
        -Name "MicrosoftWindows.Client.WebExperience" `
        -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($null -eq $WidgetsBoardPackage) {
        throw "Windows Web Experience Pack is missing; Widgets Board cannot host the provider."
    }
    $HostEvidence.PrerequisiteValidation = "passed"
    $HostEvidence.WidgetsBoardPackageVersion = [string]$WidgetsBoardPackage.Version

    $ExistingPackages = @(Get-AppxPackage -Name $PackageMetadata.Name)
    if ($ExistingPackages.Count -gt 0 -and -not $ReplaceExisting) {
        throw "The provider is already installed. Re-run with -ReplaceExisting to replace the current-user package."
    }

    $HostEvidence.VisualCppRedistributable = [PSCustomObject]@{
        Status = "installedOrRepaired"
        ExitCode = Invoke-VisualCppRedistributable -InstallerPath $VisualCppPath
    }
    $HostEvidence.WindowsAppRuntime = @(
        Install-WindowsAppRuntimePackages `
            -Packages @($ResumeEvidence.WindowsAppRuntimePackages) `
            -DependencyDirectory $DependencyDirectory
    )

    $TrustedCertificatePath = `
        "Cert:\LocalMachine\TrustedPeople\$($Certificate.Thumbprint)"
    if (-not (Test-Path $TrustedCertificatePath)) {
        Import-Certificate `
            -FilePath $CertificatePath `
            -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" | Out-Null
        $HostEvidence.CertificateTrust = "imported"
        $CertificateImportedThisRun = $true
    } else {
        $HostEvidence.CertificateTrust = "alreadyPresent"
    }
    $TrustedSignature = Get-AuthenticodeSignature -FilePath $SignedPackagePath
    if ($TrustedSignature.Status -ne [Management.Automation.SignatureStatus]::Valid) {
        throw "The development MSIX signature is not valid after certificate trust installation."
    }

    if ($ExistingPackages.Count -gt 0) {
        foreach ($ExistingPackage in $ExistingPackages) {
            Remove-AppxPackage -Package $ExistingPackage.PackageFullName
        }
    }
    Add-AppxPackage -Path $SignedPackagePath
    $ProviderInstalledThisRun = $true
    $InstalledProvider = Get-AppxPackage -Name $PackageMetadata.Name |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($null -eq $InstalledProvider `
        -or [string]$InstalledProvider.Version -ne $PackageMetadata.Version `
        -or $InstalledProvider.Architecture.ToString().ToLowerInvariant() -ne $PackageMetadata.Architecture) {
        throw "The installed provider identity does not match the resume bundle."
    }
    $HostEvidence.ProviderInstallation = [PSCustomObject]@{
        Status = "passed"
        PackageFullName = $InstalledProvider.PackageFullName
    }
    $HostEvidence.COMActivation = [PSCustomObject]@{
        Status = "passed"
        HRESULT = Invoke-PackagedCOMProbe -ClassID $PackageMetadata.ClassID
    }
    $HostEvidence.WidgetsBoard = "readyForManualVerification"
    $HostEvidence.Result = "passed"
}
catch {
    $HostEvidence.Failure = [PSCustomObject]@{
        Type = $_.Exception.GetType().FullName
        Message = $_.Exception.Message
    }
    if ($CertificateImportedThisRun -and -not $ProviderInstalledThisRun) {
        $CertificatePathToRemove = `
            "Cert:\LocalMachine\TrustedPeople\$($Certificate.Thumbprint)"
        if (Test-Path $CertificatePathToRemove) {
            Remove-Item -LiteralPath $CertificatePathToRemove -Force
        }
        $HostEvidence.CertificateTrustRollback = "removed"
    }
    throw
}
finally {
    $HostEvidence.CompletedAt = [DateTime]::UtcNow.ToString("o")
    Write-UTF8JSON -Value $HostEvidence -Path $EvidenceOutputPath
}
