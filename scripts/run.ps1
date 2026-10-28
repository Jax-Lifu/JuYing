<#
.SYNOPSIS
    聚映 (JuYing) 一键编译、设备选择、安装与启动脚本 (PowerShell)
    位置: scripts\run.ps1（可在项目根目录或 scripts 目录下任意位置直接调用）

.EXAMPLE
    .\scripts\run.ps1                        # 编译 Debug，单设备直装 / 多设备交互选择
    .\scripts\run.ps1 -All                   # 编译 Debug，安装并打开所有已连接设备
    .\scripts\run.ps1 -Release               # 编译 Release，单设备直装 / 多设备交互选择
    .\scripts\run.ps1 -Release -All          # 编译 Release，安装并打开所有已连接设备
    .\scripts\run.ps1 -Device qytech6666     # 指定设备序列号安装
    .\scripts\run.ps1 -SkipBuild -All        # 跳过编译，直接安装最新已编译的 APK 到全部设备
#>
param(
    [switch]$Release,
    [switch]$All,
    [string]$Device = "",
    [switch]$SkipBuild
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
            Write-Host "初次运行未检测到项目虚拟环境与 uv，正在自动运行初始化脚本..." -ForegroundColor Yellow
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

$AppPackage = "com.flytech.juying"
$MainActivity = "$AppPackage/.MainActivity"
$BuildType = if ($Release) { "release" } else { "debug" }
$GradleTask = if ($Release) { ":app:assembleRelease" } else { ":app:assembleDebug" }

function Find-AdbPath {
    $localProps = Join-Path $ProjectRoot "local.properties"
    if (Test-Path $localProps) {
        $line = Get-Content $localProps | Where-Object { $_ -match "^sdk\.dir=" } | Select-Object -First 1
        if ($line) {
            $sdkDir = ($line -replace "^sdk\.dir=", "").Replace("\:", ":").Replace("\\", "\").Trim()
            $adbCandidate = Join-Path $sdkDir "platform-tools\adb.exe"
            if (Test-Path $adbCandidate) { return $adbCandidate }
        }
    }
    foreach ($envVar in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)) {
        if ($envVar) {
            $adbCandidate = Join-Path $envVar "platform-tools\adb.exe"
            if (Test-Path $adbCandidate) { return $adbCandidate }
        }
    }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "未找到 adb.exe，请检查 local.properties 中的 sdk.dir 或配置 ANDROID_HOME。"
}

$adb = Find-AdbPath

if (-not $SkipBuild) {
    Write-Host "`n[1/3] 正在编译 JuYing ($BuildType) -> $GradleTask ..." -ForegroundColor Cyan
    & "$ProjectRoot\gradlew.bat" $GradleTask
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Gradle 编译失败 (ExitCode: $LASTEXITCODE)"
        exit $LASTEXITCODE
    }
} else {
    Write-Host "`n[1/3] 已跳过编译 (-SkipBuild)，直接查找最新 APK..." -ForegroundColor Yellow
}

$apkDir = Join-Path $ProjectRoot "app\build\outputs\apk\$BuildType"
if (-not (Test-Path $apkDir)) {
    Write-Error "APK 输出目录不存在: $apkDir"
    exit 1
}
$apkFile = Get-ChildItem -Path $apkDir -Filter "*.apk" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $apkFile) {
    Write-Error "未在 $apkDir 下找到任何 .apk 文件"
    exit 1
}

$apkSizeMb = [Math]::Round($apkFile.Length / 1MB, 2)
Write-Host "      产物文件: $($apkFile.Name) ($apkSizeMb MB)" -ForegroundColor Green

Write-Host "`n[2/3] 正在扫描已连接的 ADB 设备..." -ForegroundColor Cyan
$rawLines = & $adb devices
$devices = @()

foreach ($line in $rawLines) {
    if ($line -match "^(\S+)\s+device$") {
        $serial = $Matches[1]
        $model = (& $adb -s $serial shell getprop ro.product.model 2>$null | Out-String).Trim()
        $androidVer = (& $adb -s $serial shell getprop ro.build.version.release 2>$null | Out-String).Trim()
        $sdkVer = (& $adb -s $serial shell getprop ro.build.version.sdk 2>$null | Out-String).Trim()
        $abi = (& $adb -s $serial shell getprop ro.product.cpu.abi 2>$null | Out-String).Trim()
        $devices += [PSCustomObject]@{
            Serial     = $serial
            Model      = if ($model) { $model } else { "Unknown" }
            AndroidVer = if ($androidVer) { "Android $androidVer (API $sdkVer)" } else { "Unknown" }
            Abi        = if ($abi) { $abi } else { "Unknown" }
        }
    }
}

