[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

Write-CiLog -Level INFO -Message 'Running common cleanup.'
Write-CiArtifacts -Context $Context
