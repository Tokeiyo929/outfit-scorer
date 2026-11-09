[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ProfileBundle,

  [string]$OutputDir = '',
  [string]$ProfileServiceUrl = '',
  [string]$ProjectCode = '',
  [string]$ChannelCode = '',
  [string]$Platform = '',
  [string]$Version = '',
  [switch]$Json
)

$ErrorActionPreference = 'Stop'

$CiRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $CiRoot

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

  return [System.IO.Path]::GetFullPath((Join-Path (Join-Path $CiRoot 'profiles') $Value))
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
    return 'profile'
  }
  return $safeName
}

function Copy-ProfileBundleDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  $sourceRoot = [System.IO.Path]::GetFullPath($Source).TrimEnd([char[]]@('\', '/'))
  $destinationRoot = [System.IO.Path]::GetFullPath($Destination).TrimEnd([char[]]@('\', '/'))

  if ($sourceRoot.Equals($destinationRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $destinationRoot
  }

  New-Item -ItemType Directory -Force -Path $destinationRoot | Out-Null
  Copy-Item -LiteralPath (Join-Path $sourceRoot '*') -Destination $destinationRoot -Recurse -Force
  return $destinationRoot
}

if (-not [string]::IsNullOrWhiteSpace($ProfileServiceUrl)) {
  Write-Warning 'Remote Profile service fetch is not implemented yet. Falling back to local ProfileBundle resolution.'
}

$resolvedSource = Resolve-ProfileBundleArgument -Value $ProfileBundle -CiRoot $CiRoot
if (-not (Test-Path -LiteralPath $resolvedSource -PathType Container)) {
  throw "ProfileBundle directory not found: $resolvedSource"
}

$sourceProfileJson = Join-Path $resolvedSource 'profile.json'
if (-not (Test-Path -LiteralPath $sourceProfileJson -PathType Leaf)) {
  throw "profile.json not found in ProfileBundle: $sourceProfileJson"
}

$resolvedProfileBundle = $resolvedSource
if (-not [string]::IsNullOrWhiteSpace($OutputDir)) {
  $targetDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    [System.IO.Path]::GetFullPath($OutputDir)
  }
  else {
    [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $OutputDir))
  }

  $leafName = Split-Path -Leaf $resolvedSource
  if ([string]::IsNullOrWhiteSpace([System.IO.Path]::GetFileName($targetDir))) {
    $targetDir = Join-Path $targetDir (ConvertTo-SafePathName -Value $leafName)
  }

  $resolvedProfileBundle = Copy-ProfileBundleDirectory -Source $resolvedSource -Destination $targetDir
}

$result = [ordered]@{
  status = 'SUCCESS'
  mode = 'local-placeholder'
  profileBundle = $resolvedProfileBundle
  sourceProfileBundle = $resolvedSource
  profileJson = Join-Path $resolvedProfileBundle 'profile.json'
  profileServiceUrl = $ProfileServiceUrl
  projectCode = $ProjectCode
  channelCode = $ChannelCode
  platform = $Platform
  version = $Version
}

if (-not [string]::IsNullOrWhiteSpace($OutputDir)) {
  $resultPath = Join-Path $resolvedProfileBundle 'profile-pull-result.json'
  $result['resultPath'] = $resultPath
  $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}

if ($Json) {
  $result | ConvertTo-Json -Depth 10
}
else {
  Write-Host "PROFILE_BUNDLE=$resolvedProfileBundle"
  Write-Host "PROFILE_PULL_MODE=local-placeholder"
}
