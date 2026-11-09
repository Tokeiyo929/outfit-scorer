[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

$envInfo = [ordered]@{
  projectRoot = $Context.ProjectRoot
  profileBundle = $Context.ProfileBundle
  platform = $Context.Platform
  outputDir = $Context.OutputDir
  powershell = $PSVersionTable.PSVersion.ToString()
  os = [System.Environment]::OSVersion.VersionString
  machineName = [System.Environment]::MachineName
  userName = [System.Environment]::UserName
  startedAt = $Context.StartedAt
}

try {
  $envInfo.git = (& git --version 2>$null) -join ''
}
catch {
  $envInfo.git = ''
}

$cocosVersion = if ($Context.Profile.PSObject.Properties['cocosCreatorVersion']) { [string]$Context.Profile.cocosCreatorVersion } else { '' }
$versionedEnvName = if ($cocosVersion) { 'COCOS_CREATOR_' + ($cocosVersion -replace '\.', '_') } else { '' }
$creatorValue = if ($versionedEnvName) { [Environment]::GetEnvironmentVariable($versionedEnvName) } else { '' }
$creatorPath = $creatorValue
if (-not [string]::IsNullOrWhiteSpace($creatorPath) -and (Test-Path -LiteralPath $creatorPath -PathType Container)) {
  $creatorPath = Join-Path $creatorPath 'CocosCreator.exe'
}
$envInfo.cocosCreatorVersion = $cocosVersion
$envInfo.cocosCreatorEnvName = $versionedEnvName
$envInfo.cocosCreator = if ($creatorPath) { [string]$creatorPath } else { '' }
$envInfo.cocosCreatorSource = $versionedEnvName
$envInfo.cocosCreatorExists = (-not [string]::IsNullOrWhiteSpace($creatorPath) -and (Test-Path -LiteralPath $creatorPath -PathType Leaf))

$envInfo | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Context.OutputDir 'environment.json') -Encoding UTF8
