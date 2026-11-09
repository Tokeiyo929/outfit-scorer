[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ProfileBundle,

  [Parameter(Mandatory = $true)]
  [ValidateSet('web-mobile', 'wechatgame', 'bytedance')]
  [string]$Platform,

  [ValidateSet('all', 'env-prepare', 'before-build', 'build', 'after-build', 'upload', 'cleanup')]
  [string]$Stage = 'all',

  [string]$OutputDir = '',
  [string]$BuildId = '',
  [switch]$KeepTemp
)

$ErrorActionPreference = 'Stop'

$CiRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $CiRoot
if (-not $OutputDir) {
  $OutputDir = Join-Path $CiRoot 'output'
}

. (Join-Path $CiRoot 'common/logging.ps1')
. (Join-Path $CiRoot 'common/profile-bundle.ps1')
. (Join-Path $CiRoot 'common/result-writer.ps1')
. (Join-Path $CiRoot 'common/notification.ps1')

function Get-CiProjectLockName {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)

  $bytes = [Text.Encoding]::UTF8.GetBytes([System.IO.Path]::GetFullPath($ProjectRoot).ToLowerInvariant())
  $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  $hex = -join ($hash | ForEach-Object { $_.ToString('x2') })
  return "Global\GameNexusCi-$hex"
}

function Invoke-CiScript {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][hashtable]$Context
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Required CI script not found: $Path"
  }

  & $Path -Context $Context
}

function Invoke-OptionalCiScript {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][hashtable]$Context
  )

  if (Test-Path -LiteralPath $Path) {
    & $Path -Context $Context
  }
}

function Invoke-CiNotificationSafely {
  param([Parameter(Mandatory = $true)][hashtable]$Context)

  try {
    Invoke-CiNotification -Context $Context
  }
  catch {
    Write-CiLog -Level WARN -Message "Notification step failed: $($_.Exception.Message)"
  }
}

function Resolve-ProfileBundleArgument {
  param(
    [Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][string]$CiRoot
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    throw 'ProfileBundle cannot be empty.'
  }

  if (Test-Path -LiteralPath $Value -PathType Container) {
    return (Resolve-Path -LiteralPath $Value).Path
  }

  if ([System.IO.Path]::IsPathRooted($Value)) {
    return [System.IO.Path]::GetFullPath($Value)
  }

  $profileRoot = Join-Path $CiRoot 'profiles'
  $profileBundlePath = Join-Path $profileRoot $Value
  return [System.IO.Path]::GetFullPath($profileBundlePath)
}

function ConvertTo-SafePathName {
  param([Parameter(Mandatory = $true)][string]$Value)

  $safeName = $Value
  foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
    $safeName = $safeName.Replace($char, '-')
  }
  $safeName = $safeName -replace '\s+', '-'
  $safeName = $safeName.Trim('.', '-', ' ')

  if ([string]::IsNullOrWhiteSpace($safeName)) {
    return 'run'
  }
  return $safeName
}

function New-CiRunOutputDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [Parameter(Mandatory = $true)][string]$RunName
  )

  New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

  $safeRunName = ConvertTo-SafePathName -Value $RunName
  $candidate = Join-Path $OutputRoot $safeRunName
  $index = 1
  while (Test-Path -LiteralPath $candidate) {
    $candidate = Join-Path $OutputRoot ('{0}-{1:000}' -f $safeRunName, $index)
    $index++
  }

  New-Item -ItemType Directory -Force -Path $candidate | Out-Null
  return (Resolve-Path -LiteralPath $candidate).Path
}

$ResolvedProfileBundle = Resolve-ProfileBundleArgument -Value $ProfileBundle -CiRoot $CiRoot
$profileName = Split-Path -Leaf $ResolvedProfileBundle
$resolvedBuildId = $BuildId
if ([string]::IsNullOrWhiteSpace($resolvedBuildId)) {
  $resolvedBuildId = '{0}-{1}-{2}-{3}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $profileName, $Platform, $Stage
}

$OutputRoot = [System.IO.Path]::GetFullPath($OutputDir)
$RunOutputDir = New-CiRunOutputDirectory -OutputRoot $OutputRoot -RunName $resolvedBuildId

$Context = @{
  CiRoot = $CiRoot
  ProjectRoot = $ProjectRoot
  ProfileBundle = $ResolvedProfileBundle
  Platform = $Platform
  OutputRoot = $OutputRoot
  OutputDir = $RunOutputDir
  BuildId = $resolvedBuildId
  Stage = $Stage
  KeepTemp = [bool]$KeepTemp
  StartedAt = (Get-Date).ToString('o')
  CurrentStage = 'init'
  Profile = $null
  EffectiveProfile = $null
  Artifacts = @{
    buildDir = ''
    packagePath = ''
    packageSizeBytes = 0
    uploadStatus = 'NOT_RUN'
    previewUrl = ''
    qrcodePath = ''
    compressionStats = @{}
  }
  Result = @{}
}

