[CmdletBinding()]
param(
  [string]$Url,
  [string]$Id,
  [string]$Token,
  [string]$Agent,
  [switch]$Help
)

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Help) {
  Write-Host '用法: init.ps1 [-Url U] [-Id I] [-Token T] [-Agent claude|codex]'
  exit 0
}

$urlValue = if ($Url) { $Url } else { $env:WORKO_URL }
$idValue = if ($Id) { $Id } else { $env:WORKO_ID }
$tokenValue = if ($Token) { $Token } else { $env:WORKO_TOKEN }
$agentValue = if ($Agent) { $Agent } else { $env:WORKO_AGENT }

if (-not $urlValue -and [Environment]::UserInteractive) {
  $urlValue = Read-Host 'Hub 地址 (WORKO_URL) [http://localhost:8080]'
  if (-not $urlValue) { $urlValue = 'http://localhost:8080' }
}
if (-not $idValue -and [Environment]::UserInteractive) {
  $idValue = Read-Host '你的身份/邮箱 (WORKO_ID)'
}
if (-not $tokenValue -and [Environment]::UserInteractive) {
  $tokenValue = Read-Host 'Workspace 口令 (WORKO_TOKEN)'
}
if (-not $agentValue -and [Environment]::UserInteractive) {
  $agentValue = Read-Host '本机 agent (claude|codex) [claude]'
  if (-not $agentValue) { $agentValue = 'claude' }
}
if (-not $agentValue) { $agentValue = 'claude' }

if (-not $urlValue -or -not $idValue) {
  Stop-WorkoError '缺少必填 -Url / -Id。非交互请传参：init.ps1 -Url http://hub:8080 -Id you@corp.com -Token <口令> -Agent claude'
}

$urlValue = $urlValue.TrimEnd('/')  # 去掉尾斜杠，否则拼出 $url/agents 会变成 //agents

# 加入 workspace 时用 token 把 room id 取回来存进 config（发消息直接带对，且顺带体检 token/连接）。
# 取不到（离线/token 错）就留空：发消息时服务器仍按 token 兜底解析。
$roomValue = $env:WORKO_ROOM
if (-not $roomValue) {
  try {
    $headers = Get-WorkoAuthHeaders $tokenValue
    $rooms = Invoke-RestMethod -Uri "$urlValue/rooms" -Headers $headers -TimeoutSec 5
    if ($rooms.rooms -and $rooms.rooms.Count -gt 0) { $roomValue = $rooms.rooms[0].id }
  } catch { $roomValue = '' }
  if (-not $roomValue) {
    [Console]::Error.WriteLine("[worko] 警告：没从 $urlValue 取到 room（hub 连得上吗？token 对吗？）。先留空，发消息时服务器按 token 兜底解析。")
  }
}

$configPath = Get-WorkoConfigWritePath
New-Item -ItemType Directory -Force -Path (Split-Path $configPath) | Out-Null
$lines = @(
  "WORKO_URL=$urlValue",
  "WORKO_ID=$idValue",
  "WORKO_TOKEN=$tokenValue",
  "WORKO_AGENT=$agentValue"
)
if ($roomValue) { $lines += "WORKO_ROOM=$roomValue" }
$lines | Set-Content -Path $configPath -Encoding UTF8

$tokenStatus = if ($tokenValue) { '已设' } else { '空' }
$roomStatus = if ($roomValue) { $roomValue } else { '未取到(运行时兜底)' }
Write-Host "[worko] 已写 $configPath"
Write-Host "        id=$idValue  url=$urlValue  agent=$agentValue  token=$tokenStatus  room=$roomStatus"
