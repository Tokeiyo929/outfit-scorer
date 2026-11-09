[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

if (-not (Test-Path -LiteralPath (Join-Path $Context.ProjectRoot 'project.json'))) {
  throw "project.json not found under project root: $($Context.ProjectRoot)"
}

Write-CiLog -Level INFO -Message "Profile loaded: project=$($Context.Profile.projectCode) channel=$($Context.Profile.channelCode) platform=$($Context.Platform)"
