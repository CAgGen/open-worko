[CmdletBinding()]
param([switch]$Help)

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Help) {
  Write-Host 'Usage: logs.ps1'
  exit 0
}

$config = Read-WorkoConfig
$id = Get-WorkoValue $config 'WORKO_ID' ''
if (-not $id) { Stop-WorkoError 'WORKO_ID is required' }

$logPath = Get-WorkoLogPath $id
$errLogPath = Get-WorkoErrLogPath $id

if (-not (Test-Path -LiteralPath $logPath) -and -not (Test-Path -LiteralPath $errLogPath)) {
  Stop-WorkoError 'No log yet (run start.ps1 first)'
}

if (Test-Path -LiteralPath $errLogPath) {
  Write-Host "[worko] stderr log: $errLogPath"
}
if (Test-Path -LiteralPath $logPath) {
  Get-Content -LiteralPath $logPath -Wait
} else {
  Get-Content -LiteralPath $errLogPath -Wait
}
