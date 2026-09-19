[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FlutterProjectPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SigningPropertiesPath,

    [Parameter(Mandatory = $true)]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ApiBaseUrl,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VersionName,

    [Parameter(Mandatory = $true)]
    [int]$VersionCode,

    [Parameter(Mandatory = $true)]
    [switch]$CronetHttpNoPlay,

    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

$expectedApiBaseUrl = 'https://api.suixiangji.icu'
$expectedVersionName = '1.0.4'
$expectedVersionCode = 7
$expectedApplicationId = 'com.example.wealthmate_flutter'
$expectedSigningCertificateSha256 = 'CADEB8CA7786B755305E07A086B407D8DA7D6751D54566D9A0787D457DF32458'
$forbiddenV1_0_2ApkSha256 = '7E71B0FEF91F9C734B5FB99A0ABAB8F783C2A28ADB8EEDA7A26A82EEEA29058A'

function Stop-BuildGuard {
    param([Parameter(Mandatory = $true)][string]$Message)

    throw "BUILD GUARD FAILED: $Message"
}

function Resolve-ExistingFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Stop-BuildGuard "required file is missing: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-ExistingDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Stop-BuildGuard "required directory is missing: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Read-SigningProperties {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedPath = Resolve-ExistingFile -Path $Path
    $values = @{}

    foreach ($line in Get-Content -LiteralPath $resolvedPath) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
            continue
        }

        $separator = $trimmed.IndexOf('=')
        if ($separator -le 0) {
            Stop-BuildGuard "signing properties contains an invalid line"
        }

        $key = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim()
        $values[$key] = $value
    }

    foreach ($requiredKey in @('storeFile', 'storePassword', 'keyAlias', 'keyPassword')) {
        if (-not $values.ContainsKey($requiredKey) -or [string]::IsNullOrWhiteSpace($values[$requiredKey])) {
            Stop-BuildGuard "signing properties is missing required field: $requiredKey"
        }
    }

    $storeFileValue = $values['storeFile']
    $storeFilePath = if ([System.IO.Path]::IsPathRooted($storeFileValue)) {
        $storeFileValue
    } else {
        Join-Path (Split-Path -Parent $resolvedPath) $storeFileValue
    }
    $resolvedStoreFile = Resolve-ExistingFile -Path $storeFilePath

    return @{
        PropertiesPath = $resolvedPath
        StoreFilePath = $resolvedStoreFile
    }
}

function Resolve-AndroidSdkPath {
    param([Parameter(Mandatory = $true)][string]$ProjectPath)

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_SDK_ROOT)) {
        $candidates += $env:ANDROID_SDK_ROOT
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) {
        $candidates += $env:ANDROID_HOME
    }

    $localPropertiesPath = Join-Path $ProjectPath 'android\local.properties'
    if (Test-Path -LiteralPath $localPropertiesPath -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $localPropertiesPath) {
            if ($line -match '^\s*sdk\.dir=(.+)$') {
                $candidate = $Matches[1].Trim().Replace('\\', '\')
                $candidates += $candidate
                break
            }
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    Stop-BuildGuard 'Android SDK path was not found in ANDROID_SDK_ROOT, ANDROID_HOME, or android/local.properties'
}

function Get-InspectionValue {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $pattern = '(?im)^' + [regex]::Escape($Name) + '\s*:\s*(?<value>.+?)\s*$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) {
        Stop-BuildGuard "APK inspection did not report $Name"
    }
    return $match.Groups['value'].Value.Trim()
}

