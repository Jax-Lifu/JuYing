<#
.SYNOPSIS
    聚映 (JuYing) 开发环境一键初始化脚本 (PowerShell)
    作用: 检查并自动安装 uv、自动配置 Python 3.11，并通过 uv sync 建立项目隔离虚拟环境 (.venv)
    用法: .\scripts\setup_env.ps1
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
Set-Location $ProjectRoot

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "        聚映 (JuYing) 独立开发环境初始化 (uv + Python 3.11)        " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. 检查或安装 uv
$uvCmd = Get-Command uv -ErrorAction SilentlyContinue
if (-not $uvCmd) {
    # 检查默认安装路径是否已存在
    $defaultUv = Join-Path $env:USERPROFILE ".cargo\bin\uv.exe"
    $localUv = Join-Path $env:LOCALAPPDATA "bin\uv.exe"
    if (Test-Path $defaultUv) {
        $env:PATH = "$(Split-Path $defaultUv);$env:PATH"
        $uvCmd = Get-Command uv -ErrorAction SilentlyContinue
    } elseif (Test-Path $localUv) {
        $env:PATH = "$(Split-Path $localUv);$env:PATH"
        $uvCmd = Get-Command uv -ErrorAction SilentlyContinue
    }
}

if (-not $uvCmd) {
    Write-Host "`n[1/3] 未检测到 uv，正在通过官方脚本自动安装 uv..." -ForegroundColor Yellow
    try {
        powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
        $defaultUvDir = Join-Path $env:USERPROFILE ".cargo\bin"
        $localUvDir = Join-Path $env:LOCALAPPDATA "bin"
        if (Test-Path (Join-Path $defaultUvDir "uv.exe")) {
            $env:PATH = "$defaultUvDir;$env:PATH"
        } elseif (Test-Path (Join-Path $localUvDir "uv.exe")) {
            $env:PATH = "$localUvDir;$env:PATH"
        }
        $uvCmd = Get-Command uv -ErrorAction Stop
        Write-Host "  -> uv 安装成功！" -ForegroundColor Green
    } catch {
        Write-Error "自动安装 uv 失败，请访问 https://docs.astral.sh/uv/ 手动安装后重试。"
        exit 1
    }
} else {
    Write-Host "`n[1/3] 检测到 uv 已安装: $($uvCmd.Source)" -ForegroundColor Green
}

# 2. 确保 Python 3.11 存在
Write-Host "`n[2/3] 检查 Python 3.11 运行时..." -ForegroundColor Yellow
try {
    & uv python install 3.11
    Write-Host "  -> Python 3.11 运行时就绪！" -ForegroundColor Green
} catch {
    Write-Error "通过 uv 下载 Python 3.11 失败，请检查网络连接。"
    exit 1
}

# 3. 在项目根目录下通过 uv sync 同步并锁定虚拟环境 (.venv)
$VenvDir = Join-Path $ProjectRoot ".venv"
Write-Host "`n[3/3] 正在通过 uv sync 同步并锁定本地环境与依赖..." -ForegroundColor Yellow

& uv sync
if ($LASTEXITCODE -ne 0) {
    Write-Error "通过 uv sync 创建并同步虚拟环境失败。"
    exit $LASTEXITCODE
}

$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
if (-not (Test-Path $VenvPython)) {
    $VenvPython = Join-Path $VenvDir "bin\python"
}

if (Test-Path $VenvPython) {
    $pyVer = (& $VenvPython --version 2>&1) -join ""
    Write-Host "`n============================================================" -ForegroundColor Green
    Write-Host "  环境初始化完成！" -ForegroundColor Green
    Write-Host "  项目虚拟环境路径: $VenvDir" -ForegroundColor White
    Write-Host "  解释器版本: $pyVer" -ForegroundColor White
    Write-Host "  已安装本地依赖: requests, beautifulsoup4, lxml" -ForegroundColor White
    Write-Host "  后续编译无需任何额外配置，脚本与 Gradle 会自动优先使用此环境。" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Green
} else {
    Write-Error "虚拟环境创建后未找到 python 可执行文件: $VenvPython"
    exit 1
}
