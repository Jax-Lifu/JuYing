# Run all package unit tests and the main application test suite
$ErrorActionPreference = "Stop"

Write-Host "==> Testing packages/core..." -ForegroundColor Cyan
Push-Location packages/core
dart test
Pop-Location

Write-Host "==> Testing packages/player_engine..." -ForegroundColor Cyan
Push-Location packages/player_engine
dart test
Pop-Location

Write-Host "==> Testing packages/source_providers..." -ForegroundColor Cyan
Push-Location packages/source_providers
dart test
Pop-Location

Write-Host "==> Testing packages/epg..." -ForegroundColor Cyan
Push-Location packages/epg
dart test
Pop-Location

Write-Host "==> Testing packages/proxy_server..." -ForegroundColor Cyan
Push-Location packages/proxy_server
dart test
Pop-Location

Write-Host "==> Testing packages/discovery..." -ForegroundColor Cyan
Push-Location packages/discovery
dart test
Pop-Location

Write-Host "==> Testing packages/cast_sender..." -ForegroundColor Cyan
Push-Location packages/cast_sender
dart test
Pop-Location

Write-Host "==> Testing packages/receiver..." -ForegroundColor Cyan
Push-Location packages/receiver
dart test
Pop-Location

Write-Host "==> Testing packages/net..." -ForegroundColor Cyan
Push-Location packages/net
dart test
Pop-Location

Write-Host "==> Testing packages/storage..." -ForegroundColor Cyan
Push-Location packages/storage
dart test
Pop-Location

Write-Host "==> Testing packages/ui_kit..." -ForegroundColor Cyan
Push-Location packages/ui_kit
flutter test
Pop-Location

Write-Host "==> Testing apps/juying_app..." -ForegroundColor Cyan
Push-Location apps/juying_app
flutter test
Pop-Location

Write-Host "==> All test suites completed successfully!" -ForegroundColor Green