if ($devices.Count -eq 0) {
    Write-Error "未检测到任何在线的 Android 设备（请确认 adb devices 状态为 device）。"
    exit 1
}

$targetDevices = @()

if (-not [string]::IsNullOrWhiteSpace($Device)) {
    $matched = $devices | Where-Object { $_.Serial -eq $Device }
    if (-not $matched) {
        $available = ($devices | ForEach-Object { "$($_.Serial) ($($_.Model))" }) -join ", "
        Write-Error "未找到序列号为 '$Device' 的在线设备。当前在线设备: $available"
        exit 1
    }
    $targetDevices = @($matched)
    Write-Host "      已指定目标设备: $($matched.Serial) ($($matched.Model))" -ForegroundColor Green
}
elseif ($All) {
    $targetDevices = $devices
    Write-Host "      已开启全部安装 (-All)，共选中 $($targetDevices.Count) 台设备。" -ForegroundColor Green
}
elseif ($devices.Count -eq 1) {
    $targetDevices = $devices
    $d = $devices[0]
    Write-Host "      仅检测到 1 台设备，自动选择: $($d.Serial) [$($d.Model) | $($d.AndroidVer) | $($d.Abi)]" -ForegroundColor Green
}
else {
    Write-Host "      检测到 $($devices.Count) 台在线设备：" -ForegroundColor Yellow
    for ($i = 0; $i -lt $devices.Count; $i++) {
        $d = $devices[$i]
        Write-Host ("        [{0}] {1,-18} | {2,-12} | {3,-20} | {4}" -f ($i + 1), $d.Serial, $d.Model, $d.AndroidVer, $d.Abi) -ForegroundColor White
    }
    Write-Host "        [A] 全部设备安装并启动 (All)" -ForegroundColor Green

    while ($targetDevices.Count -eq 0) {
        $inputStr = Read-Host "`n请选择设备编号 (输入单个如 1，多个用逗号分隔如 1,2，或输入 A 全部安装)"
        $trimmed = $inputStr.Trim()
        if ($trimmed -match "^(a|all|0|\*)$") {
            $targetDevices = $devices
            break
        }
        $parts = $trimmed -split "[,\s]+" | Where-Object { $_ -ne "" }
        $selected = @()
        $valid = $true
        foreach ($p in $parts) {
            $idx = 0
            if ([int]::TryParse($p, [ref]$idx) -and $idx -ge 1 -and $idx -le $devices.Count) {
                $selected += $devices[$idx - 1]
            } else {
                $valid = $false
                break
            }
        }
        if ($valid -and $selected.Count -gt 0) {
            $targetDevices = $selected | Select-Object -Unique
        } else {
            Write-Host "输入无效，请输入 1~$($devices.Count) 的数字或 A。" -ForegroundColor Red
        }
    }
}

Write-Host "`n[3/3] 开始安装并打开应用 ($($apkFile.Name))..." -ForegroundColor Cyan
$successCount = 0

foreach ($dev in $targetDevices) {
    Write-Host "`n  --> 目标设备: $($dev.Serial) ($($dev.Model), $($dev.AndroidVer))" -ForegroundColor White
    $installOut = & $adb -s $dev.Serial install -r $apkFile.FullName 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $installOut -notmatch "Success") {
        if ($installOut -match "INSTALL_FAILED_VERSION_DOWNGRADE|INSTALL_FAILED_UPDATE_INCOMPATIBLE") {
            Write-Host "      检测到旧版签名或版本号冲突，正在卸载旧版后重试..." -ForegroundColor Yellow
            & $adb -s $dev.Serial uninstall $AppPackage 2>&1 | Out-Null
            $installOut = & $adb -s $dev.Serial install -r $apkFile.FullName 2>&1 | Out-String
        }
    }

    if ($installOut -match "Success") {
        Write-Host "      [成功] APK 安装完成，正在启动 $MainActivity ..." -ForegroundColor Green
        & $adb -s $dev.Serial shell am force-stop $AppPackage 2>$null
        $startOut = & $adb -s $dev.Serial shell am start -W -n $MainActivity 2>&1 | Out-String
        $totalTime = if ($startOut -match "TotalTime:\s*(\d+)") { "$($Matches[1]) ms" } else { "OK" }
        Write-Host "      [已启动] $MainActivity (冷启动耗时: $totalTime)" -ForegroundColor Green
        $successCount++
    } else {
        Write-Host "      [失败] 安装到 $($dev.Serial) 失败:`n$installOut" -ForegroundColor Red
    }
}

Write-Host "`n全部任务执行完毕：成功安装并打开 $successCount / $($targetDevices.Count) 台设备。" -ForegroundColor Cyan
