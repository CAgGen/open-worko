[CmdletBinding()]
param(
  [Parameter(Position=0)][string]$To,
  [Parameter(Position=1,ValueFromRemainingArguments=$true)][string[]]$Question,
  [switch]$Help
)

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Help) {
  Write-Host '用法: ask.ps1 <对方id> <问题>'
  exit 0
}

$questionText = ($Question -join ' ')
$config = Read-WorkoConfig
$hub = Get-WorkoValue $config 'WORKO_URL' 'http://localhost:8080'
$id = Get-WorkoValue $config 'WORKO_ID' ''
$room = Get-WorkoValue $config 'WORKO_ROOM' 'room_dev'
$timeout = [int](Get-WorkoValue $config 'WORKO_TIMEOUT' '120')
$headers = Get-WorkoAuthHeaders (Get-WorkoValue $config 'WORKO_TOKEN' '')

if (-not $id -or -not $To -or -not $questionText) {
  Stop-WorkoError '用法: WORKO_ID=你 ask.ps1 <对方id> <问题>'
}

$body = '{"room":' + (ConvertTo-WorkoJsonValue $room) +
  ',"from":' + (ConvertTo-WorkoJsonValue $id) +
  ',"to":[' + (ConvertTo-WorkoJsonValue $To) + ']' +
  ',"type":"ask","content":' + (ConvertTo-WorkoJsonValue $questionText) + '}'

$response = Invoke-RestMethod -Uri "$hub/messages" -Method Post -ContentType 'application/json' -Headers $headers -Body $body
$thread = $response.thread
[Console]::Error.WriteLine("[$id] 已问 $To (thread=$thread)，等回答...")

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

[Console]::Error.WriteLine("[$id] 等 $To 超时(${timeout}s)")
exit 1
