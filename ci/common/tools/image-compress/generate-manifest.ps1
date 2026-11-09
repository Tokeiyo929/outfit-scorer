[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

$Context.Artifacts.imageCompressionManifest = @{
  status = 'NOT_RUN'
}

if ([bool]$Context.Profile.compressImages) {
  $manifestScript = Join-Path $Context.ProjectRoot 'packages/image-compress/scripts/generate_manifest.js'
  $manifestPath = Join-Path $Context.ProjectRoot 'temp/image-compress.manifest.json'
  $manifestLog = Join-Path $Context.OutputDir 'image-compress-manifest.log'

  if (Test-Path -LiteralPath $manifestScript -PathType Leaf) {
    Write-CiLog -Level INFO -Message 'Generating image compression manifest before build.'
    $manifestOutput = & node $manifestScript $Context.ProjectRoot 2>&1
    $manifestExitCode = $LASTEXITCODE
    $manifestOutput | Set-Content -LiteralPath $manifestLog -Encoding UTF8

    if ($manifestExitCode -ne 0) {
      throw "Image compression manifest generation failed with exit code $manifestExitCode. See $manifestLog"
    }

    $summary = $null
    try {
      $summary = (($manifestOutput -join [Environment]::NewLine) | ConvertFrom-Json)
    }
    catch {
    }

    $Context.Artifacts.imageCompressionManifest = @{
      status = 'SUCCESS'
      manifestPath = $manifestPath
      logPath = $manifestLog
      summary = $summary
    }

    if ($summary) {
      Write-CiLog -Level INFO -Message "Image compression manifest generated. atlases=$($summary.atlases) atlasSources=$($summary.atlasSources) images=$($summary.images)"
    }
    else {
      Write-CiLog -Level INFO -Message "Image compression manifest generated: $manifestPath"
    }
  }
  else {
    $Context.Artifacts.imageCompressionManifest = @{
      status = 'SKIPPED'
      reason = 'image-compress manifest script not found'
    }
    Write-CiLog -Level WARN -Message "Image compression manifest skipped because script was not found: $manifestScript"
  }
}
else {
  $Context.Artifacts.imageCompressionManifest = @{
    status = 'SKIPPED'
    reason = 'profile.compressImages=false'
  }
  Write-CiLog -Level INFO -Message 'Image compression manifest skipped by profile.compressImages=false.'
}
