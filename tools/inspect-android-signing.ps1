[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ApkPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AndroidSdkPath
)

$ErrorActionPreference = 'Stop'

function Stop-Inspection {
    param([Parameter(Mandatory = $true)][string]$Message)

    [Console]::Error.WriteLine($Message)
    exit 2
}

function Invoke-AndroidTool {
    param(
        [Parameter(Mandatory = $true)][string]$ToolPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $output = & $ToolPath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Android tool failed: $([System.IO.Path]::GetFileName($ToolPath))"
    }

    return ($output | Out-String).Trim()
}

if (-not (Test-Path -LiteralPath $ApkPath -PathType Leaf)) {
    Stop-Inspection "APK not found: $ApkPath"
}

if (-not (Test-Path -LiteralPath $AndroidSdkPath -PathType Container)) {
    Stop-Inspection "Android SDK directory not found: $AndroidSdkPath"
}

$resolvedApkPath = (Resolve-Path -LiteralPath $ApkPath).Path
$sdkPath = (Resolve-Path -LiteralPath $AndroidSdkPath).Path
$apkanalyzerPath = Join-Path $sdkPath 'cmdline-tools\latest\bin\apkanalyzer.bat'

if (-not (Test-Path -LiteralPath $apkanalyzerPath -PathType Leaf)) {
    Stop-Inspection "apkanalyzer not found: $apkanalyzerPath"
}

$apksignerPath = Get-ChildItem -LiteralPath (Join-Path $sdkPath 'build-tools') -Directory -ErrorAction SilentlyContinue |
    Sort-Object -Property Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1

if (-not $apksignerPath) {
    Stop-Inspection "apksigner not found under: $(Join-Path $sdkPath 'build-tools')"
}

try {
    $packageName = Invoke-AndroidTool -ToolPath $apkanalyzerPath -Arguments @('manifest', 'application-id', $resolvedApkPath)
    $versionName = Invoke-AndroidTool -ToolPath $apkanalyzerPath -Arguments @('manifest', 'version-name', $resolvedApkPath)
    $versionCode = Invoke-AndroidTool -ToolPath $apkanalyzerPath -Arguments @('manifest', 'version-code', $resolvedApkPath)
    $signerOutput = Invoke-AndroidTool -ToolPath $apksignerPath -Arguments @('verify', '--print-certs', $resolvedApkPath)
} catch {
    Stop-Inspection $_.Exception.Message
}

$certificateMatch = [regex]::Match($signerOutput, '(?im)^Signer #1 certificate SHA-256 digest:\s*(?<digest>[0-9A-F:]+)\s*$')
if (-not $certificateMatch.Success) {
    Stop-Inspection 'Unable to read the APK signing certificate SHA-256 digest.'
}

$apkSha256 = (Get-FileHash -LiteralPath $resolvedApkPath -Algorithm SHA256).Hash.ToUpperInvariant()
$certificateSha256 = $certificateMatch.Groups['digest'].Value.Replace(':', '').ToUpperInvariant()

[PSCustomObject]@{
    PackageName = $packageName
    VersionName = $versionName
    VersionCode = $versionCode
    ApkSha256 = $apkSha256
    SigningCertificateSha256 = $certificateSha256
} | Format-List
