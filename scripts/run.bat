@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ============================================================================
:: 聚映 (JuYing) 纯原生 Windows Batch 编译、设备选择、安装与启动脚本（零 PowerShell 依赖）
:: 位置: scripts\run.bat（可在项目根目录或 scripts 目录下任意位置直接调用）
::
:: 用法:
::   scripts\run.bat                        编译 Debug，单设备直装 / 多设备交互选择
::   scripts\run.bat --all                  编译 Debug，安装并打开所有在线设备
::   scripts\run.bat --release              编译 Release，单设备直装 / 多设备交互选择
::   scripts\run.bat --release --all        编译 Release，安装并打开所有在线设备
::   scripts\run.bat --device qytech6666    指定设备序列号安装
::   scripts\run.bat --skip-build --all     跳过编译，直接安装最新 APK 到所有设备
:: ============================================================================

for %%I in ("%~dp0..") do set "PROJECT_ROOT=%%~fI\"
cd /d "%PROJECT_ROOT%"

set "APP_PACKAGE=com.flytech.juying"
set "MAIN_ACTIVITY=com.flytech.juying/.MainActivity"

set "BUILD_TYPE=debug"
set "GRADLE_TASK=:app:assembleDebug"
set "INSTALL_ALL=0"
set "SKIP_BUILD=0"
set "TARGET_SERIAL="

:parse_args
if "%~1"=="" goto :args_done
if /i "%~1"=="--release"    (set "BUILD_TYPE=release" & set "GRADLE_TASK=:app:assembleRelease" & shift & goto :parse_args)
if /i "%~1"=="-release"     (set "BUILD_TYPE=release" & set "GRADLE_TASK=:app:assembleRelease" & shift & goto :parse_args)
if /i "%~1"=="release"      (set "BUILD_TYPE=release" & set "GRADLE_TASK=:app:assembleRelease" & shift & goto :parse_args)
if /i "%~1"=="-r"           (set "BUILD_TYPE=release" & set "GRADLE_TASK=:app:assembleRelease" & shift & goto :parse_args)
if /i "%~1"=="--all"        (set "INSTALL_ALL=1" & shift & goto :parse_args)
if /i "%~1"=="-all"         (set "INSTALL_ALL=1" & shift & goto :parse_args)
if /i "%~1"=="all"          (set "INSTALL_ALL=1" & shift & goto :parse_args)
if /i "%~1"=="-a"           (set "INSTALL_ALL=1" & shift & goto :parse_args)
if /i "%~1"=="--skip-build" (set "SKIP_BUILD=1" & shift & goto :parse_args)
if /i "%~1"=="-skipbuild"   (set "SKIP_BUILD=1" & shift & goto :parse_args)
if /i "%~1"=="--device"     (set "TARGET_SERIAL=%~2" & shift & shift & goto :parse_args)
if /i "%~1"=="-device"      (set "TARGET_SERIAL=%~2" & shift & shift & goto :parse_args)
if /i "%~1"=="-s"           (set "TARGET_SERIAL=%~2" & shift & shift & goto :parse_args)
shift
goto :parse_args
:args_done

:: 1. 查找 adb.exe（不依赖 PowerShell）
set "ADB_EXE="
if exist "%PROJECT_ROOT%local.properties" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%PROJECT_ROOT%local.properties") do (
        if "%%A"=="sdk.dir" (
            set "RAW_SDK=%%B"
            set "RAW_SDK=!RAW_SDK:\:=:!"
            set "RAW_SDK=!RAW_SDK:\\=\!"
            if exist "!RAW_SDK!\platform-tools\adb.exe" set "ADB_EXE=!RAW_SDK!\platform-tools\adb.exe"
        )
    )
)
if "!ADB_EXE!"=="" if defined ANDROID_HOME if exist "%ANDROID_HOME%\platform-tools\adb.exe" set "ADB_EXE=%ANDROID_HOME%\platform-tools\adb.exe"
if "!ADB_EXE!"=="" if defined ANDROID_SDK_ROOT if exist "%ANDROID_SDK_ROOT%\platform-tools\adb.exe" set "ADB_EXE=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
if "!ADB_EXE!"=="" (
    for /f "delims=" %%P in ('where adb 2^>nul') do if "!ADB_EXE!"=="" set "ADB_EXE=%%P"
)
if "!ADB_EXE!"=="" (
    echo [错误] 未找到 adb.exe，请检查 local.properties 中的 sdk.dir 或 ANDROID_HOME 环境变量。
    exit /b 1
)

