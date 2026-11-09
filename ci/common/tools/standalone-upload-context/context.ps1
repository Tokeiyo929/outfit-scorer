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

function Get-CiUploadOutputRuns {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Platform
  )

  if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    return @()
  }

  return @(Get-ChildItem -LiteralPath $Root -Directory |
    Where-Object {
      $profilePath = Join-Path $_.FullName 'effective-profile.json'
      $artifactsPath = Join-Path $_.FullName 'artifacts.json'
      if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf) -or -not (Test-Path -LiteralPath $artifactsPath -PathType Leaf)) {
        return $false
      }

      try {
        $profile = ConvertFrom-CiJsonFile -Path $profilePath
        return ([string]$profile.platform -eq $Platform)
      }
      catch {
        return $false
      }
    } |
    Sort-Object LastWriteTime -Descending)
}

function Resolve-CiUploadOutputRun {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Platform,
    [string]$Run
  )

  $runs = Get-CiUploadOutputRuns -Root $Root -Platform $Platform
  if ($runs.Count -eq 0) {
    throw "No uploadable $Platform output directories found under: $Root"
  }

  if ([string]::IsNullOrWhiteSpace($Run)) {
    Write-Host "Available $Platform output runs:"
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

function New-CiStandaloneUploadContext {
  param(
    [Parameter(Mandatory = $true)][string]$CiRoot,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$Platform,
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [string]$OutputRun = '',
    [string]$SourceDir = ''
  )

  $OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
  $outputDir = Resolve-CiUploadOutputRun -Root $OutputRoot -Platform $Platform -Run $OutputRun
  $effectiveProfile = ConvertFrom-CiJsonFile -Path (Join-Path $outputDir 'effective-profile.json')
  $artifacts = ConvertTo-CiHashtable -Value (ConvertFrom-CiJsonFile -Path (Join-Path $outputDir 'artifacts.json'))

  $profile = $effectiveProfile
  if ($effectiveProfile.PSObject.Properties['bundleRoot'] -and -not [string]::IsNullOrWhiteSpace([string]$effectiveProfile.bundleRoot)) {
    $bundleRoot = [string]$effectiveProfile.bundleRoot
    if (Test-Path -LiteralPath (Join-Path $bundleRoot 'profile.json') -PathType Leaf) {
      $profile = Read-ProfileBundle -BundlePath $bundleRoot -Platform $Platform
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($SourceDir)) {
    $resolvedSourceDir = if ([System.IO.Path]::IsPathRooted($SourceDir)) {
      [System.IO.Path]::GetFullPath($SourceDir)
    }
    else {
      [System.IO.Path]::GetFullPath((Join-Path $outputDir $SourceDir))
    }
    $artifacts['buildDir'] = $resolvedSourceDir
  }
  elseif (-not $artifacts.ContainsKey('buildDir') -or [string]::IsNullOrWhiteSpace([string]$artifacts['buildDir'])) {
    $artifacts['buildDir'] = Join-Path (Join-Path $outputDir 'build') $Platform
  }

  if (-not (Test-Path -LiteralPath ([string]$artifacts['buildDir']) -PathType Container)) {
    throw "Build output directory not found: $($artifacts['buildDir'])"
  }

  $global:GameNexusCiLogFile = Join-Path $outputDir 'upload-retry.log'
  Set-Content -LiteralPath $global:GameNexusCiLogFile -Value '' -Encoding UTF8

  return @{
    CiRoot = $CiRoot
    ProjectRoot = $ProjectRoot
    ProfileBundle = [string]$profile.bundleRoot
    Platform = $Platform
    OutputRoot = $OutputRoot
    OutputDir = $outputDir
    BuildId = Split-Path -Leaf $outputDir
    Stage = 'upload'
    KeepTemp = $true
    StartedAt = (Get-Date).ToString('o')
    CurrentStage = 'upload'
    Profile = $profile
    EffectiveProfile = $effectiveProfile
    Artifacts = $artifacts
    Result = @{}
  }
}
