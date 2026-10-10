param([Parameter(Mandatory=$true)][string]$RuntimeDir)
$ErrorActionPreference = 'Stop'
$stateFile = Join-Path ([IO.Path]::GetFullPath($RuntimeDir)) 'state.json'
if (-not (Test-Path -LiteralPath $stateFile)) { Write-Output 'No running receiver recorded.'; return }
$state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
foreach ($processId in @($state.receiver_pid, $state.tunnel_pid)) {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
    # Avoid terminating a recycled PID belonging to an unrelated process.
    if ($process -and (($process.Name -match '^python.*\.exe$' -and $process.CommandLine -match 'receiver\.py') -or
        ($process.Name -eq 'cloudflared.exe' -and $process.CommandLine -match 'tunnel'))) {
        Stop-Process -Id $processId
    }
}
Remove-Item -LiteralPath $stateFile
Write-Output 'Receiver and tunnel stopped. Existing snapshots are preserved.'
