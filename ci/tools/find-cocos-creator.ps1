[CmdletBinding()]
param(
  [string]$Version = '',
  [switch]$AllDrives,
  [switch]$SetUser,
  [switch]$SetMachine,
  [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'

function Get-CocosCreatorEnvName {
  param([Parameter(Mandatory = $true)][string]$Version)
  return 'COCOS_CREATOR_' + ($Version -replace '\.', '_')
}

function Get-CocosCreatorVersionFromPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  $patterns = @(
    '[\\/](?<version>\d+\.\d+\.\d+)[\\/]CocosCreator\.exe$',
    '[\\/]app-(?<version>\d+\.\d+\.\d+)[\\/]CocosCreator\.exe$',
    '[\\/]CocosCreator[_-](?<version>\d+\.\d+\.\d+)[\\/]CocosCreator\.exe$'
  )
  foreach ($pattern in $patterns) {
    $match = [regex]::Match($Path, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
      return $match.Groups['version'].Value
    }
  }

  $file = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
  if ($file) {
    $productVersion = [string]$file.VersionInfo.ProductVersion
    if ($productVersion -match '^\d+\.\d+\.\d+') {
      return $matches[0]
    }
    $fileVersion = [string]$file.VersionInfo.FileVersion
    if ($fileVersion -match '^\d+\.\d+\.\d+') {
      return $matches[0]
    }
  }

  return ''
}

function Add-CocosCandidate {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.ArrayList]$Candidates,
    [AllowEmptyString()][string]$Path,
    [Parameter(Mandatory = $true)][string]$Source,
    [string]$Version = ''
  )

  if ([string]::IsNullOrWhiteSpace($Path)) { return }

  $candidate = $Path
  if (Test-Path -LiteralPath $candidate -PathType Container) {
    $candidate = Join-Path $candidate 'CocosCreator.exe'
  }

  if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { return }

  $resolved = (Resolve-Path -LiteralPath $candidate).Path
  foreach ($item in $Candidates) {
    if ([string]$item.Path -ieq $resolved) { return }
  }

  $detectedVersion = Get-CocosCreatorVersionFromPath -Path $resolved
  if (-not [string]::IsNullOrWhiteSpace($Version) -and $detectedVersion -ne $Version) {
    return
  }

  $score = 0
  if (-not [string]::IsNullOrWhiteSpace($detectedVersion)) { $score += 100 }
  if (-not [string]::IsNullOrWhiteSpace($Version) -and $detectedVersion -eq $Version) { $score += 100 }
  if ($Source -match '^env:') { $score += 80 }
  elseif ($Source -eq 'cocos-dashboard') { $score += 70 }
  elseif ($Source -eq 'path') { $score += 50 }
  elseif ($Source -eq 'common') { $score += 40 }
  elseif ($Source -eq 'all-drives') { $score += 10 }

  [void]$Candidates.Add([pscustomobject]@{
    Path = $resolved
    Source = $Source
    Version = $detectedVersion
    Score = $score
  })
}

function Add-CocosCandidatesFromDirectory {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.ArrayList]$Candidates,
    [Parameter(Mandatory = $true)][string]$Directory,
    [Parameter(Mandatory = $true)][string]$Source,
    [string]$Version = ''
  )

  if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return }
  $matches = @(Get-ChildItem -LiteralPath $Directory -Filter CocosCreator.exe -File -Recurse -ErrorAction SilentlyContinue)
  foreach ($match in $matches) {
    Add-CocosCandidate -Candidates $Candidates -Path $match.FullName -Source $Source -Version $Version
  }
}

function Find-CocosCreatorCandidates {
  param(
    [string]$Version = '',
    [switch]$AllDrives
  )

  $candidates = [System.Collections.ArrayList]::new()

  $knownEnvNames = @()
  if (-not [string]::IsNullOrWhiteSpace($Version)) {
    $knownEnvNames += Get-CocosCreatorEnvName -Version $Version
  }
  $knownEnvNames += @(
    'COCOS_CREATOR_2_4_11',
    'COCOS_CREATOR_2_4_10',
    'COCOS_CREATOR_3_8_0',
    'COCOS_CREATOR_3_8_1',
    'COCOS_CREATOR_3_8_2',
    'COCOS_CREATOR_3_8_3',
    'COCOS_CREATOR_3_8_4',
    'COCOS_CREATOR_3_8_5',
    'COCOS_CREATOR_3_8_6',
    'COCOS_CREATOR_3_8_7'
  )
  foreach ($envName in ($knownEnvNames | Select-Object -Unique)) {
    Add-CocosCandidate -Candidates $candidates -Path ([Environment]::GetEnvironmentVariable($envName, 'Process')) -Source "env:$envName(process)" -Version $Version
    Add-CocosCandidate -Candidates $candidates -Path ([Environment]::GetEnvironmentVariable($envName, 'User')) -Source "env:$envName(user)" -Version $Version
    Add-CocosCandidate -Candidates $candidates -Path ([Environment]::GetEnvironmentVariable($envName, 'Machine')) -Source "env:$envName(machine)" -Version $Version
  }

  Add-CocosCandidatesFromDirectory -Candidates $candidates -Directory 'C:\ProgramData\cocos\editors\Creator' -Source 'cocos-dashboard' -Version $Version
  if ($env:LOCALAPPDATA) {
    Add-CocosCandidatesFromDirectory -Candidates $candidates -Directory (Join-Path $env:LOCALAPPDATA 'CocosCreator') -Source 'common' -Version $Version
  }
  Add-CocosCandidate -Candidates $candidates -Path "C:\Program Files\Cocos\CocosCreator\CocosCreator.exe" -Source 'common' -Version $Version
  Add-CocosCandidate -Candidates $candidates -Path "C:\Program Files\CocosCreator\CocosCreator.exe" -Source 'common' -Version $Version
  Add-CocosCandidate -Candidates $candidates -Path "C:\Program Files (x86)\CocosCreator\CocosCreator.exe" -Source 'common' -Version $Version

  $pathCommand = Get-Command CocosCreator.exe -ErrorAction SilentlyContinue
  if ($pathCommand) {
    Add-CocosCandidate -Candidates $candidates -Path $pathCommand.Source -Source 'path' -Version $Version
  }

  if ($AllDrives) {
    $drives = @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Za-z]:\\$' })
    foreach ($drive in $drives) {
      Write-Host "Scanning drive $($drive.Root) for CocosCreator.exe. This may take a while..."
      try {
        $matches = @(Get-ChildItem -LiteralPath $drive.Root -Filter CocosCreator.exe -File -Recurse -ErrorAction SilentlyContinue)
        foreach ($match in $matches) {
          Add-CocosCandidate -Candidates $candidates -Path $match.FullName -Source 'all-drives' -Version $Version
        }
      }
      catch {
        Write-Warning "Failed to scan $($drive.Root): $($_.Exception.Message)"
      }
    }
  }

  return @($candidates | Sort-Object -Property Version, @{ Expression = 'Score'; Descending = $true }, Path)
}

