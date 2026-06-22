[CmdletBinding()]
param([switch]$Help)

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Help) {
  Write-Host 'Usage: stop.ps1'
  exit 0
}

$config = Read-WorkoConfig
$id = Get-WorkoValue $config 'WORKO_ID' ''
if (-not $id) { Stop-WorkoError 'WORKO_ID is required' }

$pidPath = Get-WorkoPidPath $id
$workoProcessId = Get-WorkoPid $pidPath

if (Test-WorkoProcess $workoProcessId) {
  Stop-Process -Id $workoProcessId -Force
  Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
  Write-Host "[worko] stopped ($id)"
} else {
  Write-Host "[worko] not running ($id)"
  Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
}
