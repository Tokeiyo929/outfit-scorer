[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

. (Join-Path $PSScriptRoot 'lib.ps1')

function Get-ImageCompressConfiguredPython {
  param([Parameter(Mandatory = $true)][hashtable]$Context)

  $configPath = Join-Path $Context.ProjectRoot 'settings/image-compress.config.json'
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    return ''
  }

  try {
    $config = ConvertFrom-CiJson -Json (Get-Content -Raw -LiteralPath $configPath -Encoding UTF8)
    if ($config.PSObject.Properties['tools'] -and $config.tools.PSObject.Properties['python']) {
      return [string]$config.tools.python
    }
  }
  catch {
    Write-CiLog -Level WARN -Message "Unable to read image-compress python config: $($_.Exception.Message)"
  }
  return ''
}

function Resolve-CiCocosCreatorForPrepare {
  param([Parameter(Mandatory = $true)][hashtable]$Context)

  $version = [string]$Context.Profile.cocosCreatorVersion
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

  Write-CiLog -Level INFO -Message "Cocos Creator ready: $envName=$creatorPath"
}

function Ensure-ImageCompressPythonDependencies {
  param([Parameter(Mandatory = $true)][hashtable]$Context)

  if (-not [bool]$Context.Profile.compressImages) {
    Write-CiLog -Level INFO -Message 'Image compression dependency setup skipped because profile.compressImages=false.'
    return
  }

  $configuredPython = Get-ImageCompressConfiguredPython -Context $Context
  $python = Get-CiDefaultPythonCommand -ConfiguredPython $configuredPython
  Test-CiPythonCommand -Python $python -Purpose 'image-compress'

  $modules = @(
    @{ Import = 'PIL'; Package = 'Pillow'; Required = $true },
    @{ Import = 'imagequant'; Package = 'imagequant'; Required = $false },
    @{ Import = 'oxipng'; Package = 'pyoxipng'; Required = $false }
  )

  foreach ($module in $modules) {
    if (Test-CiPythonImport -PythonCommand $python.Command -PythonArgs $python.Args -ImportName $module.Import) {
      Write-CiLog -Level INFO -Message "image-compress python module ready: $($module.Import)"
      continue
    }

    $allowFailure = -not [bool]$module.Required
    Invoke-CiPythonPipInstall -PythonCommand $python.Command -PythonArgs $python.Args -Packages @([string]$module.Package) -Description "Install image-compress python package $($module.Package)" -AllowFailure:$allowFailure

    if (Test-CiPythonImport -PythonCommand $python.Command -PythonArgs $python.Args -ImportName $module.Import) {
      Write-CiLog -Level INFO -Message "image-compress python module installed: $($module.Import)"
      continue
    }

    if ([bool]$module.Required) {
      throw "image-compress required python module is missing after install: $($module.Import)"
    }
    Write-CiLog -Level WARN -Message "image-compress optional python module is unavailable: $($module.Import). Compression will continue with lower optimization."
  }
}

Get-CiRequiredCommand -Name 'node' -InstallHint 'Install Node.js first.' | Out-Null
Get-CiRequiredCommand -Name 'npm' -InstallHint 'Install Node.js first.' | Out-Null
Write-CiLog -Level INFO -Message 'Node.js and npm are ready.'

if (Test-CiEnvStage -Context $Context -Stages @('all', 'env-prepare', 'before-build', 'build')) {
  Resolve-CiCocosCreatorForPrepare -Context $Context
}

if (Test-CiEnvStage -Context $Context -Stages @('all', 'env-prepare', 'after-build')) {
  Ensure-ImageCompressPythonDependencies -Context $Context
}

if ($Context.Platform -eq 'web-mobile' -and (Test-CiEnvStage -Context $Context -Stages @('all', 'env-prepare', 'after-build'))) {
  & (Join-Path $Context.CiRoot 'common/tools/super-html/ensure-deps.ps1') | ForEach-Object {
    Write-CiLog -Level INFO -Message "super-html deps | $_"
  }
}

$Context.Artifacts.envPrepare = @{
  status = 'SUCCESS'
  preparedAt = (Get-Date).ToString('o')
}
