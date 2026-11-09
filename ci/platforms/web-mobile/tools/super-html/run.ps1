[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

. (Join-Path $Context.CiRoot 'common/runtime-config-injection.ps1')

$buildDir = [string]$Context.Artifacts.buildDir
if ([string]::IsNullOrWhiteSpace($buildDir)) {
  Write-CiLog -Level WARN -Message 'super-html skipped because buildDir is empty.'
  return
}

if (-not (Test-Path -LiteralPath $buildDir -PathType Container)) {
  throw "super-html input build directory does not exist: $buildDir"
}

$superHtmlScript = Join-Path $Context.CiRoot 'common/tools/super-html/build_cocos.js'
if (-not (Test-Path -LiteralPath $superHtmlScript -PathType Leaf)) {
  throw "super-html script not found: $superHtmlScript"
}

$ensureDepsScript = Join-Path $Context.CiRoot 'common/tools/super-html/ensure-deps.ps1'
if (-not (Test-Path -LiteralPath $ensureDepsScript -PathType Leaf)) {
  throw "super-html dependency script not found: $ensureDepsScript"
}
& $ensureDepsScript | ForEach-Object {
  Write-CiLog -Level INFO -Message ([string]$_)
}

$superHtmlDir = Join-Path (Split-Path -Parent $buildDir) 'super-html'
$superHtmlLog = Join-Path $Context.OutputDir 'super-html.log'
$cocosVersion = if ($Context.Profile.PSObject.Properties['cocosCreatorVersion']) { [string]$Context.Profile.cocosCreatorVersion } else { '' }

Write-CiLog -Level INFO -Message "Running super-html after image compression. input=$buildDir output=$superHtmlDir"

$superHtmlArgs = @(
  $superHtmlScript,
  '--project', $Context.ProjectRoot,
  '--input', $buildDir,
  '--output', $superHtmlDir
)
if (-not [string]::IsNullOrWhiteSpace($cocosVersion)) {
  $superHtmlArgs += @('--version', $cocosVersion)
}

$superHtmlOutput = & node @superHtmlArgs 2>&1 | ForEach-Object {
  Write-Host $_
  $_
}
$superHtmlExitCode = $LASTEXITCODE
$superHtmlOutput | Set-Content -LiteralPath $superHtmlLog -Encoding UTF8

if ($superHtmlExitCode -ne 0) {
  $Context.Artifacts.superHtml = @{
    status = 'FAILED'
    inputDir = $buildDir
    outputDir = $superHtmlDir
    logPath = $superHtmlLog
  }
  Write-CiArtifacts -Context $Context
  throw "super-html failed with exit code $superHtmlExitCode. See $superHtmlLog"
}

$htmlFiles = @()
if (Test-Path -LiteralPath $superHtmlDir -PathType Container) {
  $htmlFiles = @(Get-ChildItem -LiteralPath $superHtmlDir -Recurse -File -Filter '*.html' | ForEach-Object {
      @{
        path = $_.FullName
        sizeBytes = [int64]$_.Length
      }
    })
}

$Context.Artifacts.superHtml = @{
  status = 'SUCCESS'
  inputDir = $buildDir
  outputDir = $superHtmlDir
  logPath = $superHtmlLog
  obfuscator = $false
  fileCount = $htmlFiles.Count
  totalBytes = [int64](($htmlFiles | ForEach-Object { $_.sizeBytes } | Measure-Object -Sum).Sum)
  files = $htmlFiles
}
Write-CiArtifacts -Context $Context
Write-CiLog -Level INFO -Message "super-html completed. files=$($Context.Artifacts.superHtml.fileCount) totalBytes=$($Context.Artifacts.superHtml.totalBytes)"

Invoke-CiRuntimeConfigInjection -Context $Context -BuildDir $superHtmlDir -InlineHtmlOnly
