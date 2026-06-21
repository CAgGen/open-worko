[CmdletBinding()]
param([switch]$Help)

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Help) {
  Write-Host '用法: start.ps1'
  exit 0
}

$configPath = Get-WorkoConfigPath
$config = Read-WorkoConfig
$id = Get-WorkoValue $config 'WORKO_ID' ''

if (-not (Test-Path -LiteralPath $configPath) -and -not $id) {
  if ([Environment]::UserInteractive) {
    Write-Host "[worko] 没找到 $configPath，先配置一下："
    & (Join-Path $PSScriptRoot 'init.ps1')
    $config = Read-WorkoConfig
    $id = Get-WorkoValue $config 'WORKO_ID' ''
  } else {
    Stop-WorkoError '没有 ~/.worko/config。先跑 init.ps1 配置，或传 WORKO_ID/WORKO_TOKEN 等环境变量。'
  }
}

if (-not $id) {
  Stop-WorkoError '需要 WORKO_ID（在 config 或环境变量里设）'
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
  Write-Host "[worko] daemon 已在跑 pid=$workoProcessId"
  exit 0
}

$hub = Get-WorkoValue $config 'WORKO_URL' 'http://localhost:8080'
try {
  Invoke-WebRequest -UseBasicParsing -Uri "$hub/health" -TimeoutSec 3 | Out-Null
} catch {
  Write-Host "[worko] 警告：$hub 暂时连不上，daemon 会自动重连"
}

$process = Start-Process -FilePath $runtime -ArgumentList "`"$gateway`"" -PassThru -WindowStyle Hidden `
  -RedirectStandardOutput $logPath -RedirectStandardError $errLogPath
$process.Id | Set-Content -Path $pidPath -Encoding ASCII

$agent = Get-WorkoValue $config 'WORKO_AGENT' 'claude'
Write-Host "[worko] gateway 起好 pid=$($process.Id)  id=$id  agent=$agent  runtime=$runtime  log=$logPath"
