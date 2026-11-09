[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

Write-CiLog -Level INFO -Message 'Running common after-build.'

$steps = @(
  'common/tools/build-stats/collect.ps1',
  'common/tools/image-compress/compress-build.ps1',
  'common/tools/build-stats/collect.ps1',
  'common/tools/runtime-config/inject.ps1',
  'common/tools/logo-inject/inject.ps1'
)

foreach ($step in $steps) {
  & (Join-Path $Context.CiRoot $step) -Context $Context
}

Write-CiArtifacts -Context $Context
