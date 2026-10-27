<#
.SYNOPSIS
    聚映 (JuYing) PowerShell APK 编译与归档脚本（自动输出至 dist/<版本或日期子目录>/）
    位置: scripts\build_apk.ps1（可在项目根目录或 scripts 目录下任意位置直接调用）

.EXAMPLE
    .\scripts\build_apk.ps1                    # 默认编译 Debug + Release 并归档至 dist\v0.1.0_20261024\
    .\scripts\build_apk.ps1 -Release           # 仅编译 Release APK（含 R8 mapping.txt）
    .\scripts\build_apk.ps1 -Debug             # 仅编译 Debug APK
    .\scripts\build_apk.ps1 -ByVersion         # 归档至 dist\v0.1.0\
    .\scripts\build_apk.ps1 -ByDate            # 归档至 dist\20261024\
#>
param(
    [switch]$Debug,
    [switch]$Release,
    [switch]$All,
    [switch]$ByVersion,
    [switch]$ByDate,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
Set-Location $ProjectRoot

$DistMode = "version_date"
if ($ByVersion) { $DistMode = "version" }
elseif ($ByDate) { $DistMode = "date" }

$Tasks = @()
$Variants = @()
if ($Clean) { $Tasks += "clean" }
if ($Debug -and -not $Release) {
    $Tasks += ":app:assembleDebug"
    $Variants = @("debug")
} elseif ($Release -and -not $Debug) {
    $Tasks += ":app:assembleRelease"
    $Variants = @("release")
} else {
    $Tasks += ":app:assembleDebug"
    $Tasks += ":app:assembleRelease"
    $Variants = @("debug", "release")
}

Write-Host "`n[1/2] 正在编译 APK (任务: $($Tasks -join ' '), 归档模式: $DistMode)..." -ForegroundColor Cyan
& "$ProjectRoot\gradlew.bat" @Tasks "-PdistMode=$DistMode"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Gradle 编译失败 (ExitCode: $LASTEXITCODE)"
    exit $LASTEXITCODE
}

$AppVer = "0.1.0"
$BuildDate = (Get-Date -Format "yyyyMMdd")
foreach ($v in $Variants) {
    $apk = Get-ChildItem -Path "$ProjectRoot\app\build\outputs\apk\$v" -Filter "*.apk" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($apk) {
        $parts = $apk.BaseName -split "_"
        if ($parts.Count -ge 4) {
            $AppVer = $parts[2]
            $BuildDate = $parts[3]
        }
    }
}

$SubDir = switch ($DistMode) {
    "version" { "v$AppVer" }
    "date"    { "$BuildDate" }
    default   { "v${AppVer}_${BuildDate}" }
}

$TargetDist = Join-Path $ProjectRoot "dist\$SubDir"
New-Item -ItemType Directory -Path $TargetDist -Force | Out-Null

foreach ($v in $Variants) {
    $apk = Get-ChildItem -Path "$ProjectRoot\app\build\outputs\apk\$v" -Filter "*.apk" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($apk) {
        Copy-Item -Path $apk.FullName -Destination (Join-Path $TargetDist $apk.Name) -Force
        if ($v -eq "release") {
            $mapping = Join-Path $ProjectRoot "app\build\outputs\mapping\release\mapping.txt"
            if (Test-Path $mapping) {
                Copy-Item -Path $mapping -Destination (Join-Path $TargetDist "$($apk.BaseName)_mapping.txt") -Force
            }
        }
    }
}

Write-Host "`n[2/2] 编译与归档完成！输出目录: $TargetDist" -ForegroundColor Green
Get-ChildItem -Path $TargetDist -File | ForEach-Object {
    $sizeMb = [Math]::Round($_.Length / 1MB, 2)
    Write-Host ("  - {0,-45} ({1} MB)" -f $_.Name, $sizeMb) -ForegroundColor White
}
