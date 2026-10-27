# Builds the website, adds the phone app for "Install App", and puts it
# online (Cloudflare). Build the phone app first (tool\build_apk.ps1).
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File tool\deploy_web.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot)
$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
$apk = "..\Releases\PE Daily Report v$version.apk"
if (-not (Test-Path $apk)) { throw "Build the phone app first: $apk not found" }
if ((Get-Item $apk).Length -gt 25MB) { throw 'The APK is over 25 MB, Cloudflare will not take it.' }

flutter build web --release --no-web-resources-cdn
if ($LASTEXITCODE -ne 0) { throw 'Website build failed' }

# Only handed out through the login check in worker/index.js.
New-Item -ItemType Directory -Force build\web\private-app | Out-Null
Copy-Item $apk build\web\private-app\pe-daily-report.apk -Force

npx wrangler deploy
if ($LASTEXITCODE -ne 0) { throw 'Deploy failed' }
