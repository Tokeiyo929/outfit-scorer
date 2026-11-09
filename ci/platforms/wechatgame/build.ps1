[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

Write-CiLog -Level INFO -Message 'Running wechatgame build.'

. (Join-Path $Context.CiRoot 'common/cocos-build.ps1')

Invoke-CocosBuild -Context $Context -Platform 'wechatgame' -BuildOutputName 'wechatgame' -Publisher 'cocos/wechatgame' -EntryCandidates @('game.js', 'project.config.json')
