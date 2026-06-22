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
  Write-Host 'Usage: update.ps1 [-From local-repo-path] [-Repo owner/repo] [-Ref branch]'
  exit 0
}

if (-not $Repo) { $Repo = if ($env:WORKO_SKILL_REPO) { $env:WORKO_SKILL_REPO } else { 'CAgGen/open-worko' } }
if (-not $PathInRepo) { $PathInRepo = if ($env:WORKO_SKILL_PATH) { $env:WORKO_SKILL_PATH } else { 'skills/worko' } }
if (-not $Ref) { $Ref = if ($env:WORKO_SKILL_REF) { $env:WORKO_SKILL_REF } else { 'main' } }

$dest = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path -LiteralPath (Join-Path $dest 'SKILL.md'))) {
  Stop-WorkoError "[worko] This doesn't look like a worko skill directory: $dest"
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("worko-skill-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
  if ($From) {
    $src = Join-Path $From $PathInRepo
    if (-not (Test-Path -LiteralPath $src)) {
      Stop-WorkoError "[worko] Local source does not contain $src"
    }
    Write-Host "[worko] Updating from local $src..."
  } else {
    $repoDir = Join-Path $tmp 'repo'
    Write-Host "[worko] Pulling $PathInRepo from github.com/$Repo ($Ref)..."
    & git clone --depth 1 --branch $Ref --filter=blob:none --sparse "https://github.com/$Repo.git" $repoDir | Out-Null
    if ($LASTEXITCODE -ne 0) { Stop-WorkoError '[worko] git clone failed (check repo/branch/network; private repos need GITHUB_TOKEN)' }

    Push-Location $repoDir
    try {
      & git sparse-checkout set $PathInRepo | Out-Null
      if ($LASTEXITCODE -ne 0) { Stop-WorkoError "[worko] sparse-checkout failed: $PathInRepo" }
    } finally {
      Pop-Location
    }

    $src = Join-Path $repoDir $PathInRepo
    if (-not (Test-Path -LiteralPath $src)) {
      Stop-WorkoError "[worko] $PathInRepo not found in repo"
    }
  }

  Get-ChildItem -LiteralPath $src -Force | Copy-Item -Destination $dest -Recurse -Force
  Write-Host "[worko] Updated $dest"
  Write-Host '        Codex requires a restart to pick up the new skill; script-only changes (ask/list/start) take effect immediately.'
} finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
