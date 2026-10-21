# Format all Dart files across the monorepo workspace
$ErrorActionPreference = "Stop"

Write-Host "==> Formatting monorepo Dart files..." -ForegroundColor Cyan
dart format apps packages
Write-Host "==> Code formatting complete!" -ForegroundColor Green
