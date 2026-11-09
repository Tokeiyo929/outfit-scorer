[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

. (Join-Path $Context.CiRoot 'common/upload.ps1')

if (Test-CiUploadSkipped -Context $Context -Platform 'wechatgame') {
  return
}

if (Invoke-CiCommandUpload -Context $Context -Platform 'wechatgame') {
  return
}

if (& (Join-Path $Context.CiRoot 'platforms/wechatgame/tools/miniprogram-ci/upload.ps1') -Context $Context) {
  return
}

Assert-CiUploadConfigured -Context $Context -Platform 'wechatgame' -RequiredFields @('appId', 'wechatPrivateKeyPathResolved', 'wechatRobot')
