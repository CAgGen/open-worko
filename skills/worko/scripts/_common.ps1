$ErrorActionPreference = 'Stop'

function Get-WorkoHomeDir {
  if ($env:USERPROFILE) { return $env:USERPROFILE }
  return $HOME
}

# Config lookup. Priority: WORKO_CONFIG > nearest .worko\config walking up (project-level) > ~\.worko\config (machine-level)
function Get-WorkoConfigPath {
  if ($env:WORKO_CONFIG) { return $env:WORKO_CONFIG }
  $dir = (Get-Location).Path
  while ($dir) {
    $candidate = Join-Path $dir '.worko\config'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    $parent = Split-Path $dir -Parent
    if ($parent -eq $dir) { break }
    $dir = $parent
  }
  return (Join-Path (Get-WorkoHomeDir) '.worko\config')
}

# Write path for config (init). WORKO_CONFIG takes priority; otherwise project-level .\.worko\config.
function Get-WorkoConfigWritePath {
  if ($env:WORKO_CONFIG) { return $env:WORKO_CONFIG }
  return (Join-Path (Get-Location).Path '.worko\config')
}

function Get-WorkoRunDir {
  if ($env:WORKO_RUNDIR) { return $env:WORKO_RUNDIR }
  return (Join-Path (Get-WorkoHomeDir) '.worko\run')
}

function Stop-WorkoError {
  param([Parameter(Mandatory=$true)][string]$Message)
  Write-Error $Message
  exit 1
}

function Read-WorkoConfig {
  $config = @{}
  $path = Get-WorkoConfigPath

  if (Test-Path -LiteralPath $path) {
    foreach ($line in Get-Content -LiteralPath $path) {
      if ($line -match '^\s*([A-Z_]+)\s*=\s*(.*)$') {
        $config[$matches[1]] = $matches[2].Trim()
      }
    }
  }

  foreach ($key in 'WORKO_URL','WORKO_ID','WORKO_TOKEN','WORKO_AGENT','WORKO_ROOM','WORKO_TIMEOUT','WORKO_WS') {
    $value = [Environment]::GetEnvironmentVariable($key)
    if ($null -ne $value -and $value -ne '') {
      $config[$key] = $value
    }
  }

  return $config
}

function Get-WorkoValue {
  param(
    [Parameter(Mandatory=$true)][hashtable]$Config,
    [Parameter(Mandatory=$true)][string]$Name,
    [string]$Default = ''
  )

  if ($Config.ContainsKey($Name) -and $null -ne $Config[$Name] -and "$($Config[$Name])" -ne '') {
    return $Config[$Name]
  }

  return $Default
}

function Get-WorkoAuthHeaders {
  param([string]$Token)
  if ($Token) { return @{ authorization = "Bearer $Token" } }
  return @{}
}

function ConvertTo-WorkoJsonValue {
  param([AllowNull()][object]$Value)
  return (ConvertTo-Json -InputObject $Value -Compress)
}

function Set-WorkoEnvironmentFromConfig {
  param([Parameter(Mandatory=$true)][hashtable]$Config)

  foreach ($key in 'WORKO_URL','WORKO_ID','WORKO_TOKEN','WORKO_AGENT','WORKO_ROOM','WORKO_WS','WORKO_AGENT_CWD') {
    if ($Config.ContainsKey($key)) {
      Set-Item -Path "env:$key" -Value $Config[$key]
    }
  }

  if (-not $env:HOME) {
    Set-Item -Path 'env:HOME' -Value (Get-WorkoHomeDir)
  }
}

function Get-WorkoPidPath {
  param([Parameter(Mandatory=$true)][string]$Id)
  return (Join-Path (Get-WorkoRunDir) "$Id.pid")
}

function Get-WorkoLogPath {
  param([Parameter(Mandatory=$true)][string]$Id)
  return (Join-Path (Get-WorkoRunDir) "$Id.log")
}

function Get-WorkoErrLogPath {
  param([Parameter(Mandatory=$true)][string]$Id)
  return (Join-Path (Get-WorkoRunDir) "$Id.err")
}

function Get-WorkoPid {
  param([Parameter(Mandatory=$true)][string]$PidPath)

  if (-not (Test-Path -LiteralPath $PidPath)) { return $null }
  $raw = (Get-Content -LiteralPath $PidPath -Raw).Trim()
  $parsedProcessId = 0
  if ([int]::TryParse($raw, [ref]$parsedProcessId)) { return $parsedProcessId }
  return $null
}

function Test-WorkoProcess {
  param([AllowNull()][int]$ProcessId)
  if ($null -eq $ProcessId -or $ProcessId -le 0) { return $false }
  return [bool](Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Resolve-WorkoRuntime {
  if ($env:WORKO_RUNTIME) { return $env:WORKO_RUNTIME }
  if (Get-Command bun -ErrorAction SilentlyContinue) { return 'bun' }
  if (Get-Command node -ErrorAction SilentlyContinue) { return 'node' }
  Stop-WorkoError 'bun or node (node 22.18+/23.6+) is required to run the gateway. On Windows, install the node package.'
}
