param(
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$Cloudflared,
    [Parameter(Mandatory=$true)][string]$RuntimeDir,
    [int]$Port = 8765
)
$ErrorActionPreference = 'Stop'
$runtimePath = [IO.Path]::GetFullPath($RuntimeDir)
New-Item -ItemType Directory -Path $runtimePath -Force | Out-Null
$stateFile = Join-Path $runtimePath 'state.json'
if (Test-Path -LiteralPath $stateFile) {
    throw "Existing runtime found: $stateFile. Stop the existing service before starting another."
}
$randomBytes = New-Object byte[] 32
$randomGenerator = [Security.Cryptography.RandomNumberGenerator]::Create()
$randomGenerator.GetBytes($randomBytes)
$randomGenerator.Dispose()
$token = ([BitConverter]::ToString($randomBytes)).Replace('-', '').ToLowerInvariant()
$configPath = Join-Path $runtimePath 'receiver.json'
$urlFile = Join-Path $runtimePath 'public_url.txt'
$dataDir = Join-Path (Split-Path $runtimePath -Parent) 'snapshots'
@{token=$token; port=$Port; data_dir=$dataDir; public_url_file=$urlFile} |
    ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8
$receiverScript = Join-Path $PSScriptRoot 'receiver.py'
$receiverOut = Join-Path $runtimePath 'receiver.stdout.log'
$receiverErr = Join-Path $runtimePath 'receiver.stderr.log'
$tunnelOut = Join-Path $runtimePath 'tunnel.stdout.log'
$tunnelErr = Join-Path $runtimePath 'tunnel.stderr.log'
$receiverProcess = Start-Process -FilePath $Python -ArgumentList @('"' + $receiverScript + '"', '--config', '"' + $configPath + '"') -WindowStyle Hidden -PassThru -RedirectStandardOutput $receiverOut -RedirectStandardError $receiverErr
$tunnelProcess = $null
try {
    $ready = $false
    for ($attempt=0; $attempt -lt 20; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2
            if ($response.Content -match 'BEC diagnostic receiver ready') { $ready=$true; break }
        } catch { }
        if ($receiverProcess.HasExited) { throw "Receiver stopped. Read $receiverErr" }
        Start-Sleep -Milliseconds 250
    }
    if (-not $ready) { throw 'Receiver did not start' }
    $tunnelProcess = Start-Process -FilePath $Cloudflared -ArgumentList @('tunnel', '--no-autoupdate', '--protocol', 'http2', '--url', "http://127.0.0.1:$Port") -WindowStyle Hidden -PassThru -RedirectStandardOutput $tunnelOut -RedirectStandardError $tunnelErr
    @{receiver_pid=$receiverProcess.Id; tunnel_pid=$tunnelProcess.Id; port=$Port; started=(Get-Date).ToString('o')} |
        ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding utf8
    $publicUrl = $null
    for ($attempt=0; $attempt -lt 90; $attempt++) {
        $logText = (Get-Content -LiteralPath $tunnelErr -Raw -ErrorAction SilentlyContinue) + (Get-Content -LiteralPath $tunnelOut -Raw -ErrorAction SilentlyContinue)
        if ($logText -match 'https://[a-z0-9-]+\.trycloudflare\.com') { $publicUrl=$Matches[0]; break }
        if ($tunnelProcess.HasExited) { throw "Tunnel stopped. Read $tunnelErr" }
        Start-Sleep -Milliseconds 500
    }
    if (-not $publicUrl) { throw "No public tunnel URL. Read $tunnelErr" }
    $publicUrl | Set-Content -LiteralPath $urlFile -Encoding utf8
    $bootstrapUrl = "$publicUrl/$token/bootstrap.lua"
    $bootstrapUrl | Set-Content -LiteralPath (Join-Path $runtimePath 'bootstrap_url.txt') -Encoding utf8
    Write-Output "Receiver and tunnel started. Snapshot directory: $dataDir"
    Write-Output "wget -f $bootstrapUrl /home/bec_upload.lua"
    Write-Output 'lua /home/bec_upload.lua'
} catch {
    if ($tunnelProcess -and -not $tunnelProcess.HasExited) { Stop-Process -Id $tunnelProcess.Id }
    if (-not $receiverProcess.HasExited) { Stop-Process -Id $receiverProcess.Id }
    if (Test-Path -LiteralPath $stateFile) { Remove-Item -LiteralPath $stateFile }
    throw
}
