[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

. (Join-Path $Context.CiRoot 'common/tools/env-prepare/lib.ps1')
. (Join-Path $Context.CiRoot 'common/upload.ps1')

if (-not (Test-CiEnvStage -Context $Context -Stages @('all', 'env-prepare', 'upload'))) {
  return
}

if (-not [bool]$Context.Profile.uploadEnabled) {
  Write-CiLog -Level INFO -Message 'bytedance upload dependency setup skipped because profile.uploadEnabled=false.'
  return
}

$cliName = Get-CiProfileString -Profile $Context.Profile -Name 'bytedanceUploadCli' -Default 'tmg'
$cli = Get-Command $cliName -ErrorAction SilentlyContinue
if ($cli) {
  Write-CiLog -Level INFO -Message "bytedance upload CLI is ready: $($cli.Source)"
  return
}

Invoke-CiNpmGlobalInstall -PackageName 'tt-minigame-ide-cli' -Description 'Install bytedance tt-minigame-ide-cli'

$cli = Get-Command $cliName -ErrorAction SilentlyContinue
if (-not $cli) {
  throw "bytedance upload CLI '$cliName' is still unavailable after npm global install."
}

Write-CiLog -Level INFO -Message "bytedance upload CLI installed: $($cli.Source)"
