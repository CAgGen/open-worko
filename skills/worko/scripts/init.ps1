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

# 本地 agent 的工作目录：默认当前目录。gateway 用它当 cwd + 沙箱边界，agent 只能在这个目录里干活。
$WORKO_AGENT_CWD = if ($env:WORKO_AGENT_CWD) { $env:WORKO_AGENT_CWD } else { $PWD.Path }

# Windows + codex：沙箱要 codex-windows-sandbox-setup.exe，它常没进 PATH → codex 起不了沙箱报"找不到"。
# 定位它、把所在目录加进【用户级】PATH（不需要管理员；system 级才要提权，没必要）。幂等；找不到就提示重装。
if ($agentValue -eq 'codex' -and ($IsWindows -or $env:OS -eq 'Windows_NT')) {
  $helper = 'codex-windows-sandbox-setup.exe'
  $roots = @()
  $cmd = Get-Command codex -ErrorAction SilentlyContinue
  if ($cmd) { $roots += Split-Path $cmd.Source }            # codex 自己所在目录最可能带着 helper
  try { $roots += (& npm root -g 2>$null) } catch {}        # 兜底：npm 全局 node_modules
  $found = $null
  foreach ($r in ($roots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)) {
    $hit = Get-ChildItem -Path $r -Recurse -Depth 5 -Filter $helper -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { $found = $hit.DirectoryName; break }
  }
  if ($found) {
    $parts = ([Environment]::GetEnvironmentVariable('Path', 'User') -split ';') | Where-Object { $_ }
    if ($parts -notcontains $found) {
      [Environment]::SetEnvironmentVariable('Path', (($parts + $found) -join ';'), 'User')
      $env:Path = "$env:Path;$found"                        # 当前会话也立刻生效，免得重开终端
      Write-Host "[worko] 已把 codex 沙箱目录加入用户 PATH：$found"
    } else {
      Write-Host "[worko] codex 沙箱目录已在 PATH：$found"
    }
  } else {
    [Console]::Error.WriteLine("[worko] 警告：没找到 $helper，codex 沙箱起不来。多半 codex 装得不全，重装/升级 codex 后重跑。")
  }
}

# 加入 workspace 时用 token 把 room id 取回来存进 config（发消息直接带对，且顺带体检 token/连接）。
# 取不到（离线/token 错）就留空：发消息时服务器仍按 token 兜底解析。
$roomValue = $env:WORKO_ROOM
if (-not $roomValue) {
  try {
    $headers = Get-WorkoAuthHeaders $tokenValue
    $rooms = Invoke-RestMethod -Uri "$urlValue/rooms" -Headers $headers -TimeoutSec 5
    # 只在恰好 1 个 room 时采用：authed 模式 token 锁定唯一 room；dev 模式会返回所有 workspace 的 room，分不清就放弃。
    if ($rooms.rooms -and @($rooms.rooms).Count -eq 1) { $roomValue = @($rooms.rooms)[0].id }
  } catch { $roomValue = '' }
  if (-not $roomValue) {
    [Console]::Error.WriteLine("[worko] 提示：没唯一确定 room（连不上 / token 不对 / dev 模式有多个 workspace）。留空即可，发消息时服务器按 token 兜底解析。")
  }
}

$configPath = Get-WorkoConfigWritePath
New-Item -ItemType Directory -Force -Path (Split-Path $configPath) | Out-Null
$lines = @(
  "WORKO_URL=$urlValue",
  "WORKO_ID=$idValue",
  "WORKO_TOKEN=$tokenValue",
  "WORKO_AGENT=$agentValue",
  "WORKO_AGENT_CWD=$WORKO_AGENT_CWD"
)
if ($roomValue) { $lines += "WORKO_ROOM=$roomValue" }
$lines | Set-Content -Path $configPath -Encoding UTF8

$tokenStatus = if ($tokenValue) { '已设' } else { '空' }
$roomStatus = if ($roomValue) { $roomValue } else { '未取到(运行时兜底)' }
Write-Host "[worko] 已写 $configPath"
Write-Host "        id=$idValue  url=$urlValue  agent=$agentValue  token=$tokenStatus  room=$roomStatus  workdir=$WORKO_AGENT_CWD"
