<#
.SYNOPSIS
    聚映 (JuYing) Windows 平台生产级发布自动化构建脚本。
    同时产出便携版 Zip (Portable) 与 Inno Setup 安装包 (.exe)。
    遵循 ADR-009 (GPL-3.0) 与《聚映项目指导文档 v0.2》第 3.3 节、10.3 节与 Q9 规范。
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
Write-Host " 聚映 (JuYing) Windows x64 发布包自动化构建 (v$Version)" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. 创建发布目录
if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
}

# 2. 执行 Flutter Windows Release 编译
if (-not $SkipBuild) {
    Write-Host "[1/4] 正在执行 Flutter Windows Release 构建..." -ForegroundColor Yellow
    Push-Location $AppDir
    try {
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter windows release 构建失败，退出码: $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "[1/4] 跳过编译步骤，直接使用已有构建产物..." -ForegroundColor DarkYellow
}

if (-not (Test-Path $BuildReleaseDir)) {
    throw "未找到构建输出目录: $BuildReleaseDir"
}

# 3. 组装便携版 (Portable Zip)
Write-Host "[2/4] 正在打包便携版 (Portable ZIP)..." -ForegroundColor Yellow
$PortableStageName = "JuYing-v$Version-windows-x64-portable"
$PortableStageDir = Join-Path $DistDir $PortableStageName
$PortableZipFile = Join-Path $DistDir "$PortableStageName.zip"

if (Test-Path $PortableStageDir) {
    Remove-Item -Path $PortableStageDir -Recurse -Force
}
if (Test-Path $PortableZipFile) {
    Remove-Item -Path $PortableZipFile -Force
}

# 复制发布二进制文件
Copy-Item -Path $BuildReleaseDir -Destination $PortableStageDir -Recurse
# 注入便携模式标识文件 (使应用数据重定向至本地 data_portable 目录)
New-Item -ItemType File -Path (Join-Path $PortableStageDir "portable.flag") -Force | Out-Null
# 注入 GPL-3.0 许可证声明
Copy-Item -Path (Join-Path $RepoRoot "LICENSE") -Destination $PortableStageDir -Force

# 压缩为 ZIP
Compress-Archive -Path "$PortableStageDir\*" -DestinationPath $PortableZipFile -CompressionLevel Optimal
Remove-Item -Path $PortableStageDir -Recurse -Force
Write-Host "  -> 便携版已生成: $PortableZipFile" -ForegroundColor Green

# 4. 编译 Inno Setup 安装包
Write-Host "[3/4] 正在检查并编译 Inno Setup 安装包..." -ForegroundColor Yellow
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

if ($IsccExe) {
    Write-Host "  -> 找到 Inno Setup 编译器: $IsccExe" -ForegroundColor Gray
    & $IsccExe "/DMyAppVersion=$Version" $IssPath
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Inno Setup 编译失败，退出码: $LASTEXITCODE"
    } else {
        $SetupFile = Join-Path $DistDir "JuYing-v$Version-windows-x64-setup.exe"
        Write-Host "  -> 安装包已生成: $SetupFile" -ForegroundColor Green
    }
} else {
    Write-Host "  [提示] 未在系统中检测到 Inno Setup 6 (ISCC.exe)。" -ForegroundColor DarkYellow
    Write-Host "  如需生成 Windows 安装包 (.exe)，请安装 Inno Setup 6 (https://jrsoftware.org/isdl.php)" -ForegroundColor DarkYellow
    Write-Host "  安装完成后重新运行本脚本，或直接在 Inno Setup IDE 中打开: $IssPath" -ForegroundColor DarkYellow
}

# 5. 生成校验值文件 (SHA-256 Checksums)
Write-Host "[4/4] 正在生成发布包 SHA-256 校验和..." -ForegroundColor Yellow
$ChecksumFile = Join-Path $DistDir "SHA256SUMS.txt"
$Checksums = @()

Get-ChildItem -Path $DistDir -File | Where-Object { $_.Name -ne "SHA256SUMS.txt" } | ForEach-Object {
    $hash = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash.ToLower()
    $Checksums += "$hash  $($_.Name)"
}

$Checksums | Out-File -FilePath $ChecksumFile -Encoding utf8
Write-Host "  -> 校验和已保存至: $ChecksumFile" -ForegroundColor Green

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "发布产物汇总 (位于 dist/windows):" -ForegroundColor Cyan
Get-ChildItem -Path $DistDir | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
Write-Host "==================================================" -ForegroundColor Cyan
