function Test-CiEnvStage {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Context,
    [Parameter(Mandatory = $true)][string[]]$Stages
  )

  return $Stages -contains [string]$Context.Stage
}

function Get-CiRequiredCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$InstallHint = ''
  )

  $commandName = if ($Name -eq 'npm' -and ($IsWindows -or $env:OS -eq 'Windows_NT')) { 'npm.cmd' } else { $Name }
  $command = Get-Command $commandName -ErrorAction SilentlyContinue
  if (-not $command) {
    if ([string]::IsNullOrWhiteSpace($InstallHint)) {
      throw "Required command was not found in PATH: $Name"
    }
    throw "Required command was not found in PATH: $Name. $InstallHint"
  }
  return $command
}

function Invoke-CiEnvCommand {
  param(
    [Parameter(Mandatory = $true)][string]$FileName,
    [string[]]$Arguments = @(),
    [Parameter(Mandatory = $true)][string]$Description,
    [switch]$AllowFailure
  )

  Write-CiLog -Level INFO -Message "$Description started: $FileName $($Arguments -join ' ')"
  $output = @()
  $oldErrorActionPreference = $ErrorActionPreference
  $nativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
  $hadNativePreference = $null -ne $nativePreference
  $oldNativePreference = if ($hadNativePreference) { $nativePreference.Value } else { $null }
  try {
    $ErrorActionPreference = 'Continue'
    if ($hadNativePreference) {
      Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false -Scope Local
    }
    $output = & $FileName @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  }
  catch {
    if ($AllowFailure) {
      Write-CiLog -Level WARN -Message "$Description failed: $($_.Exception.Message)"
      return $false
    }
    throw "$Description failed: $($_.Exception.Message)"
  }
  finally {
    $ErrorActionPreference = $oldErrorActionPreference
    if ($hadNativePreference) {
      Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $oldNativePreference -Scope Local
    }
  }

  foreach ($line in $output) {
    if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
      Write-CiLog -Level INFO -Message "$Description | $line"
    }
  }

  if ($exitCode -ne 0) {
    if ($AllowFailure) {
      Write-CiLog -Level WARN -Message "$Description failed with exit code $exitCode."
      return $false
    }
    throw "$Description failed with exit code $exitCode."
  }

  Write-CiLog -Level INFO -Message "$Description completed."
  return $true
}

function Add-CiNpmGlobalBinToPath {
  param([Parameter(Mandatory = $true)][string]$NpmPath)

  try {
    $prefix = (& $NpmPath prefix -g 2>$null | Select-Object -First 1)
    if (-not [string]::IsNullOrWhiteSpace([string]$prefix) -and (Test-Path -LiteralPath ([string]$prefix) -PathType Container)) {
      $paths = $env:Path -split ';'
      if ($paths -notcontains [string]$prefix) {
        $env:Path = [string]$prefix + ';' + $env:Path
      }
    }
  }
  catch {
  }
}

function Invoke-CiNpmGlobalInstall {
  param(
    [Parameter(Mandatory = $true)][string]$PackageName,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $npm = Get-CiRequiredCommand -Name 'npm' -InstallHint 'Install Node.js first.'
  Invoke-CiEnvCommand -FileName $npm.Source -Arguments @('install', '-g', $PackageName) -Description $Description | Out-Null
  Add-CiNpmGlobalBinToPath -NpmPath $npm.Source
}

function Test-CiPythonImport {
  param(
    [Parameter(Mandatory = $true)][string]$PythonCommand,
    [string[]]$PythonArgs = @(),
    [Parameter(Mandatory = $true)][string]$ImportName
  )

  $args = @($PythonArgs) + @('-c', "import $ImportName")
  $oldErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $null = & $PythonCommand @args 2>$null
    return $LASTEXITCODE -eq 0
  }
  catch {
    return $false
  }
  finally {
    $ErrorActionPreference = $oldErrorActionPreference
  }
}

function Invoke-CiPythonPipInstall {
  param(
    [Parameter(Mandatory = $true)][string]$PythonCommand,
    [string[]]$PythonArgs = @(),
    [Parameter(Mandatory = $true)][string[]]$Packages,
    [Parameter(Mandatory = $true)][string]$Description,
    [switch]$AllowFailure
  )

  $ensurePipArgs = @($PythonArgs) + @('-m', 'ensurepip', '--upgrade')
  Invoke-CiEnvCommand -FileName $PythonCommand -Arguments $ensurePipArgs -Description "$Description ensurepip" -AllowFailure | Out-Null

  $pipArgs = @($PythonArgs) + @('-m', 'pip', 'install', '--upgrade') + $Packages
  Invoke-CiEnvCommand -FileName $PythonCommand -Arguments $pipArgs -Description $Description -AllowFailure:$AllowFailure | Out-Null
}

function Get-CiDefaultPythonCommand {
  param([string]$ConfiguredPython = '')

  if (-not [string]::IsNullOrWhiteSpace($ConfiguredPython)) {
    $resolved = $ConfiguredPython
    if (Test-Path -LiteralPath $resolved -PathType Leaf) {
      $resolved = (Resolve-Path -LiteralPath $resolved).Path
    }
    return @{ Command = $resolved; Args = @() }
  }

  if (-not [string]::IsNullOrWhiteSpace($env:TINYPYTHON)) {
    return @{ Command = $env:TINYPYTHON; Args = @() }
  }

  $candidates = if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    @('py', 'python', 'python3')
  }
  else {
    @('python3', 'python')
  }

  foreach ($candidate in $candidates) {
    $command = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($command) {
      return @{ Command = $command.Source; Args = @() }
    }
  }

  return @{ Command = $candidates[0]; Args = @() }
}

function Test-CiPythonCommand {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Python,
    [Parameter(Mandatory = $true)][string]$Purpose
  )

  $args = @($Python.Args) + @('--version')
  $output = & $Python.Command @args 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "$Purpose requires Python, but '$($Python.Command) $($Python.Args -join ' ')' is not available. Install Python or configure the matching profile field."
  }
  Write-CiLog -Level INFO -Message "$Purpose Python ready: $($output -join ' ')"
}
