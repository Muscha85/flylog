#requires -Version 5.1
<#
.SYNOPSIS
    Builds the FlyLog release APK, copies it to Google Drive and pushes changes to GitHub.
    If local Flutter is not present, it triggers the GitHub Actions cloud build,
    waits for the release APK artifact to finish, and automatically downloads it to Google Drive!
#>
[CmdletBinding()]
param(
    [switch]$NoWaitCloud
)

$ErrorActionPreference = 'Stop'

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  FlyLog - Build & Sync APK                        " -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

$destDir = "G:\Můj disk\Antigravity\FlyLog\Apk"
if (-not (Test-Path $destDir)) {
    Write-Host "Vytvarim cilovou slozku: $destDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}

# 1. Kontrola lokalniho Flutter SDK
Write-Host "[1/4] Kontroluji dostupnost lokalniho Flutter SDK..." -ForegroundColor Yellow
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
$flutterExe = $null
if (-not $flutterCmd) {
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

$localBuildSuccess = $false
if ($flutterExe) {
    Write-Host "Pouzivam lokalni Flutter: $flutterExe" -ForegroundColor Green
    Write-Host "[2/4] Kompiluji Release APK lokalne..." -ForegroundColor Yellow
    & $flutterExe build apk --release
    $apkSource = "build\app\outputs\flutter-apk\app-release.apk"
    if ($LASTEXITCODE -eq 0 -and (Test-Path $apkSource)) {
        $latestApk = Join-Path $destDir "flylog-latest.apk"
        $timeStamp = Get-Date -Format 'yyyyMMdd-HHmm'
        $archiveApk = Join-Path $destDir "flylog-$timeStamp.apk"

        Copy-Item -Path $apkSource -Destination $latestApk -Force
        Copy-Item -Path $apkSource -Destination $archiveApk -Force
        Write-Host "Lokalni APK bylo uspesne zkopirovano na Google Disk." -ForegroundColor Green
        $localBuildSuccess = $true
    }
} else {
    Write-Host "Lokalni Flutter SDK nenalezen -> vyuzijeme automaticky GitHub Actions cloud build." -ForegroundColor Cyan
}

# 2. Synchronizace s GitHubem
Write-Host ""
Write-Host "[3/4] Synchronizuji zmeny na GitHub (git commit & push)..." -ForegroundColor Yellow

git add .
$status = git status --porcelain
if ($status) {
    git commit -m "build: release new APK"
} else {
    Write-Host "Zadne nove zmeny k commitnuti." -ForegroundColor Gray
}

Write-Host "Odesilam na GitHub (git push origin main)..." -ForegroundColor Yellow
git push origin main
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Git push skoncil s kodem $LASTEXITCODE."
    exit $LASTEXITCODE
}
Write-Host "GitHub synchronizace uspesne dokoncena." -ForegroundColor Green

# 3. Pokud neprobehl lokalni build, pockame na GitHub Actions a stahneme hotove APK na Google Disk
if (-not $localBuildSuccess -and -not $NoWaitCloud) {
    Write-Host ""
    Write-Host "[4/4] Cekam na dokonceni buildu v GitHub Actions a stazeni APK na Google Disk..." -ForegroundColor Yellow
    
    # Ziskame token pro stazeni z Git Credential Manageru
    $cred = cmd.exe /c "echo protocol=https& echo host=github.com& echo." | git credential fill
    $tokenMatch = $cred | Select-String "password="
    $token = if ($tokenMatch) { $tokenMatch.ToString().Replace("password=","").Trim() } else { $null }

    $headers = @{
        "User-Agent" = "PowerShell"
        "Accept" = "application/vnd.github+json"
    }
    if ($token) {
        $headers["Authorization"] = "Bearer $token"
    }

    $commitSha = (git rev-parse HEAD).Trim()
    Write-Host "Hledam workflow run pro commit: $($commitSha.Substring(0,7))..." -ForegroundColor Gray

    $run = $null
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 3
        try {
            $resp = Invoke-RestMethod -Uri "https://api.github.com/repos/Muscha85/flylog/actions/runs?head_sha=$commitSha" -Headers $headers -ErrorAction Stop
            if ($resp.workflow_runs -and $resp.workflow_runs.Count -gt 0) {
                $run = $resp.workflow_runs[0]
                break
            }
        } catch {}
    }

    if ($run) {
        Write-Host "Workflow spusten (Run ID: $($run.id)), sleduji prubeh kompilace..." -ForegroundColor Cyan
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($run.status -ne "completed") {
            Write-Host "  ... status: $($run.status) ($([int]$sw.Elapsed.TotalSeconds)s)" -ForegroundColor Gray
            Start-Sleep -Seconds 10
            $run = Invoke-RestMethod -Uri "https://api.github.com/repos/Muscha85/flylog/actions/runs/$($run.id)" -Headers $headers
        }

        Write-Host "Build dokoncen s vysledkem: $($run.conclusion)" -ForegroundColor $(if ($run.conclusion -eq 'success') { 'Green' } else { 'Red' })

        if ($run.conclusion -eq "success") {
            $artResp = Invoke-RestMethod -Uri "https://api.github.com/repos/Muscha85/flylog/actions/runs/$($run.id)/artifacts" -Headers $headers
            if ($artResp.artifacts -and $artResp.artifacts.Count -gt 0) {
                $art = $artResp.artifacts[0]
                Write-Host "Stahuji artefakt $($art.name) ($([math]::Round($art.size_in_bytes/1MB, 2)) MB)..." -ForegroundColor Yellow

                $tempZip = Join-Path $env:TEMP "flylog-artifact-$($run.id).zip"
                $tempExtract = Join-Path $env:TEMP "flylog-artifact-extract-$($run.id)"
                if (Test-Path $tempExtract) { Remove-Item -Recurse -Force $tempExtract }

                Invoke-WebRequest -Uri $art.archive_download_url -Headers $headers -OutFile $tempZip -MaximumRedirection 5
                Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

                $downloadedApk = Get-ChildItem -Path $tempExtract -Filter "*.apk" -Recurse | Select-Object -First 1
                if ($downloadedApk) {
                    $latestApk = Join-Path $destDir "flylog-latest.apk"
                    $timeStamp = Get-Date -Format 'yyyyMMdd-HHmm'
                    $archiveApk = Join-Path $destDir "flylog-$timeStamp.apk"

                    Copy-Item -Path $downloadedApk.FullName -Destination $latestApk -Force
                    Copy-Item -Path $downloadedApk.FullName -Destination $archiveApk -Force

                    Write-Host ""
                    Write-Host "HOTOVO! APK bylo uspesne ulozeno na Google Disk:" -ForegroundColor Green
                    Write-Host "  -> $latestApk" -ForegroundColor Green
                    Write-Host "  -> $archiveApk" -ForegroundColor Green
                }
                Remove-Item -Force $tempZip -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $tempExtract -ErrorAction SilentlyContinue
            }
        } else {
            Write-Error "Cloud build selhal ($($run.conclusion)). Zkontrolujte logy na: $($run.html_url)"
        }
    }
}

Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  PROCES DOKONCEN                                  " -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan