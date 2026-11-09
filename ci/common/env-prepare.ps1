[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

Write-CiLog -Level INFO -Message 'Running common env-prepare.'

$steps = @(
  'common/tools/env-prepare/prepare.ps1'
)

foreach ($step in $steps) {
  & (Join-Path $Context.CiRoot $step) -Context $Context
}

$platformPrepare = Join-Path $Context.CiRoot "platforms/$($Context.Platform)/tools/env-prepare/prepare.ps1"
if (Test-Path -LiteralPath $platformPrepare -PathType Leaf) {
  & $platformPrepare -Context $Context
}

Write-CiArtifacts -Context $Context
