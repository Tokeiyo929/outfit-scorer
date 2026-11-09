function Get-CiProfileString {
  param(
    [Parameter(Mandatory = $true)]$Profile,
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Default = ''
  )

  if ($Profile.PSObject.Properties[$Name] -and $null -ne $Profile.$Name) {
    return [string]$Profile.$Name
  }
  return $Default
}

function Test-CiUploadSkipped {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Context,
    [Parameter(Mandatory = $true)][string]$Platform
  )

  if (-not [bool]$Context.Profile.uploadEnabled) {
    $Context.Artifacts.uploadStatus = 'SKIPPED'
    $Context.Artifacts.uploadReason = 'profile.uploadEnabled=false'
    Write-CiLog -Level INFO -Message "$Platform upload skipped by profile.uploadEnabled=false."
    Write-CiArtifacts -Context $Context
    return $true
  }

  return $false
}

function Expand-CiUploadToken {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Context,
    [AllowNull()][string]$Value
  )

  if ($null -eq $Value) { return '' }

  $profile = $Context.Profile
  $replacements = @{
    '{projectRoot}' = [string]$Context.ProjectRoot
    '{ciRoot}' = [string]$Context.CiRoot
    '{outputDir}' = [string]$Context.OutputDir
    '{buildDir}' = [string]$Context.Artifacts.buildDir
    '{entry}' = if ($Context.Artifacts.entry) { [string]$Context.Artifacts.entry } else { '' }
    '{platform}' = [string]$Context.Platform
    '{projectCode}' = Get-CiProfileString -Profile $profile -Name 'projectCode'
    '{channelCode}' = Get-CiProfileString -Profile $profile -Name 'channelCode'
    '{version}' = Get-CiProfileString -Profile $profile -Name 'version'
    '{appId}' = Get-CiProfileString -Profile $profile -Name 'appId'
    '{wechatPrivateKeyPath}' = Get-CiProfileString -Profile $profile -Name 'wechatPrivateKeyPathResolved'
    '{wechatRobot}' = Get-CiProfileString -Profile $profile -Name 'wechatRobot'
  }

  $expanded = [string]$Value
  foreach ($key in $replacements.Keys) {
    $expanded = $expanded.Replace($key, [string]$replacements[$key])
  }
  return [Environment]::ExpandEnvironmentVariables($expanded)
}

function Get-CiUploadArgs {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Context,
    [AllowNull()]$ArgsValue
  )

  $args = @()
  if ($null -eq $ArgsValue) { return $args }

  if ($ArgsValue -is [System.Array]) {
    foreach ($arg in $ArgsValue) {
      $args += Expand-CiUploadToken -Context $Context -Value ([string]$arg)
    }
  }
  else {
    $args += Expand-CiUploadToken -Context $Context -Value ([string]$ArgsValue)
  }

  return $args
}

function Invoke-CiCommandUpload {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Context,
    [Parameter(Mandatory = $true)][string]$Platform
  )

  $command = Get-CiProfileString -Profile $Context.Profile -Name 'uploadCommand'
  if ([string]::IsNullOrWhiteSpace($command)) {
    return $false
  }

  $command = Expand-CiUploadToken -Context $Context -Value $command
  $args = Get-CiUploadArgs -Context $Context -ArgsValue $Context.Profile.uploadArgs
  $uploadLog = Join-Path $Context.OutputDir 'upload.log'
  Set-Content -LiteralPath $uploadLog -Value '' -Encoding UTF8

  $Context.Artifacts.uploadProvider = 'command'
  $Context.Artifacts.uploadLog = $uploadLog

  Write-CiLog -Level INFO -Message "$Platform upload command started: $command"
  $output = & $command @args 2>&1
  $exitCode = $LASTEXITCODE
  $output | ForEach-Object { Protect-CiSecretText -Text ([string]$_) } | Set-Content -LiteralPath $uploadLog -Encoding UTF8

  if ($exitCode -ne 0) {
    $Context.Artifacts.uploadStatus = 'FAILED'
    Write-CiArtifacts -Context $Context
    throw "$Platform upload command failed with exit code $exitCode. See $uploadLog"
  }

  $Context.Artifacts.uploadStatus = 'SUCCESS'
  Write-CiArtifacts -Context $Context
  Write-CiLog -Level INFO -Message "$Platform upload command completed."
  return $true
}

function Invoke-CiWebCosUpload {
  param([Parameter(Mandatory = $true)][hashtable]$Context)

  $profile = $Context.Profile
  $bucket = Get-CiProfileString -Profile $profile -Name 'cosBucket'
  $region = Get-CiProfileString -Profile $profile -Name 'cosRegion'
  $cosKey = Get-CiProfileString -Profile $profile -Name 'cosKey'
  if ([string]::IsNullOrWhiteSpace($bucket) -or [string]::IsNullOrWhiteSpace($region) -or [string]::IsNullOrWhiteSpace($cosKey)) {
    return $false
  }

  $uploadFilePath = Get-CiProfileString -Profile $profile -Name 'uploadFilePath'
  $uploadRelativePath = Get-CiProfileString -Profile $profile -Name 'uploadRelativePath'
  if ([string]::IsNullOrWhiteSpace($uploadFilePath)) {
    if ([string]::IsNullOrWhiteSpace($uploadRelativePath)) {
      $uploadFilePath = [string]$Context.Artifacts.entry
    }
    else {
      $uploadFilePath = Join-Path $Context.OutputDir $uploadRelativePath
    }
  }
  $uploadFilePath = Expand-CiUploadToken -Context $Context -Value $uploadFilePath

  if (-not (Test-Path -LiteralPath $uploadFilePath -PathType Leaf)) {
    throw "web-mobile COS upload file not found: $uploadFilePath"
  }

  $coscmd = Get-Command coscmd -ErrorAction SilentlyContinue
  if (-not $coscmd) {
    throw 'coscmd was not found in PATH. Install and configure coscmd before web-mobile COS upload.'
  }

  $configPath = Get-CiProfileString -Profile $profile -Name 'cosConfigPath' -Default (Join-Path $env:USERPROFILE '.cos.conf')
  $configPath = Expand-CiUploadToken -Context $Context -Value $configPath
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "coscmd config not found: $configPath"
  }

  $uploadLog = Join-Path $Context.OutputDir 'upload.log'
  $Context.Artifacts.uploadProvider = 'coscmd'
  $Context.Artifacts.uploadLog = $uploadLog
  $Context.Artifacts.uploadObject = "$bucket/$cosKey"
  $Context.Artifacts.previewUrl = "https://$bucket.cos.$region.myqcloud.com/$cosKey"

  Write-CiLog -Level INFO -Message "web-mobile COS upload started: $bucket/$cosKey"
  $output = & $coscmd.Source -c $configPath -b $bucket -r $region upload $uploadFilePath $cosKey -f -y --skipmd5 2>&1
  $exitCode = $LASTEXITCODE
  $output | ForEach-Object { Protect-CiSecretText -Text ([string]$_) } | Set-Content -LiteralPath $uploadLog -Encoding UTF8

  if ($exitCode -ne 0) {
    $Context.Artifacts.uploadStatus = 'FAILED'
    Write-CiArtifacts -Context $Context
    throw "web-mobile COS upload failed with exit code $exitCode. See $uploadLog"
  }

  $Context.Artifacts.uploadStatus = 'SUCCESS'
  Write-CiArtifacts -Context $Context
  Write-CiLog -Level INFO -Message "web-mobile COS upload completed: $($Context.Artifacts.previewUrl)"
  return $true
}

function Assert-CiUploadConfigured {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Context,
    [Parameter(Mandatory = $true)][string]$Platform,
    [string[]]$RequiredFields = @()
  )

  foreach ($field in $RequiredFields) {
    $value = Get-CiProfileString -Profile $Context.Profile -Name $field
    if ([string]::IsNullOrWhiteSpace($value)) {
      throw "$Platform upload requires profile field: $field"
    }
  }

  throw "$Platform upload requires either uploadCommand/uploadArgs or platform-specific upload configuration."
}
