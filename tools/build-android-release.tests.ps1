[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'build-android-release.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'suixiangji-build-android-tests-' + [Guid]::NewGuid().ToString('N')
)
$originalPath = $env:PATH
$originalAndroidSdkRoot = $env:ANDROID_SDK_ROOT
$originalAndroidHome = $env:ANDROID_HOME
$originalFakeFlutterProject = $env:FAKE_FLUTTER_PROJECT
$originalFakeFlutterLog = $env:FAKE_FLUTTER_LOG
$passed = 0

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    if (-not $Condition) {
        throw "$Name failed: $FailureMessage"
    }
    Write-Output "PASS: $Name"
    $script:passed++
}

function Invoke-BuildScript {
    param([Parameter(Mandatory = $true)][hashtable]$Arguments)

    $output = & pwsh -NoProfile -File $scriptPath @Arguments 2>&1 | Out-String
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = $output
    }
}

function Assert-GuardRejects {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][hashtable]$Arguments,
        [Parameter(Mandatory = $true)][string]$ExpectedMessage
    )

    $result = Invoke-BuildScript -Arguments $Arguments
    $matchesMessage = $result.Output -match [regex]::Escape($ExpectedMessage)
    Assert-Condition -Name $Name -Condition ($result.ExitCode -ne 0 -and $matchesMessage) -FailureMessage (
        "exit=$($result.ExitCode); output=$($result.Output.Trim())"
    )
}

try {
    Assert-Condition -Name 'build script exists before guard cases run' -Condition (
        Test-Path -LiteralPath $scriptPath -PathType Leaf
    ) -FailureMessage "missing $scriptPath"

    New-Item -ItemType Directory -Path (Join-Path $testRoot 'flutter\android\app') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'fake-bin') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'fake-sdk\cmdline-tools\latest\bin') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'fake-sdk\build-tools\36.0.0') -Force | Out-Null

    $flutterProject = Join-Path $testRoot 'flutter'
    $fakeBin = Join-Path $testRoot 'fake-bin'
    $fakeSdk = Join-Path $testRoot 'fake-sdk'
    $signingProperties = Join-Path $flutterProject 'android\signing.properties'
    $outputPath = Join-Path $testRoot 'outputs\suixiangji-v1.0.4-build7.apk'
    $fakeFlutterLog = Join-Path $testRoot 'fake-flutter-args.txt'

    Set-Content -LiteralPath (Join-Path $flutterProject 'pubspec.yaml') -Value @'
name: wealthmate_flutter
version: 1.0.4+7
'@ -Encoding utf8
    Set-Content -LiteralPath (Join-Path $flutterProject 'android\app\build.gradle.kts') -Value @'
