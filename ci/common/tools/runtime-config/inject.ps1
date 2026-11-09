[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

$buildDir = [string]$Context.Artifacts.buildDir
if ([string]::IsNullOrWhiteSpace($buildDir)) {
  return
}

. (Join-Path $Context.CiRoot 'common/runtime-config-injection.ps1')

Invoke-CiRuntimeConfigInjection -Context $Context
Test-CiRuntimeConfigInjection -Context $Context
