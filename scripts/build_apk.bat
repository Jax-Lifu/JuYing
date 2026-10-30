@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ============================================================================
:: 聚映 (JuYing) 纯原生 Windows Batch APK 编译与归档脚本（零 PowerShell 依赖）
:: 位置: scripts\build_apk.bat（可在项目根目录或 scripts 目录下任意位置直接调用）
:: 自动将最终编译产物复制到 dist\<版本或日期子目录>\ 下
::
:: 用法:
::   scripts\build_apk.bat                    默认编译 Debug + Release 的 ARM64、ARMv7、通用包
::   scripts\build_apk.bat --debug            仅编译 Debug APK
::   scripts\build_apk.bat --release          仅编译 Release APK（含 R8 mapping.txt 归档）
::   scripts\build_apk.bat --debug --abi arm64-v8a  仅编译 ARM64 包
::   scripts\build_apk.bat --debug --abi universal  仅编译双架构通用包
::   scripts\build_apk.bat --by-version       按版本号分子目录存放: dist\v0.1.0\
::   scripts\build_apk.bat --by-date          按日期分子目录存放:   dist\20261024\
::   scripts\build_apk.bat --clean            编译前执行 clean
:: ============================================================================

for %%I in ("%~dp0..") do set "PROJECT_ROOT=%%~fI\"
cd /d "%PROJECT_ROOT%"

set "BUILD_TARGET=all"
set "DIST_MODE=version_date"
set "DO_CLEAN=0"
set "ABI=all"

:parse_args
if "%~1"=="" goto :args_done
if /i "%~1"=="--debug"           (set "BUILD_TARGET=debug" & shift & goto :parse_args)
if /i "%~1"=="-debug"            (set "BUILD_TARGET=debug" & shift & goto :parse_args)
if /i "%~1"=="debug"             (set "BUILD_TARGET=debug" & shift & goto :parse_args)
if /i "%~1"=="--release"         (set "BUILD_TARGET=release" & shift & goto :parse_args)
if /i "%~1"=="-release"          (set "BUILD_TARGET=release" & shift & goto :parse_args)
if /i "%~1"=="release"           (set "BUILD_TARGET=release" & shift & goto :parse_args)
if /i "%~1"=="-r"                (set "BUILD_TARGET=release" & shift & goto :parse_args)
if /i "%~1"=="--all"             (set "BUILD_TARGET=all" & shift & goto :parse_args)
if /i "%~1"=="all"               (set "BUILD_TARGET=all" & shift & goto :parse_args)
if /i "%~1"=="--by-version"      (set "DIST_MODE=version" & shift & goto :parse_args)
if /i "%~1"=="-v"                (set "DIST_MODE=version" & shift & goto :parse_args)
if /i "%~1"=="--by-date"         (set "DIST_MODE=date" & shift & goto :parse_args)
if /i "%~1"=="-d"                (set "DIST_MODE=date" & shift & goto :parse_args)
if /i "%~1"=="--by-version-date" (set "DIST_MODE=version_date" & shift & goto :parse_args)
if /i "%~1"=="--clean"           (set "DO_CLEAN=1" & shift & goto :parse_args)
if /i "%~1"=="--abi"             (set "ABI=%~2" & shift & shift & goto :parse_args)
shift
goto :parse_args
:args_done

if not "%ABI%"=="all" if not "%ABI%"=="universal" if not "%ABI%"=="arm64-v8a" if not "%ABI%"=="armeabi-v7a" (
    echo Invalid ABI: %ABI%. Use all, universal, arm64-v8a or armeabi-v7a.
    exit /b 1
)

set "GRADLE_TASKS="
if "%BUILD_TARGET%"=="debug" (
    set "GRADLE_TASKS=:app:assembleDebug"
) else if "%BUILD_TARGET%"=="release" (
    set "GRADLE_TASKS=:app:assembleRelease"
) else (
    set "GRADLE_TASKS=:app:assembleDebug :app:assembleRelease"
)

if "%ABI%"=="all" (
    set "BUILD_ABIS=arm64-v8a armeabi-v7a universal"
) else (
    set "BUILD_ABIS=%ABI%"
)
for %%A in (%BUILD_ABIS%) do (
    call :build_abi %%A
    if errorlevel 1 exit /b 1
)

:: Gradle assemble 为每轮 APK 和对应 mapping 精确归档，避免混入旧架构产物。
echo [2/2] 编译与归档完成！输出目录: %PROJECT_ROOT%dist\
endlocal
exit /b 0

:build_abi
set "CLEAN_TASK="
if "%DO_CLEAN%"=="1" set "CLEAN_TASK=clean"
set "ABI_PROPERTY="
if not "%~1"=="universal" set "ABI_PROPERTY=-PtargetAbi=%~1"
echo [1/2] 正在编译 APK ^(目标: %BUILD_TARGET%, ABI: %~1, 归档模式: %DIST_MODE%^)
call "%PROJECT_ROOT%gradlew.bat" %CLEAN_TASK% %GRADLE_TASKS% -PdistMode=%DIST_MODE% %ABI_PROPERTY%
if errorlevel 1 exit /b 1
set "DO_CLEAN=0"
exit /b 0
