[CmdletBinding()]
param([switch]$Help)

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Help) {
  Write-Host '用法: stop.ps1'
  exit 0
}

$config = Read-WorkoConfig
$id = Get-WorkoValue $config 'WORKO_ID' ''
if (-not $id) { Stop-WorkoError '需要 WORKO_ID' }

$pidPath = Get-WorkoPidPath $id
$workoProcessId = Get-WorkoPid $pidPath

if (Test-WorkoProcess $workoProcessId) {
  Stop-Process -Id $workoProcessId -Force
  Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
  Write-Host "[worko] 已停止 ($id)"
} else {
  Write-Host "[worko] 没在跑 ($id)"
  Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
}
