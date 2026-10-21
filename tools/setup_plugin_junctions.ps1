$ErrorActionPreference = "Stop"
$RepoRoot = (Get-Item $PSScriptRoot).Parent.FullName
$DepFile = Join-Path $RepoRoot "apps\juying_app\.flutter-plugins-dependencies"
$SymlinkDir = Join-Path $RepoRoot "apps\juying_app\windows\flutter\ephemeral\.plugin_symlinks"

if (-not (Test-Path $SymlinkDir)) {
    New-Item -ItemType Directory -Path $SymlinkDir -Force | Out-Null
}

$content = Get-Content $DepFile -Raw | ConvertFrom-Json
$plugins = $content.plugins.windows

foreach ($p in $plugins) {
    $name = $p.name
    $path = $p.path.TrimEnd('\')
    $target = Join-Path $SymlinkDir $name
    if (-not (Test-Path $target)) {
        Write-Host "Creating junction for $name -> $path" -ForegroundColor Yellow
        cmd /c "mklink /J `"$target`" `"$path`""
    } else {
        Write-Host "$name junction already exists" -ForegroundColor Gray
    }
}
Write-Host "Plugin junctions setup complete!" -ForegroundColor Green
