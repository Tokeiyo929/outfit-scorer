[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

Write-CiLog -Level INFO -Message 'Running web-mobile after-build.'

$steps = @(
  'platforms/web-mobile/tools/super-html/run.ps1'
)

foreach ($step in $steps) {
  & (Join-Path $Context.CiRoot $step) -Context $Context
}
