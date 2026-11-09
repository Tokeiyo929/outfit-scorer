[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

. (Join-Path $Context.CiRoot 'common/upload.ps1')

function Invoke-ByteDanceCli {
  param(
    [Parameter(Mandatory = $true)][string]$CliPath,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$LogPath,
    [string[]]$SecretValues = @()
  )

  $processPath = $CliPath
  if ([IO.Path]::GetExtension($processPath) -ieq '.ps1') {
    $cmdPath = [IO.Path]::ChangeExtension($processPath, '.cmd')
    if (Test-Path -LiteralPath $cmdPath -PathType Leaf) {
      $processPath = $cmdPath
    }
  }

  $stdoutPath = [IO.Path]::GetTempFileName()
  $stderrPath = [IO.Path]::GetTempFileName()
  try {
    $argumentLine = ($Arguments | ForEach-Object {
        $argument = [string]$_
        $argument = $argument -replace '(\\*)"', '$1$1\"'
        $argument = $argument -replace '(\\+)$', '$1$1'
        '"' + $argument + '"'
      }) -join ' '
    $process = Start-Process -FilePath $processPath -ArgumentList $argumentLine `
      -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -Wait -PassThru

    $output = @(Get-Content -LiteralPath $stdoutPath -Encoding UTF8)
    $output += @(Get-Content -LiteralPath $stderrPath -Encoding UTF8)
    $exitCode = $process.ExitCode
    $safeOutput = @()
    foreach ($line in $output) {
      $safe = Protect-CiSecretText -Text ([string]$line)
      foreach ($secret in $SecretValues) {
        if (-not [string]::IsNullOrWhiteSpace($secret)) {
          $safe = $safe.Replace($secret, '***REDACTED***')
        }
      }
      $safeOutput += $safe
    }
    Add-Content -LiteralPath $LogPath -Value $safeOutput -Encoding UTF8
    if ($output -match '(?i)Project Error:|请调整包大小') {
      return 1
    }
    return $exitCode
  }
  finally {
    Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
  }
}

$profile = $Context.Profile
$email = Get-CiProfileString -Profile $profile -Name 'bytedanceUploadEmail'
$password = Get-CiProfileString -Profile $profile -Name 'bytedanceUploadPassword'
$version = Get-CiProfileString -Profile $profile -Name 'version'
$changeLog = Get-CiProfileString -Profile $profile -Name 'uploadDesc' -Default $version
$proxy = Get-CiProfileString -Profile $profile -Name 'bytedanceUploadProxy'
$cliName = Get-CiProfileString -Profile $profile -Name 'bytedanceUploadCli' -Default 'tmg'
$buildDir = [string]$Context.Artifacts.buildDir
$qrcodePath = Join-Path $Context.OutputDir 'bytedance-experience-qrcode.png'

foreach ($field in @('bytedanceUploadEmail', 'bytedanceUploadPassword', 'version')) {
  if ([string]::IsNullOrWhiteSpace((Get-CiProfileString -Profile $profile -Name $field))) {
    throw "bytedance upload requires profile field: $field"
  }
}
if ([string]::IsNullOrWhiteSpace($buildDir) -or -not (Test-Path -LiteralPath $buildDir -PathType Container)) {
  throw "bytedance upload build directory not found: $buildDir"
}

$cli = Get-Command $cliName -ErrorAction SilentlyContinue
if (-not $cli) {
  throw "bytedance upload CLI '$cliName' was not found in PATH. Install it first: npm install -g tt-minigame-ide-cli"
}

$uploadLog = Join-Path $Context.OutputDir 'upload.log'
Set-Content -LiteralPath $uploadLog -Value '' -Encoding UTF8

$Context.Artifacts.uploadProvider = 'tt-minigame-ide-cli'
$Context.Artifacts.uploadLog = $uploadLog
$Context.Artifacts.qrcodePath = $qrcodePath

Write-CiLog -Level INFO -Message "bytedance tt-minigame-ide-cli login started. email=$email"
$loginArgs = @('login-e', $email, $password)
if (-not [string]::IsNullOrWhiteSpace($proxy)) {
  $loginArgs += @('--proxy', $proxy)
}
$exitCode = Invoke-ByteDanceCli -CliPath $cli.Source -Arguments $loginArgs -LogPath $uploadLog -SecretValues @($password)
if ($exitCode -ne 0) {
  $Context.Artifacts.uploadStatus = 'FAILED'
  Write-CiArtifacts -Context $Context
  throw "bytedance tt-minigame-ide-cli login failed with exit code $exitCode. See $uploadLog"
}

Write-CiLog -Level INFO -Message "bytedance tt-minigame-ide-cli upload started. version=$version"
$uploadArgs = @('upload', '--app-version', $version, '--app-changelog', $changeLog, '--output', $qrcodePath)
if (-not [string]::IsNullOrWhiteSpace($proxy)) {
  $uploadArgs += @('--proxy', $proxy)
}
$uploadArgs += $buildDir
$exitCode = Invoke-ByteDanceCli -CliPath $cli.Source -Arguments $uploadArgs -LogPath $uploadLog -SecretValues @($password)
if ($exitCode -ne 0) {
  $Context.Artifacts.uploadStatus = 'FAILED'
  Write-CiArtifacts -Context $Context
  throw "bytedance tt-minigame-ide-cli upload failed with exit code $exitCode. See $uploadLog"
}

$Context.Artifacts.uploadStatus = 'SUCCESS'
$Context.Artifacts.uploadResult = 'BYTEDANCE_UPLOAD_SUCCESS'
Write-CiArtifacts -Context $Context
Write-CiLog -Level INFO -Message 'bytedance tt-minigame-ide-cli upload completed.'
return $true