:: 2. 执行 Gradle 编译
if "%SKIP_BUILD%"=="0" (
    echo.
    echo [1/3] 正在编译 JuYing ^(%BUILD_TYPE%^) -^> %GRADLE_TASK% ...
    call "%PROJECT_ROOT%gradlew.bat" %GRADLE_TASK%
    if errorlevel 1 (
        echo [错误] Gradle 编译失败。
        exit /b 1
    )
) else (
    echo.
    echo [1/3] 已跳过编译 ^(--skip-build^)，直接查找最新 APK...
)

set "APK_DIR=%PROJECT_ROOT%app\build\outputs\apk\%BUILD_TYPE%"
set "APK_FILE="
if exist "%APK_DIR%" (
    for /f "delims=" %%F in ('dir /b /a-d /o-d "%APK_DIR%\*.apk" 2^>nul') do (
        if "!APK_FILE!"=="" set "APK_FILE=%APK_DIR%\%%F" & set "APK_NAME=%%F"
    )
)
if "!APK_FILE!"=="" (
    echo [错误] 未在 %APK_DIR% 下找到 APK 文件。
    exit /b 1
)
echo       产物文件: !APK_NAME!

:: 3. 扫描在线 ADB 设备（使用 <nul 防止 adb 吞掉标准输入）
echo.
echo [2/3] 正在扫描已连接的 ADB 设备...
set /a DEV_COUNT=0
for /f "skip=1 tokens=1,2" %%S in ('"%ADB_EXE%" devices') do (
    if "%%T"=="device" (
        set /a DEV_COUNT+=1
        set "DEV_SERIAL_!DEV_COUNT!=%%S"
        set "MODEL="
        set "AVER="
        for /f "delims=" %%M in ('"%ADB_EXE%" -s %%S shell getprop ro.product.model ^<nul 2^>nul') do set "MODEL=%%M"
        for /f "delims=" %%V in ('"%ADB_EXE%" -s %%S shell getprop ro.build.version.release ^<nul 2^>nul') do set "AVER=%%V"
        for /f "delims=" %%M in ("!MODEL!") do set "MODEL=%%M"
        for /f "delims=" %%V in ("!AVER!") do set "AVER=%%V"
        set "DEV_MODEL_!DEV_COUNT!=!MODEL!"
        set "DEV_AVER_!DEV_COUNT!=Android !AVER!"
    )
)

if !DEV_COUNT! EQU 0 (
    echo [错误] 未检测到任何在线的 Android 设备 ^(请确认 adb devices 状态为 device^)。
    exit /b 1
)

:: 4. 选择设备
set "SELECTED_INDICES="
if not "!TARGET_SERIAL!"=="" (
    for /l %%I in (1,1,!DEV_COUNT!) do (
        if /i "!DEV_SERIAL_%%I!"=="!TARGET_SERIAL!" set "SELECTED_INDICES=%%I"
    )
    if "!SELECTED_INDICES!"=="" (
        echo [错误] 未找到序列号为 '!TARGET_SERIAL!' 的在线设备。
        exit /b 1
    )
    echo       已指定设备: !TARGET_SERIAL!
    goto :install_loop
)

if "%INSTALL_ALL%"=="1" (
    for /l %%I in (1,1,!DEV_COUNT!) do set "SELECTED_INDICES=!SELECTED_INDICES! %%I"
    echo       已开启全部安装 ^(--all^)，共 !DEV_COUNT! 台在线设备。
    goto :install_loop
)

if !DEV_COUNT! EQU 1 (
    set "SELECTED_INDICES=1"
    echo       仅检测到 1 台设备，自动选择: !DEV_SERIAL_1! ^(!DEV_MODEL_1!, !DEV_AVER_1!^)
    goto :install_loop
)