android {
    defaultConfig {
        applicationId = "com.example.wealthmate_flutter"
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
    signingConfigs {
        create("release") {}
    }
}
'@ -Encoding utf8
    Set-Content -LiteralPath $signingProperties -Value @'
storeFile=fake-signing.keystore
storePassword=test-only-value
keyAlias=androiddebugkey
keyPassword=test-only-value
'@ -Encoding utf8
    Set-Content -LiteralPath (Join-Path $flutterProject 'android\fake-signing.keystore') -Value 'test-only-keystore' -Encoding ascii

    Set-Content -LiteralPath (Join-Path $fakeBin 'flutter.bat') -Value @'
@echo off
setlocal
if not "%FAKE_FLUTTER_LOG%"=="" echo %*>>"%FAKE_FLUTTER_LOG%"
set "OUTPUT=%FAKE_FLUTTER_PROJECT%\build\app\outputs\flutter-apk"
if not exist "%OUTPUT%" mkdir "%OUTPUT%"
type nul > "%OUTPUT%\app-release.apk"
exit /b 0
'@ -Encoding ascii
    Set-Content -LiteralPath (Join-Path $fakeSdk 'cmdline-tools\latest\bin\apkanalyzer.bat') -Value @'
@echo off
if "%2"=="application-id" echo com.example.wealthmate_flutter
if "%2"=="version-name" echo 1.0.4
if "%2"=="version-code" echo 7
exit /b 0
'@ -Encoding ascii
    Set-Content -LiteralPath (Join-Path $fakeSdk 'build-tools\36.0.0\apksigner.bat') -Value @'
@echo off
if not "%1"=="verify" exit /b 1
echo Signer #1 certificate SHA-256 digest: cadeb8ca7786b755305e07a086b407d8da7d6751d54566d9a0787d457df32458
exit /b 0
'@ -Encoding ascii

    $env:PATH = "$fakeBin;$originalPath"
    $env:ANDROID_SDK_ROOT = $fakeSdk
    $env:ANDROID_HOME = $fakeSdk
    $env:FAKE_FLUTTER_PROJECT = $flutterProject
    $env:FAKE_FLUTTER_LOG = $fakeFlutterLog

    $baseArguments = @{
        FlutterProjectPath = $flutterProject
        OutputPath = $outputPath
        SigningPropertiesPath = $signingProperties
        Environment = 'production'
        ApiBaseUrl = 'https://api.suixiangji.icu'
        VersionName = '1.0.4'
        VersionCode = 7
        CronetHttpNoPlay = $true
    }

    $case = $baseArguments.Clone()
    $case.Environment = 'development'
    Assert-GuardRejects -Name 'rejects non-production environment' -Arguments $case -ExpectedMessage 'production'

    $case = $baseArguments.Clone()
    $case.ApiBaseUrl = 'https://api.example.invalid'
    Assert-GuardRejects -Name 'rejects non-production API host' -Arguments $case -ExpectedMessage 'api.suixiangji.icu'

    $case = $baseArguments.Clone()
    $case.ApiBaseUrl = 'http://api.suixiangji.icu'
    Assert-GuardRejects -Name 'rejects non-HTTPS production API' -Arguments $case -ExpectedMessage 'HTTPS'

    $case = $baseArguments.Clone()
    $case.CronetHttpNoPlay = $false
    Assert-GuardRejects -Name 'rejects disabled embedded Cronet' -Arguments $case -ExpectedMessage 'Cronet'

    $case = $baseArguments.Clone()
    $case.VersionName = '1.0.3'
    Assert-GuardRejects -Name 'rejects wrong version name' -Arguments $case -ExpectedMessage '1.0.4'

    $case = $baseArguments.Clone()
    $case.VersionCode = 6
    Assert-GuardRejects -Name 'rejects wrong version code' -Arguments $case -ExpectedMessage '7'

    $case = $baseArguments.Clone()
    $case.SigningPropertiesPath = Join-Path $testRoot 'missing-signing.properties'
    Assert-GuardRejects -Name 'rejects missing signing properties' -Arguments $case -ExpectedMessage 'signing'

    $result = Invoke-BuildScript -Arguments $baseArguments
    Assert-Condition -Name 'accepts complete production build configuration' -Condition ($result.ExitCode -eq 0) -FailureMessage (
        "exit=$($result.ExitCode); output=$($result.Output.Trim())"
    )
    Assert-Condition -Name 'reports production guard pass' -Condition ($result.Output -match 'BUILD_GUARD: PASS') -FailureMessage $result.Output
    Assert-Condition -Name 'prints the fixed production API base URL' -Condition ($result.Output -match [regex]::Escape('https://api.suixiangji.icu')) -FailureMessage $result.Output
    Assert-Condition -Name 'creates the requested output artifact' -Condition (
        Test-Path -LiteralPath $outputPath -PathType Leaf
    ) -FailureMessage "missing $outputPath"

    $flutterArgs = Get-Content -LiteralPath $fakeFlutterLog -Raw
    foreach ($expected in @(
        'build apk --release',
        '--dart-define=WEALTHMATE_ENVIRONMENT=production',
        '--dart-define=WEALTHMATE_API_BASE_URL=https://api.suixiangji.icu',
        '--dart-define=cronetHttpNoPlay=true'
    )) {
        Assert-Condition -Name "passes $expected to Flutter" -Condition (
            $flutterArgs.Contains($expected)
        ) -FailureMessage $flutterArgs
    }

    $validateOnly = $baseArguments.Clone()
    $validateOnly.ValidateOnly = $true
    $beforeValidateOnlyLog = (Get-Item -LiteralPath $fakeFlutterLog).Length
    $result = Invoke-BuildScript -Arguments $validateOnly
    Assert-Condition -Name 'validate-only accepts complete production configuration' -Condition ($result.ExitCode -eq 0) -FailureMessage (
        "exit=$($result.ExitCode); output=$($result.Output.Trim())"
    )
    $afterValidateOnlyLog = (Get-Item -LiteralPath $fakeFlutterLog).Length
    Assert-Condition -Name 'validate-only does not invoke Flutter' -Condition (
        $beforeValidateOnlyLog -eq $afterValidateOnlyLog
    ) -FailureMessage "log size changed from $beforeValidateOnlyLog to $afterValidateOnlyLog"

    Write-Output "Task 3 build guard tests: $passed passed"
} catch {
    Write-Error $_.Exception.Message
    exit 1
} finally {
    $env:PATH = $originalPath
    $env:ANDROID_SDK_ROOT = $originalAndroidSdkRoot
    $env:ANDROID_HOME = $originalAndroidHome
    $env:FAKE_FLUTTER_PROJECT = $originalFakeFlutterProject
    $env:FAKE_FLUTTER_LOG = $originalFakeFlutterLog
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
