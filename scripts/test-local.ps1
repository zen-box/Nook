# Local checks on Windows (spec section 13.2): NookCore build/test with Swift for Windows,
# then go test / go vet for the server. Exits non-zero if any step fails.
#
# Usage (from any directory):
#   powershell -ExecutionPolicy Bypass -File scripts\test-local.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\test-local.ps1 -SkipGo

[CmdletBinding()]
param(
    [switch]$SkipSwift,
    [switch]$SkipGo
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Invoke-Step {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Command
    )
    Write-Host "==> $Name" -ForegroundColor Cyan
    # Native tools write progress to stderr; keep PS 5.1 from turning that into exceptions.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = 0
    try { & $Command } finally { $ErrorActionPreference = $previous }
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed (exit code $LASTEXITCODE)"
    }
}

Push-Location $repoRoot
try {
    if (-not $SkipSwift) {
        Invoke-Step 'swift --version' { swift --version }
        Invoke-Step 'NookCore: resolve' { swift package --package-path packages/NookCore resolve }
        Invoke-Step 'NookCore: build' { swift build --package-path packages/NookCore }
        Invoke-Step 'NookCore: test' { swift test --package-path packages/NookCore }
    }
    if (-not $SkipGo) {
        Push-Location server
        try {
            Invoke-Step 'server: go test' { go test ./... }
            Invoke-Step 'server: go vet' { go vet ./... }
        } finally {
            Pop-Location
        }
    }
    Write-Host 'All local checks passed.' -ForegroundColor Green
} finally {
    Pop-Location
}
