[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

. (Join-Path $Context.CiRoot 'common/tools/env-prepare/lib.ps1')

function Test-MiniprogramCiAvailable {
  $npm = Get-CiRequiredCommand -Name 'npm' -InstallHint 'Install Node.js first.'

  $globalRoot = ''
  $oldErrorActionPreference = $ErrorActionPreference
  $nativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
  $hadNativePreference = $null -ne $nativePreference
  $oldNativePreference = if ($hadNativePreference) { $nativePreference.Value } else { $null }
  try {
    $ErrorActionPreference = 'Continue'
    if ($hadNativePreference) {
      Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false -Scope Local
    }
    $globalRoot = ((& $npm.Source root -g 2>$null | Select-Object -First 1) -as [string]).Trim()
  }
  catch {
    return $false
  }
  finally {
    $ErrorActionPreference = $oldErrorActionPreference
    if ($hadNativePreference) {
      Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $oldNativePreference -Scope Local
    }
  }

  if ([string]::IsNullOrWhiteSpace($globalRoot)) { return $false }

  $modulePath = Join-Path $globalRoot 'miniprogram-ci'
  return (Test-Path -LiteralPath $modulePath -PathType Container)
}

if (-not (Test-CiEnvStage -Context $Context -Stages @('all', 'env-prepare', 'upload'))) {
  return
}

if (-not [bool]$Context.Profile.uploadEnabled) {
  Write-CiLog -Level INFO -Message 'wechatgame upload dependency setup skipped because profile.uploadEnabled=false.'
  return
}

Get-CiRequiredCommand -Name 'node' -InstallHint 'Install Node.js first.' | Out-Null
Get-CiRequiredCommand -Name 'npm' -InstallHint 'Install Node.js first.' | Out-Null

if (Test-MiniprogramCiAvailable) {
  Write-CiLog -Level INFO -Message 'wechatgame miniprogram-ci dependency is ready.'
  return
}

Invoke-CiNpmGlobalInstall -PackageName 'miniprogram-ci' -Description 'Install wechatgame miniprogram-ci'

$available = $false
for ($i = 0; $i -lt 5; $i++) {
  if (Test-MiniprogramCiAvailable) {
    $available = $true
    break
  }
  Start-Sleep -Seconds 2
}

if (-not $available) {
  throw 'miniprogram-ci is still unavailable after npm global install.'
}

Write-CiLog -Level INFO -Message 'wechatgame miniprogram-ci dependency installed.'
