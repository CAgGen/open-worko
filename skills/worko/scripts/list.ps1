[CmdletBinding()]
param([switch]$Help)

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Help) {
  Write-Host 'Usage: list.ps1'
  exit 0
}

$config = Read-WorkoConfig
$hub = Get-WorkoValue $config 'WORKO_URL' 'http://localhost:8080'
$headers = Get-WorkoAuthHeaders (Get-WorkoValue $config 'WORKO_TOKEN' '')

$response = Invoke-RestMethod -Uri "$hub/agents" -Headers $headers
$agents = @($response.agents)
if (-not $agents -or $agents.Count -eq 0) {
  Write-Host '(no agents registered yet)'
  exit 0
}

foreach ($agent in $agents) {
  $dot = if ($agent.online) { '● online ' } else { '○ offline' }
  Write-Host "$dot  $($agent.id)  ($($agent.kind))"
}
