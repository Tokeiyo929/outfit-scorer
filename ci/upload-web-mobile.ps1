[CmdletBinding()]
param(
  [string]$OutputRun = '',
  [string]$OutputRoot = '',
  [string]$SourceDir = '',
  [switch]$List
)

$ErrorActionPreference = 'Stop'

$CiRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $CiRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $CiRoot 'output'
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)

. (Join-Path $CiRoot 'common/logging.ps1')
. (Join-Path $CiRoot 'common/result-writer.ps1')

function ConvertFrom-CiJsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Required file not found: $Path"
  }
  $json = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('NoEnumerate')) {
    return $json | ConvertFrom-Json -NoEnumerate
  }
  return $json | ConvertFrom-Json
}

function ConvertTo-CiHashtable {
  param([AllowNull()]$Value)

  if ($null -eq $Value) { return $null }
  if ($Value -is [System.Collections.IDictionary]) {
    $table = @{}
    foreach ($key in $Value.Keys) {
      $table[$key] = ConvertTo-CiHashtable -Value $Value[$key]
    }
    return $table
  }
  if ($Value -is [System.Array]) {
    return @($Value | ForEach-Object { ConvertTo-CiHashtable -Value $_ })
  }
  if ($Value -is [pscustomobject]) {
    $table = @{}
    foreach ($property in $Value.PSObject.Properties) {
      $table[$property.Name] = ConvertTo-CiHashtable -Value $property.Value
    }
    return $table
  }
  return $Value
}

function Get-WebMobileOutputRuns {
  param([Parameter(Mandatory = $true)][string]$Root)

  if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    return @()
  }

  return @(Get-ChildItem -LiteralPath $Root -Directory |
    Where-Object {
      $hasProfile = Test-Path -LiteralPath (Join-Path $_.FullName 'effective-profile.json') -PathType Leaf
      $hasArtifacts = Test-Path -LiteralPath (Join-Path $_.FullName 'artifacts.json') -PathType Leaf
      $hasProfile -and $hasArtifacts
    } |
    Sort-Object LastWriteTime -Descending)
}

function Resolve-WebMobileOutputRun {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$Run
  )

  $runs = Get-WebMobileOutputRuns -Root $Root
  if ($runs.Count -eq 0) {
    throw "No uploadable output directories found under: $Root"
  }

  if ([string]::IsNullOrWhiteSpace($Run)) {
    Write-Host 'Available web-mobile output runs:'
    $index = 1
    foreach ($item in ($runs | Select-Object -First 20)) {
      Write-Host ('  {0}. {1}  {2}' -f $index, $item.Name, $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
      $index += 1
    }
    $inputValue = Read-Host 'OutputRun [number/name/path] default 1'
    if ([string]::IsNullOrWhiteSpace($inputValue)) { $inputValue = '1' }
    $Run = $inputValue
  }

  $selected = $null
  $number = 0
  if ([int]::TryParse($Run, [ref]$number) -and $number -ge 1 -and $number -le $runs.Count) {
    $selected = $runs[$number - 1].FullName
  }
  elseif (Test-Path -LiteralPath $Run -PathType Container) {
    $selected = (Resolve-Path -LiteralPath $Run).Path
  }
  else {
    $candidate = Join-Path $Root $Run
    if (Test-Path -LiteralPath $candidate -PathType Container) {
      $selected = (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  if ([string]::IsNullOrWhiteSpace($selected)) {
    throw "OutputRun not found: $Run"
  }
  return $selected
}

$runs = Get-WebMobileOutputRuns -Root $OutputRoot
if ($List) {
  if ($runs.Count -eq 0) {
    Write-Host "No uploadable output directories found under: $OutputRoot"
    exit 0
  }
  $index = 1
  foreach ($item in $runs) {
    Write-Host ('{0}. {1}  {2}' -f $index, $item.Name, $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
    $index += 1
  }
  exit 0
}

$OutputDir = Resolve-WebMobileOutputRun -Root $OutputRoot -Run $OutputRun
$profile = ConvertFrom-CiJsonFile -Path (Join-Path $OutputDir 'effective-profile.json')
$artifacts = ConvertTo-CiHashtable -Value (ConvertFrom-CiJsonFile -Path (Join-Path $OutputDir 'artifacts.json'))

if ([string]$profile.platform -ne 'web-mobile') {
  throw "Selected output is not web-mobile. platform=$($profile.platform) output=$OutputDir"
}

if (-not [string]::IsNullOrWhiteSpace($SourceDir)) {
  $resolvedSourceDir = if ([System.IO.Path]::IsPathRooted($SourceDir)) {
    [System.IO.Path]::GetFullPath($SourceDir)
  }
  else {
    [System.IO.Path]::GetFullPath((Join-Path $OutputDir $SourceDir))
  }
  $artifacts['buildDir'] = $resolvedSourceDir
  $artifacts['entry'] = Join-Path $resolvedSourceDir 'index.html'
  $profile | Add-Member -NotePropertyName webPublisherSourceDir -NotePropertyValue $resolvedSourceDir -Force
}
elseif (-not $artifacts.ContainsKey('buildDir') -or [string]::IsNullOrWhiteSpace([string]$artifacts['buildDir'])) {
  $defaultBuildDir = Join-Path (Join-Path $OutputDir 'build') 'web-mobile'
  $artifacts['buildDir'] = $defaultBuildDir
  $artifacts['entry'] = Join-Path $defaultBuildDir 'index.html'
}

if (-not (Test-Path -LiteralPath ([string]$artifacts['buildDir']) -PathType Container)) {
  throw "Build output directory not found: $($artifacts['buildDir'])"
}

$global:GameNexusCiLogFile = Join-Path $OutputDir 'upload-retry.log'
Set-Content -LiteralPath $global:GameNexusCiLogFile -Value '' -Encoding UTF8

$Context = @{
  CiRoot = $CiRoot
  ProjectRoot = $ProjectRoot
  ProfileBundle = [string]$profile.bundleRoot
  Platform = 'web-mobile'
  OutputRoot = $OutputRoot
  OutputDir = $OutputDir
  BuildId = Split-Path -Leaf $OutputDir
  Stage = 'upload'
  KeepTemp = $true
  StartedAt = (Get-Date).ToString('o')
  CurrentStage = 'upload'
  Profile = $profile
  EffectiveProfile = $profile
  Artifacts = $artifacts
  Result = @{}
}

Write-CiLog -Level INFO -Message "Standalone web-mobile upload started. OutputDir=$OutputDir SourceDir=$($Context.Artifacts.buildDir)"
& (Join-Path $CiRoot 'platforms/web-mobile/tools/game-web-publisher/publish.ps1') -Context $Context | Out-Null
Write-CiLog -Level INFO -Message "Standalone web-mobile upload completed. previewUrl=$($Context.Artifacts.previewUrl)"

