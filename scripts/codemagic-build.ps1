# Start a Codemagic build through the REST API (v3), wait for it to finish, then list
# (and optionally download) its artifacts. App Preview itself is opened from the Codemagic
# web UI: "Quick Launch" next to the Nook.app artifact of an ios-simulator-preview build.
#
# Setup (per shell, or as user environment variables; never commit the token):
#   $env:CODEMAGIC_API_TOKEN = '<token>'   # Codemagic > Teams > Personal Account > Integrations > Codemagic API > Show
#   $env:CODEMAGIC_APP_ID    = '<app id>'  # from the app page URL: https://codemagic.io/app/<app id>
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\codemagic-build.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\codemagic-build.ps1 -Workflow ios-device-unsigned -DownloadDir build\codemagic
#   powershell -ExecutionPolicy Bypass -File scripts\codemagic-build.ps1 -BuildId <build id>   # watch an existing build

[CmdletBinding()]
param(
    [ValidateSet('ios-simulator-preview', 'ios-device-unsigned', 'ios-tests')]
    [string]$Workflow = 'ios-simulator-preview',
    [string]$Branch = 'main',
    [string]$BuildId,
    [switch]$NoWait,
    [string]$DownloadDir,
    [ValidateRange(5, 600)]
    [int]$PollSeconds = 30
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$token = $env:CODEMAGIC_API_TOKEN
if (-not $token) {
    throw 'CODEMAGIC_API_TOKEN is not set. See the comment at the top of this script.'
}
$apiBase = if ($env:CODEMAGIC_API_BASE) { $env:CODEMAGIC_API_BASE.TrimEnd('/') } else { 'https://codemagic.io/api/v3' }
$headers = @{ 'x-auth-token' = $token; 'Accept' = 'application/json' }
$terminalStates = @('finished', 'failed', 'canceled', 'timeout', 'skipped')

# Codemagic errors look like {"status_code": 402, "detail": "...", "errors": [...]}.
function Get-ErrorText {
    param($ErrorRecord)
    $message = $ErrorRecord.ErrorDetails.Message
    if ($message) {
        try {
            $parsed = $message | ConvertFrom-Json
            if ($parsed.detail) { return "$($parsed.status_code) $($parsed.detail)" }
        } catch { }
        return $message
    }
    return $ErrorRecord.Exception.Message
}

function Get-StatusCode {
    param($ErrorRecord)
    $response = $ErrorRecord.Exception.Response
    if ($response) { return [int]$response.StatusCode }
    return 0
}

if (-not $BuildId) {
    $appId = $env:CODEMAGIC_APP_ID
    if (-not $appId) {
        throw 'CODEMAGIC_APP_ID is not set. See the comment at the top of this script.'
    }
    $body = @{ workflow_id = $Workflow; branch = $Branch } | ConvertTo-Json
    try {
        $started = Invoke-RestMethod -Method Post -Uri "$apiBase/apps/$appId/builds" -Headers $headers -ContentType 'application/json' -Body $body
    } catch {
        throw "Could not start the build: $(Get-ErrorText $_)"
    }
    $BuildId = $started.data.id
    if (-not $BuildId) {
        throw "Unexpected response from Codemagic: $($started | ConvertTo-Json -Depth 5)"
    }
    Write-Host "Started $Workflow on branch ${Branch}: build $BuildId"
    Write-Host "  https://codemagic.io/app/$appId/build/$BuildId"
}

if ($NoWait) { return }

# A freshly started build can take a moment to become readable.
$notFoundDeadline = (Get-Date).AddMinutes(2)
$lastStatus = ''
while ($true) {
    try {
        $build = (Invoke-RestMethod -Method Get -Uri "$apiBase/builds/$BuildId" -Headers $headers).data
    } catch {
        if ((Get-StatusCode $_) -eq 404 -and (Get-Date) -lt $notFoundDeadline) {
            Start-Sleep -Seconds 5
            continue
        }
        throw "Could not read build ${BuildId}: $(Get-ErrorText $_)"
    }
    if ($build.status -ne $lastStatus) {
        Write-Host ('[{0:HH:mm:ss}] {1}' -f (Get-Date), $build.status)
        $lastStatus = $build.status
    }
    if ($terminalStates -contains $build.status) { break }
    Start-Sleep -Seconds $PollSeconds
}

$artifacts = @($build.artifacts | Where-Object { $_ })
if ($artifacts.Count -gt 0) {
    Write-Host 'Artifacts (download links expire soon):'
    foreach ($artifact in $artifacts) {
        $sizeMb = [math]::Round($artifact.size_in_bytes / 1MB, 1)
        Write-Host ('  {0}  [{1}, {2} MB]' -f $artifact.name, $artifact.type, $sizeMb)
        Write-Host "    $($artifact.short_lived_download_url)"
    }
}

if ($DownloadDir -and $artifacts.Count -gt 0) {
    New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
    foreach ($artifact in $artifacts) {
        $url = $artifact.short_lived_download_url
        if (-not $url) { continue }
        $target = Join-Path $DownloadDir (Split-Path -Leaf $artifact.name)
        # Only send the API token to Codemagic itself, never to a storage host.
        $downloadHeaders = @{}
        $urlHost = ([Uri]$url).Host
        if ($urlHost -eq 'codemagic.io' -or $urlHost -like '*.codemagic.io') { $downloadHeaders = $headers }
        Write-Host "Downloading $($artifact.name) -> $target"
        Invoke-WebRequest -UseBasicParsing -Uri $url -Headers $downloadHeaders -OutFile $target
    }
}

if ($build.status -ne 'finished') {
    Write-Host "Build $BuildId ended with status '$($build.status)'." -ForegroundColor Red
    exit 1
}
Write-Host "Build $BuildId finished." -ForegroundColor Green
