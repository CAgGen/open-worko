[CmdletBinding()]
param([switch]$Help)

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Help) {
  Write-Host '用法: status.ps1'
  exit 0
}

$config = Read-WorkoConfig
$id = Get-WorkoValue $config 'WORKO_ID' ''
if (-not $id) { Stop-WorkoError '需要 WORKO_ID' }

$pidPath = Get-WorkoPidPath $id
$workoProcessId = Get-WorkoPid $pidPath
$url = Get-WorkoValue $config 'WORKO_URL' 'http://localhost:8080'

if (Test-WorkoProcess $workoProcessId) {
  Write-Host "[worko] running  pid=$workoProcessId  id=$id  url=$url"
} else {
  Write-Host "[worko] stopped  id=$id"
}