function Select-CocosCreatorCandidates {
  param(
    [AllowEmptyCollection()][object[]]$Candidates = @(),
    [switch]$NonInteractive
  )

  if ($Candidates.Count -eq 0) {
    return @()
  }

  Write-Host 'Cocos Creator candidates:'
  for ($index = 0; $index -lt $Candidates.Count; $index++) {
    $item = $Candidates[$index]
    $versionText = if ([string]::IsNullOrWhiteSpace([string]$item.Version)) { 'unknown-version' } else { [string]$item.Version }
    Write-Host ('  {0}. {1}  version={2}  [{3}]' -f ($index + 1), $item.Path, $versionText, $item.Source)
  }

  $knownVersionCandidates = @($Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Version) })
  if ($knownVersionCandidates.Count -eq 0) {
    return @()
  }

  $selected = @()
  foreach ($group in ($knownVersionCandidates | Group-Object Version)) {
    $best = @($group.Group | Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, Path | Select-Object -First 1)
    if ($best.Count -gt 0) {
      $selected += $best[0]
    }
  }

  if ($NonInteractive) {
    return $selected
  }

  Write-Host ''
  Write-Host 'Selected best candidate per version:'
  foreach ($item in $selected) {
    Write-Host ('  {0} -> {1}' -f $item.Version, $item.Path)
  }
  return $selected
}

function Set-CocosCreatorEnvironment {
  param(
    [Parameter(Mandatory = $true)][string]$EnvName,
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Target
  )

  [Environment]::SetEnvironmentVariable($EnvName, $Path, $Target)
  Write-Host "Set $Target environment variable: $EnvName=$Path"
}

$candidates = Find-CocosCreatorCandidates -Version $Version -AllDrives:$AllDrives
$selected = Select-CocosCreatorCandidates -Candidates $candidates -NonInteractive:$NonInteractive

if ($selected.Count -eq 0) {
  $versionText = if ([string]::IsNullOrWhiteSpace($Version)) { 'with detectable version' } else { $Version }
  Write-Host "No Cocos Creator $versionText executable was found."
  Write-Host 'Install Cocos Creator, then set the matching versioned environment variable, for example:'
  Write-Host '  setx COCOS_CREATOR_2_4_11 "C:\Path\To\CocosCreator.exe"'
  Write-Host ''
  Write-Host 'Fast search checked environment variables, Cocos Dashboard default path, common install paths, and PATH.'
  Write-Host 'Run with -AllDrives to perform a slower full drive scan.'
  exit 1
}

Write-Host "Recommended command:"
foreach ($item in $selected) {
  $envName = Get-CocosCreatorEnvName -Version ([string]$item.Version)
  Write-Host "  setx $envName `"$($item.Path)`""
}

if ($SetUser -and $SetMachine) {
  throw 'Use only one of -SetUser or -SetMachine.'
}
if ($SetUser) {
  foreach ($item in $selected) {
    Set-CocosCreatorEnvironment -EnvName (Get-CocosCreatorEnvName -Version ([string]$item.Version)) -Path ([string]$item.Path) -Target 'User'
  }
}
elseif ($SetMachine) {
  foreach ($item in $selected) {
    Set-CocosCreatorEnvironment -EnvName (Get-CocosCreatorEnvName -Version ([string]$item.Version)) -Path ([string]$item.Path) -Target 'Machine'
  }
}
elseif (-not $NonInteractive) {
  $answer = Read-Host 'Set user environment variables now? [y/N]'
  if ($answer -match '^(y|yes)$') {
    foreach ($item in $selected) {
      Set-CocosCreatorEnvironment -EnvName (Get-CocosCreatorEnvName -Version ([string]$item.Version)) -Path ([string]$item.Path) -Target 'User'
    }
  }
}
