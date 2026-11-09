[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

$buildDir = [string]$Context.Artifacts.buildDir
if ([string]::IsNullOrWhiteSpace($buildDir)) {
  return
}

$logoPath = if ($Context.Profile.PSObject.Properties['logoPathResolved']) { [string]$Context.Profile.logoPathResolved } else { '' }
if (-not [string]::IsNullOrWhiteSpace($logoPath)) {
  $logoInjectScript = Join-Path $Context.CiRoot 'common/tools/logo-inject/inject_logo.js'
  if (-not (Test-Path -LiteralPath $logoInjectScript -PathType Leaf)) {
    throw "Logo injection script not found: $logoInjectScript"
  }

  $logoTargetAssetPath = if ($Context.Profile.PSObject.Properties['logoTargetAssetPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Context.Profile.logoTargetAssetPath)) {
    [string]$Context.Profile.logoTargetAssetPath
  }
  else {
    'Load/Logo.png'
  }

  Write-CiLog -Level INFO -Message "Injecting logo. source=$logoPath targetAsset=$logoTargetAssetPath"
  $logoInjectOutput = & node $logoInjectScript --project $Context.ProjectRoot --build-dir $buildDir --logo $logoPath --target-asset $logoTargetAssetPath 2>&1
  $logoInjectExitCode = $LASTEXITCODE
  $logoInjectLog = Join-Path $Context.OutputDir 'logo-inject.log'
  $logoInjectOutput | Set-Content -LiteralPath $logoInjectLog -Encoding UTF8

  if ($logoInjectExitCode -ne 0) {
    $Context.Artifacts.logoInjection = @{
      status = 'FAILED'
      sourceLogoPath = $logoPath
      targetAssetPath = $logoTargetAssetPath
      logPath = $logoInjectLog
    }
    Write-CiArtifacts -Context $Context
    throw "Logo injection failed with exit code $logoInjectExitCode. See $logoInjectLog"
  }

  try {
    $logoInjectReport = (($logoInjectOutput -join [Environment]::NewLine) | ConvertFrom-Json)
    $Context.Artifacts.logoInjection = @{
      status = 'SUCCESS'
      sourceLogoPath = [string]$logoInjectReport.sourceLogoPath
      targetAssetPath = [string]$logoInjectReport.targetAssetPath
      targetUuid = [string]$logoInjectReport.targetUuid
      outputPath = [string]$logoInjectReport.outputPath
      beforeBytes = [int64]$logoInjectReport.beforeBytes
      afterBytes = [int64]$logoInjectReport.afterBytes
      logPath = $logoInjectLog
    }
    Write-CiLog -Level INFO -Message "Logo injected. output=$($logoInjectReport.outputPath) beforeBytes=$($logoInjectReport.beforeBytes) afterBytes=$($logoInjectReport.afterBytes)"
  }
  catch {
    $Context.Artifacts.logoInjection = @{
      status = 'SUCCESS_UNPARSED'
      sourceLogoPath = $logoPath
      targetAssetPath = $logoTargetAssetPath
      logPath = $logoInjectLog
    }
    Write-CiLog -Level WARN -Message "Logo injected, but report could not be parsed. See $logoInjectLog"
  }
}
else {
  $Context.Artifacts.logoInjection = @{
    status = 'SKIPPED'
    reason = 'profile.logoPath is empty'
  }
  Write-CiLog -Level INFO -Message 'Logo injection skipped because profile.logoPath is empty.'
}

Write-CiArtifacts -Context $Context