try {
    $projectPath = Resolve-ExistingDirectory -Path $FlutterProjectPath
    $gradlePath = Resolve-ExistingFile -Path (Join-Path $projectPath 'android\app\build.gradle.kts')
    $signing = Read-SigningProperties -Path $SigningPropertiesPath

    if ($Environment -ne 'production') {
        Stop-BuildGuard 'Environment must be production'
    }
    if ($ApiBaseUrl -ne $expectedApiBaseUrl) {
        Stop-BuildGuard "ApiBaseUrl must be $expectedApiBaseUrl"
    }
    if (-not $CronetHttpNoPlay) {
        Stop-BuildGuard 'CronetHttpNoPlay must be enabled for the embedded Cronet build'
    }
    if ($VersionName -ne $expectedVersionName) {
        Stop-BuildGuard "VersionName must be $expectedVersionName"
    }
    if ($VersionCode -ne $expectedVersionCode) {
        Stop-BuildGuard "VersionCode must be $expectedVersionCode"
    }

    $gradleContent = Get-Content -LiteralPath $gradlePath -Raw
    if ($gradleContent -notmatch 'applicationId\s*=\s*"com\.example\.wealthmate_flutter"') {
        Stop-BuildGuard "applicationId must remain $expectedApplicationId"
    }
    if ($gradleContent -match 'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)' -or
        $gradleContent -match 'signingConfig\s*=\s*signingConfigs\.debug') {
        Stop-BuildGuard 'release signing must not use signingConfigs.debug'
    }
    if ($gradleContent -notmatch 'signingConfig\s*=\s*signingConfigs\.getByName\("release"\)' -and
        $gradleContent -notmatch 'signingConfig\s*=\s*signingConfigs\.release') {
        Stop-BuildGuard 'release signing must explicitly use the release signing config'
    }

    Write-Output "Environment: $Environment"
    Write-Output "ApiBaseUrl: $ApiBaseUrl"
    Write-Output "VersionName: $VersionName"
    Write-Output "VersionCode: $VersionCode"
    Write-Output 'CronetHttpNoPlay: true'
    Write-Output "SigningPropertiesPresent: $($signing.PropertiesPath -ne $null)"

    if ($ValidateOnly) {
        Write-Output 'BUILD_GUARD: PASS'
        Write-Output 'ValidationOnly: true'
        return
    }

    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $flutterCommand) {
        Stop-BuildGuard 'flutter executable was not found on PATH'
    }

    $androidSdkPath = Resolve-AndroidSdkPath -ProjectPath $projectPath
    $inspectScript = Resolve-ExistingFile -Path (Join-Path $PSScriptRoot 'inspect-android-signing.ps1')
    $flutterArgs = @(
        'build',
        'apk',
        '--release',
        "--dart-define=WEALTHMATE_ENVIRONMENT=$Environment",
        "--dart-define=WEALTHMATE_API_BASE_URL=$ApiBaseUrl",
        '--dart-define=cronetHttpNoPlay=true'
    )

    $previousSigningPropertiesPath = $env:WEALTHMATE_SIGNING_PROPERTIES_PATH
    $locationPushed = $false
    try {
        $env:WEALTHMATE_SIGNING_PROPERTIES_PATH = $signing.PropertiesPath
        Push-Location -LiteralPath $projectPath
        $locationPushed = $true
        & $flutterCommand.Source @flutterArgs
        if ($LASTEXITCODE -ne 0) {
            Stop-BuildGuard "flutter build apk failed with exit code $LASTEXITCODE"
        }
    } finally {
        if ($locationPushed) {
            Pop-Location
        }
        $env:WEALTHMATE_SIGNING_PROPERTIES_PATH = $previousSigningPropertiesPath
    }

    $sourceCandidates = @(
        (Join-Path $projectPath 'build\app\outputs\flutter-apk\app-release.apk'),
        (Join-Path $projectPath 'build\app\outputs\apk\release\app-release.apk')
    )
    $sourceApk = $sourceCandidates |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if (-not $sourceApk) {
        Stop-BuildGuard 'Flutter completed without producing app-release.apk'
    }
    $sourceApk = (Resolve-Path -LiteralPath $sourceApk).Path
    $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = Split-Path -Parent $resolvedOutputPath
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    if ([StringComparer]::OrdinalIgnoreCase.Equals($sourceApk, $resolvedOutputPath)) {
        $resolvedOutputPath = $sourceApk
    } else {
        Copy-Item -LiteralPath $sourceApk -Destination $resolvedOutputPath -Force
    }

    $inspectionOutput = (& pwsh -NoProfile -File $inspectScript -ApkPath $resolvedOutputPath -AndroidSdkPath $androidSdkPath 2>&1 | Out-String)
    $inspectionExitCode = $LASTEXITCODE
    if ($inspectionExitCode -ne 0) {
        Stop-BuildGuard 'APK signing inspection failed'
    }

    $actualPackageName = Get-InspectionValue -Text $inspectionOutput -Name 'PackageName'
    $actualVersionName = Get-InspectionValue -Text $inspectionOutput -Name 'VersionName'
    $actualVersionCode = Get-InspectionValue -Text $inspectionOutput -Name 'VersionCode'
    $actualSigningCertificate = (Get-InspectionValue -Text $inspectionOutput -Name 'SigningCertificateSha256').ToUpperInvariant()
    $apkSha256 = (Get-FileHash -LiteralPath $resolvedOutputPath -Algorithm SHA256).Hash.ToUpperInvariant()
    $fileSize = (Get-Item -LiteralPath $resolvedOutputPath).Length

    if ($actualPackageName -ne $expectedApplicationId) {
        Stop-BuildGuard "APK applicationId was $actualPackageName, expected $expectedApplicationId"
    }
    if ($actualVersionName -ne $expectedVersionName) {
        Stop-BuildGuard "APK versionName was $actualVersionName, expected $expectedVersionName"
    }
    if ($actualVersionCode -ne "$expectedVersionCode") {
        Stop-BuildGuard "APK versionCode was $actualVersionCode, expected $expectedVersionCode"
    }
    if ($actualSigningCertificate -ne $expectedSigningCertificateSha256) {
        Stop-BuildGuard 'APK signing certificate does not match the approved V1.0.3 signing identity'
    }
    if ($apkSha256 -eq $forbiddenV1_0_2ApkSha256) {
        Stop-BuildGuard 'APK hash matches the incorrect V1.0.2 artifact'
    }

    Write-Output "BUILD_GUARD: PASS"
    Write-Output "OutputPath: $resolvedOutputPath"
    Write-Output "ApplicationId: $actualPackageName"
    Write-Output "VersionName: $actualVersionName"
    Write-Output "VersionCode: $actualVersionCode"
    Write-Output "SigningCertificateSha256: $actualSigningCertificate"
    Write-Output "ApkSha256: $apkSha256"
    Write-Output "FileSizeBytes: $fileSize"
} catch {
    [Console]::Error.WriteLine('BUILD_GUARD: FAIL')
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 2
}
