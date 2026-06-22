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
  Write-Host 'Usage: init.ps1 [-Url U] [-Id I] [-Token T] [-Agent claude|codex]'
  exit 0
}

$urlValue = if ($Url) { $Url } else { $env:WORKO_URL }
$idValue = if ($Id) { $Id } else { $env:WORKO_ID }
$tokenValue = if ($Token) { $Token } else { $env:WORKO_TOKEN }
$agentValue = if ($Agent) { $Agent } else { $env:WORKO_AGENT }

if (-not $urlValue -and [Environment]::UserInteractive) {
  $urlValue = Read-Host 'Hub address (WORKO_URL) [http://localhost:8080]'
  if (-not $urlValue) { $urlValue = 'http://localhost:8080' }
}
if (-not $idValue -and [Environment]::UserInteractive) {
  $idValue = Read-Host 'Your identity/email (WORKO_ID)'
}
if (-not $tokenValue -and [Environment]::UserInteractive) {
  $tokenValue = Read-Host 'Workspace token (WORKO_TOKEN)'
}
if (-not $agentValue -and [Environment]::UserInteractive) {
  $agentValue = Read-Host 'Local agent (claude|codex) [claude]'
  if (-not $agentValue) { $agentValue = 'claude' }
}
if (-not $agentValue) { $agentValue = 'claude' }

if (-not $urlValue -or -not $idValue) {
  Stop-WorkoError 'Missing required -Url / -Id. For non-interactive use, pass as arguments: init.ps1 -Url http://hub:8080 -Id you@corp.com -Token <token> -Agent claude'
}

$urlValue = $urlValue.TrimEnd('/')  # strip trailing slash to avoid double-slash in $url/agents

# Working directory for the local agent: defaults to current directory.
# The gateway uses this as cwd + sandbox boundary — the agent can only operate within this directory.
$WORKO_AGENT_CWD = if ($env:WORKO_AGENT_CWD) { $env:WORKO_AGENT_CWD } else { $PWD.Path }

# Windows + codex: the sandbox requires codex-windows-sandbox-setup.exe, which often isn't on PATH → codex can't start the sandbox.
# Locate it and add its directory to the user-level PATH (no admin needed; system-level would require elevation).
# Idempotent; if not found, prompt to reinstall.
if ($agentValue -eq 'codex' -and ($IsWindows -or $env:OS -eq 'Windows_NT')) {
  $helper = 'codex-windows-sandbox-setup.exe'
  $roots = @()
  $cmd = Get-Command codex -ErrorAction SilentlyContinue
  if ($cmd) { $roots += Split-Path $cmd.Source }            # codex's own directory most likely has the helper
  try { $roots += (& npm root -g 2>$null) } catch {}        # fallback: npm global node_modules
  $found = $null
  foreach ($r in ($roots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)) {
    $hit = Get-ChildItem -Path $r -Recurse -Depth 5 -Filter $helper -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { $found = $hit.DirectoryName; break }
  }
  if ($found) {
    $parts = ([Environment]::GetEnvironmentVariable('Path', 'User') -split ';') | Where-Object { $_ }
    if ($parts -notcontains $found) {
      [Environment]::SetEnvironmentVariable('Path', (($parts + $found) -join ';'), 'User')
      $env:Path = "$env:Path;$found"                        # also take effect in the current session
      Write-Host "[worko] Added codex sandbox directory to user PATH: $found"
    } else {
      Write-Host "[worko] Codex sandbox directory already in PATH: $found"
    }
  } else {
    [Console]::Error.WriteLine("[worko] Warning: $helper not found — codex sandbox cannot start. Likely an incomplete codex installation; reinstall/upgrade codex and run this again.")
  }
}

# Fetch room id from the hub using the token when joining a workspace (also validates token/connection).
# If unavailable, leave empty: server falls back to token-based room resolution at send time.
$roomValue = $env:WORKO_ROOM
if (-not $roomValue) {
  try {
    $headers = Get-WorkoAuthHeaders $tokenValue
    $rooms = Invoke-RestMethod -Uri "$urlValue/rooms" -Headers $headers -TimeoutSec 5
    # Only use the result when exactly 1 room is returned: authed mode locks to your workspace; dev mode
    # returns all workspace rooms, so we can't tell which one is yours.
    if ($rooms.rooms -and @($rooms.rooms).Count -eq 1) { $roomValue = @($rooms.rooms)[0].id }
  } catch { $roomValue = '' }
  if (-not $roomValue) {
    [Console]::Error.WriteLine("[worko] Note: could not determine a unique room (unreachable / wrong token / dev mode with multiple workspaces). Leaving empty — server will resolve via token at send time.")
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

$tokenStatus = if ($tokenValue) { 'set' } else { 'empty' }
$roomStatus = if ($roomValue) { $roomValue } else { 'not fetched (resolved at runtime)' }
Write-Host "[worko] Written to $configPath"
Write-Host "        id=$idValue  url=$urlValue  agent=$agentValue  token=$tokenStatus  room=$roomStatus  workdir=$WORKO_AGENT_CWD"
