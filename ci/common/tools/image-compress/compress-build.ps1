[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

$buildDir = [string]$Context.Artifacts.buildDir
if ([string]::IsNullOrWhiteSpace($buildDir)) {
  return
}

$Context.Artifacts.compressionStats = @{
  status = 'NOT_RUN'
}

if ([bool]$Context.Profile.compressImages) {
  $compressScript = Join-Path $Context.ProjectRoot 'packages/image-compress/scripts/postbuild_compress.js'
  if (Test-Path -LiteralPath $compressScript -PathType Leaf) {
    Write-CiLog -Level INFO -Message "Running image compression for buildDir=$buildDir"
    $previousAllowExternalBuildDir = [Environment]::GetEnvironmentVariable('GAMENEXUS_CI_ALLOW_EXTERNAL_BUILD_DIR')
    try {
      [Environment]::SetEnvironmentVariable('GAMENEXUS_CI_ALLOW_EXTERNAL_BUILD_DIR', '1', 'Process')
      $compressOutput = & node $compressScript --project $Context.ProjectRoot --build-dir $buildDir 2>&1
      $compressExitCode = $LASTEXITCODE
    }
    finally {
      [Environment]::SetEnvironmentVariable('GAMENEXUS_CI_ALLOW_EXTERNAL_BUILD_DIR', $previousAllowExternalBuildDir, 'Process')
    }
    $compressLog = Join-Path $Context.OutputDir 'image-compress.log'
    $compressOutput | Set-Content -LiteralPath $compressLog -Encoding UTF8

    if ($compressExitCode -ne 0) {
      throw "Image compression failed with exit code $compressExitCode. See $compressLog"
    }

    $jsonText = ($compressOutput -join [Environment]::NewLine)
    try {
      $stats = $jsonText | ConvertFrom-Json
      $Context.Artifacts.compressionStats = @{
        status = 'SUCCESS'
        totalImages = [int]$stats.totalImages
        compressed = [int]$stats.compressed
        cacheHits = [int]$stats.cacheHits
        skipped = [int]$stats.skipped
        errors = [int]$stats.errors
        savedBytes = [int64]$stats.savedBytes
        logPath = $compressLog
      }
      Write-CiLog -Level INFO -Message "Image compression completed. total=$($stats.totalImages) compressed=$($stats.compressed) savedBytes=$($stats.savedBytes)"
    }
    catch {
      $Context.Artifacts.compressionStats = @{
        status = 'SUCCESS_UNPARSED'
        logPath = $compressLog
      }
      Write-CiLog -Level WARN -Message "Image compression completed, but report could not be parsed. See $compressLog"
    }
  }
  else {
    $Context.Artifacts.compressionStats = @{
      status = 'SKIPPED'
      reason = 'image-compress script not found'
    }
    Write-CiLog -Level WARN -Message "Image compression skipped because script was not found: $compressScript"
  }
}
else {
  $Context.Artifacts.compressionStats = @{
    status = 'SKIPPED'
    reason = 'profile.compressImages=false'
  }
  Write-CiLog -Level INFO -Message 'Image compression skipped by profile.compressImages=false.'
}

Write-CiArtifacts -Context $Context
