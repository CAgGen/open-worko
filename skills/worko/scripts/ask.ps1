[CmdletBinding()]
param(
  [Parameter(Position=0)][string]$To,
  [Parameter(Position=1,ValueFromRemainingArguments=$true)][string[]]$Question,
  [switch]$Help
)

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Help) {
  Write-Host 'Usage: ask.ps1 <target-id> <question>'
  exit 0
}

$questionText = ($Question -join ' ')
$config = Read-WorkoConfig
$hub = Get-WorkoValue $config 'WORKO_URL' 'http://localhost:8080'
$id = Get-WorkoValue $config 'WORKO_ID' ''
$room = Get-WorkoValue $config 'WORKO_ROOM' ''   # empty → server auto-resolves the workspace room via token (hardcoding room_dev causes 403)
$timeout = [int](Get-WorkoValue $config 'WORKO_TIMEOUT' '120')
$headers = Get-WorkoAuthHeaders (Get-WorkoValue $config 'WORKO_TOKEN' '')

if (-not $id -or -not $To -or -not $questionText) {
  Stop-WorkoError 'Usage: WORKO_ID=you ask.ps1 <target-id> <question>'
}

$body = '{'
if ($room) { $body += '"room":' + (ConvertTo-WorkoJsonValue $room) + ',' }
$body += '"from":' + (ConvertTo-WorkoJsonValue $id) +
  ',"to":[' + (ConvertTo-WorkoJsonValue $To) + ']' +
  ',"type":"ask","content":' + (ConvertTo-WorkoJsonValue $questionText) + '}'

# Send as UTF-8 bytes: PowerShell 5.1 encodes string bodies as Latin-1, mangling non-ASCII content.
$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
$response = Invoke-RestMethod -Uri "$hub/messages" -Method Post -ContentType 'application/json; charset=utf-8' -Headers $headers -Body $bodyBytes
$thread = $response.thread
[Console]::Error.WriteLine("[$id] Sent to $To (thread=$thread), waiting for answer...")

$threadQuery = [uri]::EscapeDataString($thread)
$deadline = (Get-Date).AddSeconds($timeout)
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 1
  $context = Invoke-RestMethod -Uri "$hub/context?thread=$threadQuery" -Headers $headers
  foreach ($message in @($context.recent)) {
    if ($message.type -eq 'answer' -and (@($message.to) -contains $id)) {
      Write-Output $message.content
      exit 0
    }
  }
}

[Console]::Error.WriteLine("[$id] Timed out waiting for $To (${timeout}s)")
exit 1
