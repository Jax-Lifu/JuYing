@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ============================================================================
:: 聚映 (JuYing) 纯原生 Windows Batch APK 编译与归档脚本（零 PowerShell 依赖）
:: 位置: scripts\build_apk.bat（可在项目根目录或 scripts 目录下任意位置直接调用）
:: 自动将最终编译产物复制到 dist\<版本或日期子目录>\ 下
::
:: 用法:
::   scripts\build_apk.bat                    默认编译 Debug + Release 并归档至 dist\v{版本}_{日期}\
::   scripts\build_apk.bat --debug            仅编译 Debug APK
::   scripts\build_apk.bat --release          仅编译 Release APK（含 R8 mapping.txt 归档）
::   scripts\build_apk.bat --by-version       按版本号分子目录存放: dist\v0.1.0\
::   scripts\build_apk.bat --by-date          按日期分子目录存放:   dist\20261024\
::   scripts\build_apk.bat --clean            编译前执行 clean
:: ============================================================================

for %%I in ("%~dp0..") do set "PROJECT_ROOT=%%~fI\"
cd /d "%PROJECT_ROOT%"

set "BUILD_TARGET=all"
set "DIST_MODE=version_date"
set "DO_CLEAN=0"

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
shift
goto :parse_args
:args_done

set "GRADLE_TASKS="
if "%DO_CLEAN%"=="1" set "GRADLE_TASKS=clean "
if "%BUILD_TARGET%"=="debug" (
    set "GRADLE_TASKS=%GRADLE_TASKS%:app:assembleDebug"
    set "VARIANTS=debug"
) else if "%BUILD_TARGET%"=="release" (
    set "GRADLE_TASKS=%GRADLE_TASKS%:app:assembleRelease"
    set "VARIANTS=release"
) else (
    set "GRADLE_TASKS=%GRADLE_TASKS%:app:assembleDebug :app:assembleRelease"
    set "VARIANTS=debug release"
)

echo.
echo ============================================================================
echo [1/2] 正在编译 APK ^(目标: %BUILD_TARGET%, 归档模式: %DIST_MODE%^)
echo       执行任务: %GRADLE_TASKS% -PdistMode=%DIST_MODE%
echo ============================================================================
call "%PROJECT_ROOT%gradlew.bat" %GRADLE_TASKS% -PdistMode=%DIST_MODE%
if errorlevel 1 (
    echo [错误] Gradle 编译失败！
    exit /b 1
)

:: 从已生成的 APK 文件名提取版本号与日期（JuYing_{debug|release}_{version}_{date}.apk）
set "APP_VER=0.1.0"
set "BUILD_DATE="
for %%V in (%VARIANTS%) do (
    for /f "delims=" %%F in ('dir /b /a-d /o-d "%PROJECT_ROOT%app\build\outputs\apk\%%V\*.apk" 2^>nul') do (
        for /f "tokens=1,2,3,4 delims=_" %%A in ("%%~nF") do (
            if not "%%C"=="" set "APP_VER=%%C"
            if not "%%D"=="" set "BUILD_DATE=%%D"
        )
    )
)

if "%DIST_MODE%"=="version" (
    set "SUB_DIR=v!APP_VER!"
) else if "%DIST_MODE%"=="date" (
    set "SUB_DIR=!BUILD_DATE!"
) else (
    set "SUB_DIR=v!APP_VER!_!BUILD_DATE!"
)

set "TARGET_DIST=%PROJECT_ROOT%dist\!SUB_DIR!"
if not exist "!TARGET_DIST!" mkdir "!TARGET_DIST!"

:: 即使 Gradle UP-TO-DATE 也确保产物完整同步到目标 dist 子目录
for %%V in (%VARIANTS%) do (
    for /f "delims=" %%F in ('dir /b /a-d /o-d "%PROJECT_ROOT%app\build\outputs\apk\%%V\*.apk" 2^>nul') do (
        copy /y "%PROJECT_ROOT%app\build\outputs\apk\%%V\%%F" "!TARGET_DIST!\%%F" >nul
        if /i "%%V"=="release" (
            if exist "%PROJECT_ROOT%app\build\outputs\mapping\release\mapping.txt" (
                copy /y "%PROJECT_ROOT%app\build\outputs\mapping\release\mapping.txt" "!TARGET_DIST!\%%~nF_mapping.txt" >nul
            )
        )
    )
)

echo.
echo ============================================================================
echo [2/2] 编译与归档完成！输出目录: !TARGET_DIST!
echo ============================================================================
for %%F in ("!TARGET_DIST!\*.*") do (
    echo   - %%~nxF   ^(%%~zF 字节^)
)
echo.
endlocal
exit /b 0
