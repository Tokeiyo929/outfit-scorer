[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

Write-CiLog -Level INFO -Message 'Running common before-build.'

$steps = @(
  'common/tools/environment/collect.ps1',
  'common/tools/project-validate/validate.ps1',
  'common/tools/git-snapshot/collect.ps1',
  'common/tools/image-compress/generate-manifest.ps1'
)

foreach ($step in $steps) {
  & (Join-Path $Context.CiRoot $step) -Context $Context
}

Write-CiArtifacts -Context $Context