Initialize-CiLog -OutputDir $Context.OutputDir

$exitCode = 0
$cleanupErrors = @()
$ciMutex = New-Object System.Threading.Mutex($false, (Get-CiProjectLockName -ProjectRoot $ProjectRoot))
$ciLockTaken = $false

try {
  Write-CiLog -Level INFO -Message "GameNexus project CI started. Platform=$Platform Stage=$Stage OutputDir=$($Context.OutputDir)"
  Write-CiLog -Level INFO -Message 'Waiting for project CI lock.'
  $ciLockTaken = $ciMutex.WaitOne()
  Write-CiLog -Level INFO -Message 'Project CI lock acquired.'

  $Context.CurrentStage = 'profile'
  $Context.Profile = Read-ProfileBundle -BundlePath $Context.ProfileBundle -Platform $Context.Platform
  $Context.EffectiveProfile = Copy-ProfileForOutput -Profile $Context.Profile
  $Context.EffectiveProfile | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $Context.OutputDir 'effective-profile.json') -Encoding UTF8

  Initialize-CiResult -Context $Context

  $platform = [string]$Context.Platform
  $platformRoot = Join-Path (Join-Path $CiRoot 'platforms') $platform
  $platformAfterBuildScript = Join-Path $platformRoot 'after-build.ps1'

  $runEnvPrepare = $Stage -ne 'cleanup'
  $runBefore = $Stage -in @('all', 'before-build')
  $runBuild = $Stage -in @('all', 'build')
  $runAfter = $Stage -in @('all', 'after-build')
  $runUpload = $Stage -in @('all', 'upload')
  $runCleanupOnly = $Stage -eq 'cleanup'

  if ($runEnvPrepare) {
    $Context.CurrentStage = 'env-prepare'
    Invoke-CiScript -Path (Join-Path $CiRoot 'common/env-prepare.ps1') -Context $Context
  }

  if ($runBefore) {
    $Context.CurrentStage = 'before-build'
    Invoke-CiScript -Path (Join-Path $CiRoot 'common/before-build.ps1') -Context $Context
  }

  if ($runBuild) {
    $Context.CurrentStage = 'build'
    Invoke-CiScript -Path (Join-Path $platformRoot 'build.ps1') -Context $Context
  }

  if ($runAfter) {
    $Context.CurrentStage = 'after-build'
    Invoke-CiScript -Path (Join-Path $CiRoot 'common/after-build.ps1') -Context $Context
    Invoke-OptionalCiScript -Path $platformAfterBuildScript -Context $Context
  }

  if ($runUpload) {
    $Context.CurrentStage = 'upload'
    Invoke-CiScript -Path (Join-Path $platformRoot 'upload.ps1') -Context $Context
  }

  if ($runCleanupOnly) {
    $Context.CurrentStage = 'cleanup'
  }

  $Context.CurrentStage = 'cleanup'
  Invoke-CiScript -Path (Join-Path $CiRoot 'common/cleanup.ps1') -Context $Context

  $Context.CurrentStage = 'complete'
  Write-CiLog -Level INFO -Message 'GameNexus project CI completed successfully.'
  Complete-CiResult -Context $Context -Status 'SUCCESS' -ExitCode 0 -ErrorCode '' -ErrorMessage ''
  Invoke-CiNotificationSafely -Context $Context
}
catch {
  $exitCode = 1
  $message = $_.Exception.Message
  Write-CiLog -Level ERROR -Message $message

  try {
    $Context.CurrentStage = 'cleanup'
    Invoke-CiScript -Path (Join-Path $CiRoot 'common/cleanup.ps1') -Context $Context
  }
  catch {
    $cleanupErrors += $_.Exception.Message
  }

  if ($cleanupErrors.Count -gt 0) {
    $message = $message + " Cleanup errors: " + ($cleanupErrors -join ' | ')
  }

  Complete-CiResult -Context $Context -Status 'FAILED' -ExitCode 1 -ErrorCode 'CI_FAILED' -ErrorMessage $message
  Invoke-CiNotificationSafely -Context $Context
}
finally {
  if ($ciLockTaken) {
    $ciMutex.ReleaseMutex()
    Write-CiLog -Level INFO -Message 'Project CI lock released.'
  }
  if ($ciMutex) {
    $ciMutex.Dispose()
  }
}

exit $exitCode