echo       检测到 !DEV_COUNT! 台在线设备:
for /l %%I in (1,1,!DEV_COUNT!) do (
    echo         [%%I] !DEV_SERIAL_%%I!  ^(!DEV_MODEL_%%I!, !DEV_AVER_%%I!^)
)
echo         [A] 全部设备安装并启动 ^(All^)

set /a ASK_RETRIES=0
:ask_choice
echo.
set "USER_CHOICE="
set /p "USER_CHOICE=Please select device (1-!DEV_COUNT!, comma/space separated, or A for All): "
if "!USER_CHOICE!"=="" (
    set /a ASK_RETRIES+=1
    if !ASK_RETRIES! GEQ 3 (
        echo [错误] 未收到有效输入，已退出。
        exit /b 1
    )
    goto :ask_choice
)
if /i "!USER_CHOICE!"=="A" (
    for /l %%I in (1,1,!DEV_COUNT!) do set "SELECTED_INDICES=!SELECTED_INDICES! %%I"
    goto :install_loop
)
if /i "!USER_CHOICE!"=="ALL" (
    for /l %%I in (1,1,!DEV_COUNT!) do set "SELECTED_INDICES=!SELECTED_INDICES! %%I"
    goto :install_loop
)
if "!USER_CHOICE!"=="0" (
    for /l %%I in (1,1,!DEV_COUNT!) do set "SELECTED_INDICES=!SELECTED_INDICES! %%I"
    goto :install_loop
)

set "USER_CHOICE=!USER_CHOICE:,= !"
for %%C in (!USER_CHOICE!) do (
    set /a IDX=%%C 2>nul
    if !IDX! GEQ 1 if !IDX! LEQ !DEV_COUNT! (
        set "SELECTED_INDICES=!SELECTED_INDICES! !IDX!"
    )
)
if "!SELECTED_INDICES!"=="" (
    set /a ASK_RETRIES+=1
    if !ASK_RETRIES! GEQ 3 (
        echo [错误] 输入无效次数过多，已退出。
        exit /b 1
    )
    echo [错误] 输入无效，请重新输入。
    goto :ask_choice
)

:: 5. 安装并启动
:install_loop
echo.
echo [3/3] 开始安装并打开应用 ^(!APK_NAME!^)...
for %%I in (!SELECTED_INDICES!) do (
    set "CUR_SERIAL=!DEV_SERIAL_%%I!"
    set "CUR_MODEL=!DEV_MODEL_%%I!"
    echo.
    echo   --^> 目标设备: !CUR_SERIAL! ^(!CUR_MODEL!^)
    "%ADB_EXE%" -s !CUR_SERIAL! install -r "%APK_FILE%" <nul > "%TEMP%\juying_install.log" 2>&1
    findstr /i "Success" "%TEMP%\juying_install.log" >nul
    if errorlevel 1 (
        findstr /i "INSTALL_FAILED_VERSION_DOWNGRADE INSTALL_FAILED_UPDATE_INCOMPATIBLE" "%TEMP%\juying_install.log" >nul
        if not errorlevel 1 (
            echo       检测到旧版签名或版本号冲突，正在卸载旧版后重装...
            "%ADB_EXE%" -s !CUR_SERIAL! uninstall %APP_PACKAGE% <nul >nul 2>&1
            "%ADB_EXE%" -s !CUR_SERIAL! install -r "%APK_FILE%" <nul > "%TEMP%\juying_install.log" 2>&1
        )
    )
    findstr /i "Success" "%TEMP%\juying_install.log" >nul
    if errorlevel 1 (
        echo       [失败] 安装到 !CUR_SERIAL! 失败:
        type "%TEMP%\juying_install.log"
    ) else (
        echo       [成功] APK 安装完成，正在启动 %MAIN_ACTIVITY% ...
        "%ADB_EXE%" -s !CUR_SERIAL! shell am force-stop %APP_PACKAGE% <nul >nul 2>&1
        "%ADB_EXE%" -s !CUR_SERIAL! shell am start -W -n %MAIN_ACTIVITY% <nul | findstr /i "Status TotalTime"
    )
)

echo.
echo 全部任务执行完毕！
endlocal
exit /b 0
