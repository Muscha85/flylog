#requires -Version 5.1
<#
.SYNOPSIS
    Builds the FlyLog release APK, copies it to Google Drive and pushes changes to GitHub.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  FlyLog - Build & Sync APK                        " -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Kontrola Flutter SDK
Write-Host "[1/4] Kontroluji dostupnost Flutter SDK..." -ForegroundColor Yellow
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    # Zkusime zname cesty, pokud neni v PATH
    $knownPaths = @(
        "$env:LOCALAPPDATA\flutter\bin\flutter.bat",
        "C:\src\flutter\bin\flutter.bat",
        "C:\flutter\bin\flutter.bat",
        "C:\tools\flutter\bin\flutter.bat",
        "$env:USERPROFILE\flutter\bin\flutter.bat"
    )
    foreach ($p in $knownPaths) {
        if (Test-Path $p) {
            $flutterExe = $p
            break
        }
    }
} else {
    $flutterExe = $flutterCmd.Source
}

if (-not $flutterExe) {
    Write-Warning "Prikaz 'flutter' nebyl nalezen v PATH ani ve standardnich umistenich."
    Write-Warning "Build APK na tomto stroji vyzaduje nainstalovany Flutter SDK s Android nastroji."
    Write-Warning "Zmeny budou ulozeny a odeslany na GitHub, kde automaticky probehne GitHub Actions build."
} else {
    Write-Host "Pouzivam Flutter: $flutterExe" -ForegroundColor Green
    Write-Host ""
    Write-Host "[2/4] Kompiluji Release APK (flutter build apk --release)..." -ForegroundColor Yellow
    & $flutterExe build apk --release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Chyba: Kompilace APK selhala s kodem $LASTEXITCODE."
    }

    $apkSource = "build\app\outputs\flutter-apk\app-release.apk"
    if (Test-Path $apkSource) {
        $destDir = "G:\Můj disk\Antigravity\FlyLog\Apk"
        if (-not (Test-Path $destDir)) {
            Write-Host "Vytvarim cilovou slozku: $destDir" -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        $latestApk = Join-Path $destDir "flylog-latest.apk"
        $timeStamp = Get-Date -Format 'yyyyMMdd-HHmm'
        $archiveApk = Join-Path $destDir "flylog-$timeStamp.apk"

        Write-Host "Kopiruji APK do Google Disku:" -ForegroundColor Green
        Write-Host "  -> $latestApk"
        Copy-Item -Path $apkSource -Destination $latestApk -Force

        Write-Host "  -> $archiveApk"
        Copy-Item -Path $apkSource -Destination $archiveApk -Force
        Write-Host "APK bylo uspesne zkopirovano na Google Disk." -ForegroundColor Green
    } else {
        Write-Warning "Soubor '$apkSource' nebyl nalezen po buildu."
    }
}

# 3. Synchronizace s GitHubem
Write-Host ""
Write-Host "[3/4] Synchronizuji zmeny na GitHub (git commit & push)..." -ForegroundColor Yellow

git add .
$status = git status --porcelain
if ($status) {
    git commit -m "build: release new APK"
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Git commit skoncil s varovanim."
    }
} else {
    Write-Host "Zadne nove zmeny k commitnuti." -ForegroundColor Gray
}

Write-Host "Odesilam na GitHub (git push origin main)..." -ForegroundColor Yellow
git push origin main
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Git push skoncil s kodem $LASTEXITCODE."
} else {
    Write-Host "GitHub synchronizace uspesne dokoncena." -ForegroundColor Green
}

Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  HOTOVO!                                          " -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan