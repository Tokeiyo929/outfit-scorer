function Get-CiGitValue {
  param([string[]]$Arguments, [string]$WorkingDirectory)

  try {
    $value = & git -C $WorkingDirectory @Arguments 2>$null
    if ($LASTEXITCODE -eq 0) { return (($value | Select-Object -First 1) -as [string]) }
  }
  catch {
  }
  return ''
}

function Initialize-CiResult {
  param([Parameter(Mandatory = $true)][hashtable]$Context)

  $profile = $Context.Profile
  $branch = Get-CiGitValue -Arguments @('rev-parse', '--abbrev-ref', 'HEAD') -WorkingDirectory $Context.ProjectRoot
  $commit = Get-CiGitValue -Arguments @('rev-parse', 'HEAD') -WorkingDirectory $Context.ProjectRoot

  $Context.Result = @{
    status = 'RUNNING'
    stage = $Context.CurrentStage
    exitCode = 0
    errorCode = ''
    errorMessage = ''
    startedAt = $Context.StartedAt
    endedAt = ''
    projectCode = [string]$profile.projectCode
    name = [string]$profile.name
    channelCode = [string]$profile.channelCode
    platform = [string]$Context.Platform
    version = if ($profile.PSObject.Properties['version']) { [string]$profile.version } else { '' }
    gitBranch = $branch
    gitCommit = $commit
    uploadEnabled = [bool]$profile.uploadEnabled
    compressImages = [bool]$profile.compressImages
    notifyEnabled = [bool]$profile.notifyEnabled
    buildId = [string]$Context.BuildId
    logTail = ''
  }

  Write-CiResult -Context $Context
  Write-CiArtifacts -Context $Context
}

function Write-CiResult {
  param([Parameter(Mandatory = $true)][hashtable]$Context)

  $Context.Result.stage = $Context.CurrentStage
  $Context.Result.logTail = Get-CiLogTail -OutputDir $Context.OutputDir
  $path = Join-Path $Context.OutputDir 'result.json'
  $Context.Result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Write-CiArtifacts {
  param([Parameter(Mandatory = $true)][hashtable]$Context)

  $path = Join-Path $Context.OutputDir 'artifacts.json'
  $Context.Artifacts | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Complete-CiResult {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Context,
    [Parameter(Mandatory = $true)][string]$Status,
    [Parameter(Mandatory = $true)][int]$ExitCode,
    [string]$ErrorCode = '',
    [string]$ErrorMessage = ''
  )

  if (-not $Context.Result -or $Context.Result.Count -eq 0) {
    $Context.Result = @{}
  }

  $Context.Result.status = $Status
  $Context.Result.stage = $Context.CurrentStage
  $Context.Result.exitCode = $ExitCode
  $Context.Result.errorCode = $ErrorCode
  $Context.Result.errorMessage = Protect-CiSecretText -Text $ErrorMessage
  $Context.Result.endedAt = (Get-Date).ToString('o')
  $Context.Result.logTail = Get-CiLogTail -OutputDir $Context.OutputDir

  Write-CiArtifacts -Context $Context
  Write-CiResult -Context $Context
}
