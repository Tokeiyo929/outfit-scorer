[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

. (Join-Path $Context.CiRoot 'common/upload.ps1')

function ConvertTo-ProcessArgument {
  param([AllowNull()][string]$Value)

  if ($null -eq $Value) { return '""' }
  if ($Value -notmatch '[\s"]') { return $Value }

  $builder = [System.Text.StringBuilder]::new()
  [void]$builder.Append('"')
  $backslashes = 0
  foreach ($character in $Value.ToCharArray()) {
    if ($character -eq '\') {
      $backslashes += 1
      continue
    }
    if ($character -eq '"') {
      [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
      [void]$builder.Append('"')
      $backslashes = 0
      continue
    }
    if ($backslashes -gt 0) {
      [void]$builder.Append(('\' * $backslashes))
      $backslashes = 0
    }
    [void]$builder.Append($character)
  }
  if ($backslashes -gt 0) {
    [void]$builder.Append(('\' * ($backslashes * 2)))
  }
  [void]$builder.Append('"')
  return $builder.ToString()
}

function Invoke-NodeUpload {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$UploadLog
  )

  $node = Get-Command node -ErrorAction SilentlyContinue
  if (-not $node) {
    throw 'node was not found in PATH. Install Node.js before WeChat upload.'
  }

  $stdoutPath = Join-Path $Context.OutputDir 'wechat-upload.stdout.log'
  $stderrPath = Join-Path $Context.OutputDir 'wechat-upload.stderr.log'

  $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $processInfo.FileName = $node.Source
  $processInfo.WorkingDirectory = $Context.ProjectRoot
  $processInfo.UseShellExecute = $false
  $processInfo.RedirectStandardOutput = $true
  $processInfo.RedirectStandardError = $true
  $processInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  $processInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  if ($processInfo.ArgumentList) {
    foreach ($arg in $Arguments) {
      [void]$processInfo.ArgumentList.Add([string]$arg)
    }
  }
  else {
    $processInfo.Arguments = ($Arguments | ForEach-Object { ConvertTo-ProcessArgument -Value ([string]$_) }) -join ' '
  }

  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $processInfo
  [void]$process.Start()
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $process.WaitForExit()
  $stdoutTask.Wait()
  $stderrTask.Wait()

  $stdoutText = [string]$stdoutTask.Result
  $stderrText = [string]$stderrTask.Result
  [System.IO.File]::WriteAllText($stdoutPath, $stdoutText, [System.Text.Encoding]::UTF8)
  [System.IO.File]::WriteAllText($stderrPath, $stderrText, [System.Text.Encoding]::UTF8)

  $combined = @()
  if (Test-Path -LiteralPath $stderrPath -PathType Leaf) { $combined += Get-Content -LiteralPath $stderrPath -Encoding UTF8 }
  if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) { $combined += Get-Content -LiteralPath $stdoutPath -Encoding UTF8 }
  $combined | ForEach-Object { Protect-CiSecretText -Text ([string]$_) } | Set-Content -LiteralPath $UploadLog -Encoding UTF8

  return $process.ExitCode
}

$profile = $Context.Profile
$appId = Get-CiProfileString -Profile $profile -Name 'appId'
$privateKeyPath = Get-CiProfileString -Profile $profile -Name 'wechatPrivateKeyPathResolved'
$robotText = Get-CiProfileString -Profile $profile -Name 'wechatRobot' -Default '1'
$version = Get-CiProfileString -Profile $profile -Name 'version'
$desc = Get-CiProfileString -Profile $profile -Name 'uploadDesc' -Default $version
$buildDir = [string]$Context.Artifacts.buildDir

foreach ($field in @('appId', 'wechatPrivateKeyPathResolved', 'version')) {
  if ([string]::IsNullOrWhiteSpace((Get-CiProfileString -Profile $profile -Name $field))) {
    throw "wechatgame upload requires profile field: $field"
  }
}
if ([string]::IsNullOrWhiteSpace($buildDir) -or -not (Test-Path -LiteralPath $buildDir -PathType Container)) {
  throw "wechatgame upload build directory not found: $buildDir"
}

$robot = [int]$robotText
if ($robot -lt 1 -or $robot -gt 30) {
  throw "wechatRobot must be between 1 and 30. Current value: $robotText"
}

$uploadLog = Join-Path $Context.OutputDir 'upload.log'
$scriptPath = Join-Path $PSScriptRoot 'upload_wechat.js'
$Context.Artifacts.uploadProvider = 'miniprogram-ci'
$Context.Artifacts.uploadLog = $uploadLog
$Context.Artifacts.wechatRobot = $robot

Write-CiLog -Level INFO -Message "wechatgame miniprogram-ci upload started. appId=$appId version=$version robot=$robot"
$args = @(
  $scriptPath,
  '--appid', $appId,
  '--project-path', $buildDir,
  '--private-key-path', $privateKeyPath,
  '--version', $version,
  '--desc', $desc,
  '--robot', "$robot"
)
$exitCode = Invoke-NodeUpload -Arguments $args -UploadLog $uploadLog
if ($exitCode -ne 0) {
  $Context.Artifacts.uploadStatus = 'FAILED'
  Write-CiArtifacts -Context $Context
  throw "wechatgame miniprogram-ci upload failed with exit code $exitCode. See $uploadLog"
}

$Context.Artifacts.uploadStatus = 'SUCCESS'
$Context.Artifacts.uploadResult = 'WECHAT_UPLOAD_SUCCESS'
Write-CiArtifacts -Context $Context
Write-CiLog -Level INFO -Message 'wechatgame miniprogram-ci upload completed.'
return $true
