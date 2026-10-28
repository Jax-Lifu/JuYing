@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ============================================================================
:: 聚映 (JuYing) 开发环境一键初始化批处理 (调用 PowerShell 安装 uv 并配置 Python 3.11)
:: 用法: 双击本文件，或在终端执行 scripts\setup_env.bat
:: ============================================================================

for %%I in ("%~dp0..") do set "PROJECT_ROOT=%%~fI\"
cd /d "%PROJECT_ROOT%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_env.ps1"
if %ERRORLEVEL% neq 0 (
    echo.
    echo [错误] 环境初始化未完成，请检查上方日志。
    exit /b %ERRORLEVEL%
)

echo.
echo [提示] 环境初始化成功，您可以直接运行 scripts\build_apk.bat 或 scripts\build_apk.ps1 开始编译。
