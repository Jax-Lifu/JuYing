param(
    [switch]$RegeneratePlatforms
)

$ErrorActionPreference = 'Stop'

function Find-Flutter {
    $command = Get-Command flutter -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @(
        $env:FLUTTER_ROOT,
        'D:\flutter',
        'C:\flutter'
    ) | Where-Object { $_ }

    foreach ($candidate in $candidates) {
        $flutter = Join-Path $candidate 'bin\flutter.bat'
        if (Test-Path -LiteralPath $flutter) { return $flutter }
    }
    throw 'Flutter SDK was not found. Install Flutter stable or set FLUTTER_ROOT.'
}

$flutter = Find-Flutter

function Invoke-Flutter {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & $flutter @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter command failed: flutter $($Arguments -join ' ')"
    }
}

$appRoot = Split-Path -Parent $PSScriptRoot
Push-Location $appRoot
try {
    if ($RegeneratePlatforms) {
        Invoke-Flutter create --platforms=android,ios,windows,linux --project-name juying --org com.flytech .
    }
    Invoke-Flutter pub get
    Invoke-Flutter analyze
    Invoke-Flutter test
    Invoke-Flutter build windows --release
}
finally {
    Pop-Location
}
