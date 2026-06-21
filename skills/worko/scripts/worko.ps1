$ErrorActionPreference = 'Stop'

$commands = @{
  init = 'init.ps1'
  list = 'list.ps1'
  ask = 'ask.ps1'
  start = 'start.ps1'
  stop = 'stop.ps1'
  status = 'status.ps1'
  logs = 'logs.ps1'
  update = 'update.ps1'
}

function Show-Usage {
  Write-Host '用法: worko.ps1 <init|list|ask|start|stop|status|logs|update> [args]'
  Write-Host 'Windows 也可以直接调用同名脚本，例如: scripts/list.ps1'
}

if ($args.Count -eq 0 -or $args[0] -eq 'help' -or $args[0] -eq '-h' -or $args[0] -eq '--help') {
  Show-Usage
  exit 0
}

$command = ([string]$args[0]).ToLowerInvariant()
if (-not $commands.ContainsKey($command)) {
  Show-Usage
  exit 1
}

$rest = @()
if ($args.Count -gt 1) {
  $rest = $args[1..($args.Count - 1)]
}

$script = Join-Path $PSScriptRoot $commands[$command]
& $script @rest
