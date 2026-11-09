[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

Write-CiLog -Level INFO -Message 'Running bytedance build.'

. (Join-Path $Context.CiRoot 'common/cocos-build.ps1')

Invoke-CocosBuild -Context $Context -Platform 'bytedance' -BuildOutputName 'bytedance' -Publisher 'cocos/bytedance' -EntryCandidates @('game.js', 'project.config.json')
