[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

Write-CiLog -Level INFO -Message 'Running web-mobile build.'

. (Join-Path $Context.CiRoot 'common/cocos-build.ps1')

Invoke-CocosBuild -Context $Context -Platform 'web-mobile' -BuildOutputName 'web-mobile' -Publisher 'cocos/web-mobile' -EntryCandidates @('index.html')
