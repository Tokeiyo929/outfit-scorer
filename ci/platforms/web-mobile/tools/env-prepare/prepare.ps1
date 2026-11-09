[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

. (Join-Path $Context.CiRoot 'common/tools/env-prepare/lib.ps1')

if (-not (Test-CiEnvStage -Context $Context -Stages @('all', 'env-prepare', 'upload'))) {
  return
}

if (-not [bool]$Context.Profile.uploadEnabled) {
  Write-CiLog -Level INFO -Message 'web-mobile upload dependency setup skipped because profile.uploadEnabled=false.'
  return
}

$configured = ''
if ($Context.Profile.PSObject.Properties['webPublisherPython']) {
  $configured = [string]$Context.Profile.webPublisherPython
}

$python = Get-CiDefaultPythonCommand -ConfiguredPython $configured
Test-CiPythonCommand -Python $python -Purpose 'web-mobile game-web-publisher'
