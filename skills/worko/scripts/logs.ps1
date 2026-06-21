[CmdletBinding()]
param([switch]$Help)

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Help) {
  Write-Host '用法: logs.ps1'
  exit 0
}

$config = Read-WorkoConfig
$id = Get-WorkoValue $config 'WORKO_ID' ''
if (-not $id) { Stop-WorkoError '需要 WORKO_ID' }

$logPath = Get-WorkoLogPath $id
$errLogPath = Get-WorkoErrLogPath $id

if (-not (Test-Path -LiteralPath $logPath) -and -not (Test-Path -LiteralPath $errLogPath)) {
  Stop-WorkoError '还没有日志（先 start.ps1）'
}

if (Test-Path -LiteralPath $errLogPath) {
  Write-Host "[worko] stderr 日志: $errLogPath"
}
if (Test-Path -LiteralPath $logPath) {
  Get-Content -LiteralPath $logPath -Wait
} else {
  Get-Content -LiteralPath $errLogPath -Wait
}
