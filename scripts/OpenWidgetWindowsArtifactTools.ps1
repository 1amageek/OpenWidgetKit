Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-OpenWidgetMSIXManifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackagePath
    )
    if (-not (Test-Path $PackagePath -PathType Leaf)) {
        throw "MSIX package not found: $PackagePath"
    }
    $Archive = [IO.Compression.ZipFile]::OpenRead(
        [IO.Path]::GetFullPath($PackagePath)
    )
    try {
        $ManifestEntry = $Archive.GetEntry("AppxManifest.xml")
        if ($null -eq $ManifestEntry) {
            throw "The MSIX '$PackagePath' has no AppxManifest.xml."
        }
        $Reader = [IO.StreamReader]::new($ManifestEntry.Open())
        try {
            [xml]$Manifest = $Reader.ReadToEnd()
            return $Manifest
        }
        finally {
            $Reader.Dispose()
        }
    }
    finally {
        $Archive.Dispose()
    }
}

function Get-OpenWidgetMSIXMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackagePath
    )
    $Manifest = Get-OpenWidgetMSIXManifest -PackagePath $PackagePath
    $Identity = $Manifest.SelectSingleNode(
        "/*[local-name()='Package']/*[local-name()='Identity']"
    )
    if ($null -eq $Identity) {
        throw "The MSIX '$PackagePath' has no package identity."
    }
    $Application = $Manifest.SelectSingleNode(
        "/*[local-name()='Package']/*[local-name()='Applications']/*[local-name()='Application']"
    )
    $CreateInstance = $Manifest.SelectSingleNode(
        "//*[local-name()='CreateInstance']"
    )
    $RuntimeDependency = $Manifest.SelectSingleNode(
        "/*[local-name()='Package']/*[local-name()='Dependencies']/*[local-name()='PackageDependency']"
    )
    return [PSCustomObject]@{
        Name = [string]$Identity.Name
        Publisher = [string]$Identity.Publisher
        Version = [string]$Identity.Version
        Architecture = [string]$Identity.ProcessorArchitecture
        ApplicationID = if ($null -eq $Application) {
            $null
        } else {
            [string]$Application.Id
        }
        Executable = if ($null -eq $Application) {
            $null
        } else {
            [string]$Application.Executable
        }
        ClassID = if ($null -eq $CreateInstance) {
            $null
        } else {
            [string]$CreateInstance.ClassId
        }
        RuntimeDependency = if ($null -eq $RuntimeDependency) {
            $null
        } else {
            [PSCustomObject]@{
                Name = [string]$RuntimeDependency.Name
                Publisher = [string]$RuntimeDependency.Publisher
                MinVersion = [string]$RuntimeDependency.MinVersion
            }
        }
    }
}

function Assert-OpenWidgetFileHash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedSHA256
    )
    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "Required artifact not found: $Path"
    }
    if ($ExpectedSHA256 -notmatch '^[A-Fa-f0-9]{64}$') {
        throw "ExpectedSHA256 must contain exactly 64 hexadecimal characters."
    }
    $ActualSHA256 = (Get-FileHash -Algorithm SHA256 -Path $Path).Hash
    if ($ActualSHA256 -ne $ExpectedSHA256) {
        throw "SHA-256 mismatch for '$Path': $ActualSHA256"
    }
    return $ActualSHA256
}
