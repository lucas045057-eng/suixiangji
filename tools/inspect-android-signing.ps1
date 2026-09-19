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

function Resolve-JavaHome {
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $candidates += $env:JAVA_HOME
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $candidates += (Join-Path $env:ProgramFiles 'Android\Android Studio\jbr')
    }
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Android\Android Studio\jbr')
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'bin\java.exe') -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    Stop-Inspection 'Java runtime not found for Android SDK inspection'
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
    $javaHome = Resolve-JavaHome
    $previousJavaHome = $env:JAVA_HOME
    $env:JAVA_HOME = $javaHome
    $packageName = Invoke-AndroidTool -ToolPath $apkanalyzerPath -Arguments @('manifest', 'application-id', $resolvedApkPath)
    $versionName = Invoke-AndroidTool -ToolPath $apkanalyzerPath -Arguments @('manifest', 'version-name', $resolvedApkPath)
    $versionCode = Invoke-AndroidTool -ToolPath $apkanalyzerPath -Arguments @('manifest', 'version-code', $resolvedApkPath)
    $signerOutput = Invoke-AndroidTool -ToolPath $apksignerPath -Arguments @('verify', '--print-certs', $resolvedApkPath)
} catch {
    Stop-Inspection $_.Exception.Message
} finally {
    $env:JAVA_HOME = $previousJavaHome
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
