[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

. (Join-Path $Context.CiRoot 'common/upload.ps1')

if (Test-CiUploadSkipped -Context $Context -Platform 'web-mobile') {
  return
}

$publisher = & (Join-Path $Context.CiRoot 'platforms/web-mobile/tools/game-web-publisher/publish.ps1') -Context $Context
if ($publisher) {
  return
}

if (Invoke-CiWebCosUpload -Context $Context) {
  return
}

if (Invoke-CiCommandUpload -Context $Context -Platform 'web-mobile') {
  return
}

Assert-CiUploadConfigured -Context $Context -Platform 'web-mobile'
