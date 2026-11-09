[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'env-prepare/lib.ps1')

$VendorRoot = Join-Path $PSScriptRoot 'vendor'
$PackageJson = Join-Path $VendorRoot 'package.json'
$PackageLock = Join-Path $VendorRoot 'package-lock.json'
$NodeModules = Join-Path $VendorRoot 'node_modules'
if (-not (Test-Path -LiteralPath $PackageJson -PathType Leaf)) {
  throw "super-html package.json not found: $PackageJson"
}

$package = Get-Content -Raw -LiteralPath $PackageJson -Encoding UTF8 | ConvertFrom-Json
$RequiredModules = @($package.dependencies.PSObject.Properties.Name)
if ($RequiredModules.Count -eq 0) {
  throw "super-html package.json has no dependencies: $PackageJson"
}

$missingModules = @()
foreach ($moduleName in $RequiredModules) {
  $modulePath = Join-Path $NodeModules $moduleName
  if (-not (Test-Path -LiteralPath $modulePath -PathType Container)) {
    $missingModules += $moduleName
  }
}

if ($missingModules.Count -eq 0) {
  Write-Output "super-html dependencies are ready."
  return
}

$npm = Get-CiRequiredCommand -Name 'npm' -InstallHint 'Install Node.js first.'

$installArgs = if (Test-Path -LiteralPath $PackageLock -PathType Leaf) {
  @('ci')
}
else {
  @('install')
}

Write-Output "Installing super-html dependencies with npm $($installArgs -join ' '). Missing modules: $($missingModules -join ', ')"
Push-Location $VendorRoot
try {
  & $npm.Source @installArgs
  if ($LASTEXITCODE -ne 0) {
    throw "npm $($installArgs -join ' ') failed with exit code $LASTEXITCODE."
  }
}
finally {
  Pop-Location
}

$stillMissing = @()
foreach ($moduleName in $RequiredModules) {
  $modulePath = Join-Path $NodeModules $moduleName
  if (-not (Test-Path -LiteralPath $modulePath -PathType Container)) {
    $stillMissing += $moduleName
  }
}
if ($stillMissing.Count -gt 0) {
  throw "super-html dependency install completed but modules are still missing: $($stillMissing -join ', ')"
}

Write-Output "super-html dependencies installed."
