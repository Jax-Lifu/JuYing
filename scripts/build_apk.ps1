<#
.SYNOPSIS
    聚映 (JuYing) PowerShell APK 编译与归档脚本（自动输出至 dist/<版本或日期子目录>/）
    位置: scripts\build_apk.ps1（可在项目根目录或 scripts 目录下任意位置直接调用）

.EXAMPLE
    .\scripts\build_apk.ps1                    # 默认编译 Debug + Release 的 ARM64、ARMv7、通用包
    .\scripts\build_apk.ps1 -Release           # 仅编译 Release APK（含 R8 mapping.txt）
    .\scripts\build_apk.ps1 -Debug             # 仅编译 Debug APK
    .\scripts\build_apk.ps1 -Debug -Abi arm64-v8a # 仅编译 ARM64 包
    .\scripts\build_apk.ps1 -Debug -Abi universal # 仅编译包含双架构的通用包
    .\scripts\build_apk.ps1 -ByVersion         # 归档至 dist\v0.1.0\
    .\scripts\build_apk.ps1 -ByDate            # 归档至 dist\20261024\
#>
param(
    [switch]$Debug,
    [switch]$Release,
    [switch]$All,
    [switch]$ByVersion,
    [switch]$ByDate,
    [switch]$Clean,
    [ValidateSet("all", "universal", "arm64-v8a", "armeabi-v7a", IgnoreCase = $false)]
    [string]$Abi = "all"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
Set-Location $ProjectRoot

function Ensure-Python311 {
    # 0. 最高优先级：当前项目根目录由 uv 创建的隔离虚拟环境 (.venv)
    $localVenvScripts = Join-Path $ProjectRoot ".venv\Scripts"
    $localVenvBin = Join-Path $ProjectRoot ".venv\bin"
    if (Test-Path (Join-Path $localVenvScripts "python.exe")) {
        $env:PATH = "$localVenvScripts;$env:PATH"
        return
    } elseif (Test-Path (Join-Path $localVenvBin "python")) {
        $env:PATH = "$localVenvBin;$env:PATH"
        return
    }

    # 尝试自动通过 uv 在项目下初始化 .venv
    $uv = Get-Command uv -ErrorAction SilentlyContinue
    if (-not $uv) {
        $setupScript = Join-Path $ScriptDir "setup_env.ps1"
        if (Test-Path $setupScript) {
            Write-Host "初次编译未检测到项目虚拟环境与 uv，正在自动运行初始化脚本..." -ForegroundColor Yellow
            & $setupScript
            if (Test-Path (Join-Path $localVenvScripts "python.exe")) {
                $env:PATH = "$localVenvScripts;$env:PATH"
                return
            }
        }
    } else {
        try {
            Write-Host "检测到项目尚未创建本地 .venv，正在通过 uv sync 自动初始化环境..." -ForegroundColor Yellow
            & $uv.Source sync 2>$null
            if (Test-Path (Join-Path $localVenvScripts "python.exe")) {
                $env:PATH = "$localVenvScripts;$env:PATH"
                return
            }
        } catch {}
    }

    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py) {
        try {
            $ver = (& $py.Source --version 2>&1) -join ""
            if ($ver -match "3\.11") { return }
        } catch {}
    }

    $candidates = @()
    $uv = Get-Command uv -ErrorAction SilentlyContinue
    if ($uv) {
        try {
            $uvPy = (& $uv.Source python find 3.11 2>$null)
            if ($uvPy -and (Test-Path $uvPy.Trim())) {
                $candidates += (Split-Path -Parent $uvPy.Trim())
            }
        } catch {}
    }
    $candidates += @(
        (Get-ChildItem -Path "$env:APPDATA\uv\python\cpython-3.11*" -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName),
        "$env:LOCALAPPDATA\Programs\Python\Python311",
        "C:\Program Files\Python311",
        "C:\Python311"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path (Join-Path $c "python.exe"))) {
            $env:PATH = "$c;$env:PATH"
            return
        }
    }
}
Ensure-Python311

$DistMode = "version_date"
if ($ByVersion) { $DistMode = "version" }
elseif ($ByDate) { $DistMode = "date" }

$Tasks = @()
if ($Clean) { $Tasks += "clean" }
if ($Debug -and -not $Release) {
    $Tasks += ":app:assembleDebug"
} elseif ($Release -and -not $Debug) {
    $Tasks += ":app:assembleRelease"
} else {
    $Tasks += ":app:assembleDebug"
    $Tasks += ":app:assembleRelease"
}

$BuildAbis = if ($Abi -eq "all") { @("arm64-v8a", "armeabi-v7a", "universal") } else { @($Abi) }
foreach ($BuildAbi in $BuildAbis) {
    $GradleProperties = @("-PdistMode=$DistMode")
    if ($BuildAbi -ne "universal") { $GradleProperties += "-PtargetAbi=$BuildAbi" }
    Write-Host "`n正在编译 APK (任务: $($Tasks -join ' '), ABI: $BuildAbi, 归档模式: $DistMode)..." -ForegroundColor Cyan
    & "$ProjectRoot\gradlew.bat" @Tasks @GradleProperties
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Gradle 编译失败 (ExitCode: $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    $Tasks = @($Tasks | Where-Object { $_ -ne "clean" })
}

Write-Host "`n编译与归档完成！输出目录: $ProjectRoot\dist（具体路径见上方 [Dist] 输出）" -ForegroundColor Green
