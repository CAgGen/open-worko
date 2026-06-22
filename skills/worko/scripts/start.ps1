[CmdletBinding()]
param([switch]$Help)

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Help) {
  Write-Host 'Usage: start.ps1'
  exit 0
}

$configPath = Get-WorkoConfigPath
$config = Read-WorkoConfig
$id = Get-WorkoValue $config 'WORKO_ID' ''

if (-not (Test-Path -LiteralPath $configPath) -and -not $id) {
  if ([Environment]::UserInteractive) {
    Write-Host "[worko] Config not found at $configPath, setting up now:"
    & (Join-Path $PSScriptRoot 'init.ps1')
    $config = Read-WorkoConfig
    $id = Get-WorkoValue $config 'WORKO_ID' ''
  } else {
    Stop-WorkoError 'No ~/.worko/config found. Run init.ps1 first, or set WORKO_ID/WORKO_TOKEN etc. as environment variables.'
  }
}

if (-not $id) {
  Stop-WorkoError 'WORKO_ID is required (set in config or as an environment variable)'
}

Set-WorkoEnvironmentFromConfig $config
# Resolve-WorkoRuntime honors WORKO_RUNTIME, then falls back to bun and node.
$runtime = Resolve-WorkoRuntime
$gateway = Join-Path $PSScriptRoot 'gateway.ts'
$runDir = Get-WorkoRunDir
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$pidPath = Get-WorkoPidPath $id
$logPath = Get-WorkoLogPath $id
$errLogPath = Get-WorkoErrLogPath $id
$workoProcessId = Get-WorkoPid $pidPath

if (Test-WorkoProcess $workoProcessId) {
  Write-Host "[worko] daemon already running pid=$workoProcessId"
  exit 0
}

$hub = Get-WorkoValue $config 'WORKO_URL' 'http://localhost:8080'
try {
  Invoke-WebRequest -UseBasicParsing -Uri "$hub/health" -TimeoutSec 3 | Out-Null
} catch {
  Write-Host "[worko] Warning: $hub is unreachable — daemon will retry automatically"
}

$process = Start-Process -FilePath $runtime -ArgumentList "`"$gateway`"" -PassThru -WindowStyle Hidden `
  -RedirectStandardOutput $logPath -RedirectStandardError $errLogPath
$process.Id | Set-Content -Path $pidPath -Encoding ASCII

$agent = Get-WorkoValue $config 'WORKO_AGENT' 'claude'
Write-Host "[worko] gateway started pid=$($process.Id)  id=$id  agent=$agent  runtime=$runtime  log=$logPath"
