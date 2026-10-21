<#
.SYNOPSIS
    JuYing Windows x64 Release Packaging Automation Script.
    Generates Portable Zip package and Inno Setup installer.
    Follows ADR-009 (GPL-3.0) and Project Guidance Document v0.2.
#>

[CmdletBinding()]
param(
    [string]$Version = "0.2.0",
    [switch]$SkipBuild = $false
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Get-Item $PSScriptRoot).Parent.FullName
$AppDir = Join-Path $RepoRoot "apps\juying_app"
$BuildReleaseDir = Join-Path $RepoRoot "build\windows\x64\runner\Release"
$DistDir = Join-Path $RepoRoot "dist\windows"
$IssPath = Join-Path $AppDir "windows\packaging\juying_installer.iss"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " JuYing Windows x64 Build & Packaging (v$Version)" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Create dist directory
if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
}

# 2. Run Flutter Windows Release build if requested
if (-not $SkipBuild) {
    Write-Host "[1/4] Running Flutter Windows Release build..." -ForegroundColor Yellow
    Push-Location $AppDir
    try {
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter windows release build failed with exit code: $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "[1/4] Skipping compilation, packaging existing binaries..." -ForegroundColor DarkYellow
}

if (-not (Test-Path $BuildReleaseDir)) {
    $AppBuildReleaseDir = Join-Path $AppDir "build\windows\x64\runner\Release"
    if (Test-Path $AppBuildReleaseDir) {
        $BuildReleaseDir = $AppBuildReleaseDir
    } else {
        throw "Build output directory not found at $BuildReleaseDir or $AppBuildReleaseDir"
    }
}

# 3. Assemble Portable Zip
Write-Host "[2/4] Assembling Portable ZIP package..." -ForegroundColor Yellow
$PortableStageName = "JuYing-v$Version-windows-x64-portable"
$PortableStageDir = Join-Path $DistDir $PortableStageName
$PortableZipFile = Join-Path $DistDir "$PortableStageName.zip"

if (Test-Path $PortableStageDir) {
    Remove-Item -Path $PortableStageDir -Recurse -Force
}
if (Test-Path $PortableZipFile) {
    Remove-Item -Path $PortableZipFile -Force
}

# Copy release binaries
Copy-Item -Path $BuildReleaseDir -Destination $PortableStageDir -Recurse

# Create portable flag file (directs app data to local data_portable folder)
New-Item -ItemType File -Path (Join-Path $PortableStageDir "portable.flag") -Force | Out-Null

# Copy GPL-3.0 license
Copy-Item -Path (Join-Path $RepoRoot "LICENSE") -Destination $PortableStageDir -Force

# Compress to ZIP
Compress-Archive -Path "$PortableStageDir\*" -DestinationPath $PortableZipFile -CompressionLevel Optimal
Remove-Item -Path $PortableStageDir -Recurse -Force
Write-Host "  -> Portable ZIP created: $PortableZipFile" -ForegroundColor Green

# 4. Check and compile Inno Setup installer
Write-Host "[3/4] Checking Inno Setup compiler..." -ForegroundColor Yellow
$IsccCandidates = @(
    "iscc.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe"
)

$IsccExe = $null
foreach ($cand in $IsccCandidates) {
    if (Get-Command $cand -ErrorAction SilentlyContinue) {
        $IsccExe = $cand
        break
    } elseif (Test-Path $cand) {
        $IsccExe = $cand
        break
    }
}

if ($IsccExe -and (Test-Path $IssPath)) {
    Write-Host "  -> Found Inno Setup: $IsccExe" -ForegroundColor Gray
    & $IsccExe "/DMyAppVersion=$Version" $IssPath
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Inno Setup compilation failed with code: $LASTEXITCODE"
    } else {
        $SetupFile = Join-Path $DistDir "JuYing-v$Version-windows-x64-setup.exe"
        Write-Host "  -> Installer created: $SetupFile" -ForegroundColor Green
    }
} else {
    Write-Host "  [Note] Inno Setup 6 (ISCC.exe) not detected or iss not present. Portable ZIP is ready." -ForegroundColor DarkYellow
}

# 5. Generate SHA-256 Checksums
Write-Host "[4/4] Generating SHA-256 Checksums..." -ForegroundColor Yellow
$ChecksumFile = Join-Path $DistDir "SHA256SUMS.txt"
$Checksums = @()

Get-ChildItem -Path $DistDir -File | Where-Object { $_.Name -ne "SHA256SUMS.txt" } | ForEach-Object {
    $hash = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash.ToLower()
    $Checksums += "$hash  $($_.Name)"
}

$Checksums | Out-File -FilePath $ChecksumFile -Encoding utf8
Write-Host "  -> Checksums saved to: $ChecksumFile" -ForegroundColor Green

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Release Artifacts in dist/windows:" -ForegroundColor Cyan
Get-ChildItem -Path $DistDir | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
Write-Host "==================================================" -ForegroundColor Cyan
