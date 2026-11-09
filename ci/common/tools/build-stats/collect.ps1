[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

$buildDir = [string]$Context.Artifacts.buildDir
if ([string]::IsNullOrWhiteSpace($buildDir)) {
  Write-CiLog -Level WARN -Message 'Build artifact directory is empty; common after-build steps skipped.'
  $Context.Artifacts.afterBuildSkipped = @{
    reason = 'buildDir is empty'
  }
  Write-CiArtifacts -Context $Context
  return
}

if (-not (Test-Path -LiteralPath $buildDir -PathType Container)) {
  throw "Build artifact directory does not exist: $buildDir"
}

$files = Get-ChildItem -LiteralPath $buildDir -Recurse -File
$Context.Artifacts.fileCount = @($files).Count
$Context.Artifacts.packageSizeBytes = [int64](($files | Measure-Object -Property Length -Sum).Sum)

Write-CiArtifacts -Context $Context
