# Builds the signed phone app and copies it to ..\Releases.
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File tool\build_apk.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot)
if (-not (Test-Path 'android\key.properties')) { throw 'android\key.properties is missing (signing key).' }
$env:GRADLE_OPTS = '-Djava.net.preferIPv4Stack=true'
$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value

# ARM phones only (every real Android phone); keeps the file small.
flutter build apk --release --obfuscate --split-debug-info=build/symbols --target-platform android-arm,android-arm64
if ($LASTEXITCODE -ne 0) { throw 'APK build failed' }

$out = "..\Releases\PE Daily Report v$version.apk"
Copy-Item build\app\outputs\flutter-apk\app-release.apk $out -Force
'{0}  ({1:N1} MB)' -f (Resolve-Path $out), ((Get-Item $out).Length / 1MB)
