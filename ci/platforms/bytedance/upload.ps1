[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

. (Join-Path $Context.CiRoot 'common/upload.ps1')

if (Test-CiUploadSkipped -Context $Context -Platform 'bytedance') {
  return
}

if (Invoke-CiCommandUpload -Context $Context -Platform 'bytedance') {
  return
}

if (& (Join-Path $Context.CiRoot 'platforms/bytedance/tools/tt-minigame-ide-cli/upload.ps1') -Context $Context) {
  return
}

Assert-CiUploadConfigured -Context $Context -Platform 'bytedance' -RequiredFields @('appId', 'bytedanceUploadEmail', 'bytedanceUploadPassword')
