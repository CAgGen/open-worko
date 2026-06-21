[CmdletBinding()]
param(
  [string]$From,
  [string]$Repo,
  [string]$Ref,
  [string]$PathInRepo,
  [switch]$Help
)

. (Join-Path $PSScriptRoot '_common.ps1')

if ($Help) {
  Write-Host '用法: update.ps1 [-From 本地仓库路径] [-Repo owner/repo] [-Ref 分支]'
  exit 0
}

if (-not $Repo) { $Repo = if ($env:WORKO_SKILL_REPO) { $env:WORKO_SKILL_REPO } else { 'CAgGen/open-worko' } }
if (-not $PathInRepo) { $PathInRepo = if ($env:WORKO_SKILL_PATH) { $env:WORKO_SKILL_PATH } else { 'skills/worko' } }
if (-not $Ref) { $Ref = if ($env:WORKO_SKILL_REF) { $env:WORKO_SKILL_REF } else { 'main' } }

$dest = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path -LiteralPath (Join-Path $dest 'SKILL.md'))) {
  Stop-WorkoError "[worko] 这看着不像 worko skill 目录: $dest"
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("worko-skill-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
  if ($From) {
    $src = Join-Path $From $PathInRepo
    if (-not (Test-Path -LiteralPath $src)) {
      Stop-WorkoError "[worko] 本地源没有 $src"
    }
    Write-Host "[worko] 从本地 $src 更新..."
  } else {
    $repoDir = Join-Path $tmp 'repo'
    Write-Host "[worko] 从 github.com/$Repo ($Ref) 拉 $PathInRepo ..."
    & git clone --depth 1 --branch $Ref --filter=blob:none --sparse "https://github.com/$Repo.git" $repoDir | Out-Null
    if ($LASTEXITCODE -ne 0) { Stop-WorkoError '[worko] git clone 失败（检查 repo/分支/网络；私有仓需 GITHUB_TOKEN）' }

    Push-Location $repoDir
    try {
      & git sparse-checkout set $PathInRepo | Out-Null
      if ($LASTEXITCODE -ne 0) { Stop-WorkoError "[worko] sparse-checkout 失败: $PathInRepo" }
    } finally {
      Pop-Location
    }

    $src = Join-Path $repoDir $PathInRepo
    if (-not (Test-Path -LiteralPath $src)) {
      Stop-WorkoError "[worko] repo 里没有 $PathInRepo"
    }
  }

  Get-ChildItem -LiteralPath $src -Force | Copy-Item -Destination $dest -Recurse -Force
  Write-Host "[worko] 已更新 $dest"
  Write-Host '        Codex 需重启才认新 skill；纯脚本改动(ask/list/start)立即生效。'
} finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
