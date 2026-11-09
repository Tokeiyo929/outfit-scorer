function Get-CocosCreatorPath {
  param([Parameter(Mandatory = $true)]$Profile)

  $version = [string]$Profile.cocosCreatorVersion
  if ([string]::IsNullOrWhiteSpace($version)) {
    throw 'profile.json missing required field: cocosCreatorVersion'
  }

  $envName = 'COCOS_CREATOR_' + ($version -replace '\.', '_')
  $value = [Environment]::GetEnvironmentVariable($envName)
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "Cocos Creator executable is not configured. Set environment variable $envName to the CocosCreator.exe path for Cocos Creator $version."
  }

  $creatorPath = $value
  if (Test-Path -LiteralPath $creatorPath -PathType Container) {
    $creatorPath = Join-Path $creatorPath 'CocosCreator.exe'
  }

  if (-not (Test-Path -LiteralPath $creatorPath -PathType Leaf)) {
    throw "Cocos Creator executable not found from $envName. Current value: $value. Set $envName to the CocosCreator.exe path for Cocos Creator $version."
  }

  return (Resolve-Path -LiteralPath $creatorPath).Path
}

function ConvertTo-CocosBuildPath {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$BuildRoot
  )

  $projectRootWithSlash = $ProjectRoot.TrimEnd('\', '/') + '\'
  $buildRootFullPath = [System.IO.Path]::GetFullPath($BuildRoot)
  if ($buildRootFullPath.StartsWith($projectRootWithSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
    return './' + $buildRootFullPath.Substring($projectRootWithSlash.Length).Replace('\', '/')
  }

  return $buildRootFullPath.Replace('\', '/')
}

function Write-CocosProgress {
  param(
    [AllowEmptyString()][string]$Line,
    [Parameter(Mandatory = $true)][hashtable]$State
  )

  if ([string]::IsNullOrWhiteSpace($Line)) {
    return
  }

  $message = ''
  $progress = 0

  if ($Line -match 'Initializing Editor') {
    $progress = 5
    $message = 'Starting Cocos Creator editor.'
  }
  elseif ($Line -match 'Initializing Asset Database') {
    $progress = 12
    $message = 'Initializing asset database.'
  }
  elseif ($Line -match 'Initializing project') {
    $progress = 20
    $message = 'Loading project.'
  }
  elseif ($Line -match 'Initializing Cocos2d') {
    $progress = 28
    $message = 'Initializing Cocos2d engine.'
  }
  elseif ($Line -match 'QuickCompiler rebuild finished|Init project script') {
    $progress = 35
    $message = 'Project scripts compiled.'
  }
  elseif ($Line -match 'Start to build platform') {
    $progress = 45
    $message = 'Starting platform build.'
  }
  elseif ($Line -match 'Start spawn build-worker') {
    $progress = 52
    $message = 'Starting build worker.'
  }
  elseif ($Line -match 'Compiling ') {
    $progress = 60
    $message = 'Compiling project assets.'
  }
  elseif ($Line -match 'Start build-assets in worker') {
    $progress = 65
    $message = 'Building asset bundles.'
  }
  elseif ($Line -match '--- build-asset:') {
    $State.assetBundleCount++
    if ($State.assetBundleCount -eq 1 -or $State.assetBundleCount % 5 -eq 0) {
      $progress = [Math]::Min(80, 65 + $State.assetBundleCount)
      $message = "Building asset bundles. Processed $($State.assetBundleCount)."
    }
  }
  elseif ($Line -match 'Finish build-assets in worker') {
    $progress = 80
    $message = "Asset bundle build finished. Processed $($State.assetBundleCount)."
  }
  elseif ($Line -match 'Start building plugin scripts') {
    $progress = 84
    $message = 'Building plugin scripts.'
  }
  elseif ($Line -match 'Generating main\.js') {
    $progress = 87
    $message = 'Generating main.js.'
  }
  elseif ($Line -match 'Generating html|generate game\.json|Generate project\.config\.json') {
    $progress = 89
    $message = 'Generating platform entry files.'
  }
  elseif ($Line -match 'build-finished|\[super-html\].*-- start --') {
    $progress = 93
    $message = 'Running post-build processors.'
  }
  elseif ($Line -match 'Built to ".+" successfully') {
    $progress = 100
    $message = 'Cocos Creator build finished successfully.'
  }

  if ($Line -match 'Warning:') {
    $State.warningCount++
  }
  if ($Line -match 'Uncaught Exception|Error:| failed | failed:') {
    $State.diagnosticLineCount++
  }

  if ($message -and $State.lastProgressMessage -ne $message) {
    $State.lastProgressMessage = $message
    Write-CiLog -Level INFO -Message ('Cocos progress ~{0}%: {1}' -f $progress, $message)
  }
}

function Invoke-CocosBuild {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Context,
    [Parameter(Mandatory = $true)][string]$Platform,
    [Parameter(Mandatory = $true)][string]$BuildOutputName,
    [Parameter(Mandatory = $true)][string]$Publisher,
    [string[]]$EntryCandidates = @()
  )

  $creatorPath = Get-CocosCreatorPath -Profile $Context.Profile
  $debug = if ([string]$Context.Profile.buildType -eq 'debug') { 'true' } else { 'false' }
  $buildRoot = Join-Path $Context.OutputDir 'build'
  $buildRootForCocos = ConvertTo-CocosBuildPath -ProjectRoot $Context.ProjectRoot -BuildRoot $buildRoot
  $buildOptions = "platform=$Platform;debug=$debug;sourceMaps=false;embedWebDebugger=false;buildPath=$buildRootForCocos"
  $cocosLog = Join-Path $Context.OutputDir 'cocos.log'
  $cocosErrLog = Join-Path $Context.OutputDir 'cocos.err.log'

  Write-CiLog -Level INFO -Message "Starting Cocos Creator $Platform build. Creator=$creatorPath BuildRoot=$buildRoot"

  $arguments = @(
    '--path', $Context.ProjectRoot,
    '--force',
    '--build', $buildOptions,
    '--quit'
  )

  Set-Content -LiteralPath $cocosLog -Value '' -Encoding UTF8
  Set-Content -LiteralPath $cocosErrLog -Value '' -Encoding UTF8

  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $cocosProgressState = @{
    assetBundleCount = 0
    warningCount = 0
    diagnosticLineCount = 0
    lastProgressMessage = ''
  }
  try {
    & $creatorPath @arguments 2>&1 | ForEach-Object {
      $line = [string]$_
      Add-Content -LiteralPath $cocosLog -Value $line -Encoding UTF8
      Write-CocosProgress -Line $line -State $cocosProgressState
    }
    $cocosExitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }

  if ($cocosExitCode -ne 0) {
    throw "Cocos $Platform build failed with exit code $cocosExitCode."
  }

  Write-CiLog -Level INFO -Message "Cocos log summary: warnings=$($cocosProgressState.warningCount) diagnostic-lines=$($cocosProgressState.diagnosticLineCount) fullLog=$cocosLog"

  $buildDir = Join-Path $buildRoot $BuildOutputName
  if (-not (Test-Path -LiteralPath $buildDir -PathType Container)) {
    throw "Cocos $Platform output directory not found: $buildDir"
  }

  $entryPath = ''
  foreach ($entryCandidate in $EntryCandidates) {
    $candidate = Join-Path $buildDir $entryCandidate
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      $entryPath = $candidate
      break
    }
  }
  if ($EntryCandidates.Count -gt 0 -and [string]::IsNullOrWhiteSpace($entryPath)) {
    throw "Cocos $Platform entry file not found. Checked: $($EntryCandidates -join ', ')"
  }

  $Context.Artifacts.buildDir = $buildDir
  $Context.Artifacts.entry = $entryPath
  $Context.Artifacts.publisher = $Publisher

  Write-CiLog -Level INFO -Message "$Platform build completed: $buildDir"
  Write-CiArtifacts -Context $Context
}
