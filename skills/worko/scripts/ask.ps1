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
$room = Get-WorkoValue $config 'WORKO_ROOM' ''   # 留空 → 服务器按 token 自动定位 workspace 的 room（乱填 room_dev 会 403）
$timeout = [int](Get-WorkoValue $config 'WORKO_TIMEOUT' '120')
$headers = Get-WorkoAuthHeaders (Get-WorkoValue $config 'WORKO_TOKEN' '')

if (-not $id -or -not $To -or -not $questionText) {
  Stop-WorkoError '用法: WORKO_ID=你 ask.ps1 <对方id> <问题>'
}

$body = '{'
if ($room) { $body += '"room":' + (ConvertTo-WorkoJsonValue $room) + ',' }
$body += '"from":' + (ConvertTo-WorkoJsonValue $id) +
  ',"to":[' + (ConvertTo-WorkoJsonValue $To) + ']' +
  ',"type":"ask","content":' + (ConvertTo-WorkoJsonValue $questionText) + '}'

# UTF-8 字节发送：PowerShell 5.1 用字符串 body 会按 Latin-1 编码，中文变乱码。
$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
$response = Invoke-RestMethod -Uri "$hub/messages" -Method Post -ContentType 'application/json; charset=utf-8' -Headers $headers -Body $bodyBytes
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
