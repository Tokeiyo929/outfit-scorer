[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

. (Join-Path $Context.CiRoot 'common/upload.ps1')
. (Join-Path $Context.CiRoot 'common/tools/env-prepare/lib.ps1')

function Get-WebPublisherPython {
  $configured = Get-CiProfileString -Profile $Context.Profile -Name 'webPublisherPython'
  if (-not [string]::IsNullOrWhiteSpace($configured)) {
    $configured = Expand-CiUploadToken -Context $Context -Value $configured
    if (-not (Test-Path -LiteralPath $configured -PathType Leaf)) {
      throw "web-mobile game-web-publisher python not found: $configured"
    }
  }

  $python = Get-CiDefaultPythonCommand -ConfiguredPython $configured
  Test-CiPythonCommand -Python $python -Purpose 'web-mobile game-web-publisher'
  return $python.Command
}

function Get-WebPublisherSourceDir {
  $sourceDir = Get-CiProfileString -Profile $Context.Profile -Name 'webPublisherSourceDir'
  if (-not [string]::IsNullOrWhiteSpace($sourceDir)) {
    $sourceDir = Expand-CiUploadToken -Context $Context -Value $sourceDir
  }
  else {
    $sourceDir = [string]$Context.Artifacts.buildDir
  }

  if ([string]::IsNullOrWhiteSpace($sourceDir) -or -not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
    throw "web-mobile game-web-publisher source directory not found: $sourceDir"
  }

  $indexPath = Join-Path $sourceDir 'index.html'
  if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    throw "web-mobile game-web-publisher source directory must contain index.html: $sourceDir"
  }

  return $sourceDir
}

function New-WebPublisherZip {
  param([Parameter(Mandatory = $true)][string]$SourceDir)

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem

  $zipPath = Get-CiProfileString -Profile $Context.Profile -Name 'webPublisherZipPath'
  if ([string]::IsNullOrWhiteSpace($zipPath)) {
    $zipPath = Join-Path $Context.OutputDir 'web-mobile-publish.zip'
  }
  else {
    $zipPath = Expand-CiUploadToken -Context $Context -Value $zipPath
  }

  $zipParent = Split-Path -Parent $zipPath
  if (-not (Test-Path -LiteralPath $zipParent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $zipParent | Out-Null
  }
  if (Test-Path -LiteralPath $zipPath -PathType Leaf) {
    Remove-Item -LiteralPath $zipPath -Force
  }

  $sourceRoot = [System.IO.Path]::GetFullPath($SourceDir).TrimEnd([char[]]@('\', '/'))
  $archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
  try {
    $files = Get-ChildItem -LiteralPath $SourceDir -Recurse -File
    foreach ($file in $files) {
      $fullPath = [System.IO.Path]::GetFullPath($file.FullName)
      $prefix = $sourceRoot + [System.IO.Path]::DirectorySeparatorChar
      if (-not $fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "web-mobile game-web-publisher refused file outside source directory: $fullPath"
      }

      $entryName = $fullPath.Substring($prefix.Length).Replace('\', '/')
      if ([string]::IsNullOrWhiteSpace($entryName) -or $entryName.StartsWith('/') -or $entryName -match '(^|/)\.\.(/|$)') {
        throw "web-mobile game-web-publisher refused invalid zip entry path: $entryName"
      }

      $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
      $entry.LastWriteTime = [System.DateTimeOffset]::new($file.LastWriteTimeUtc)
      $inputStream = [System.IO.File]::OpenRead($fullPath)
      try {
        $outputStream = $entry.Open()
        try {
          $inputStream.CopyTo($outputStream)
        }
        finally {
          $outputStream.Dispose()
        }
      }
      finally {
        $inputStream.Dispose()
      }
    }
  }
  finally {
    $archive.Dispose()
  }

  return $zipPath
}

function Get-WebPublisherTitle {
  $title = Get-CiProfileString -Profile $Context.Profile -Name 'name'
  if ([string]::IsNullOrWhiteSpace($title)) {
    $title = [string]$Context.Profile.projectCode
  }
  return $title
}

function ConvertTo-WebPublisherProcessArgument {
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

function Invoke-WebPublisherClient {
  param(
    [Parameter(Mandatory = $true)][string]$ZipPath,
    [Parameter(Mandatory = $true)][string]$Slug
  )

  $python = Get-WebPublisherPython
  $clientScript = Join-Path $PSScriptRoot 'publish_game.py'
  if (-not (Test-Path -LiteralPath $clientScript -PathType Leaf)) {
    throw "web-mobile game-web-publisher client script not found: $clientScript"
  }

  $stdoutPath = Join-Path $Context.OutputDir 'game-web-publisher.stdout.log'
  $stderrPath = Join-Path $Context.OutputDir 'game-web-publisher.stderr.log'
  $uploadLog = Join-Path $Context.OutputDir 'upload.log'

  $title = Get-WebPublisherTitle

  $portal = Get-CiProfileString -Profile $Context.Profile -Name 'webPublisherPortal'
  $username = Get-CiProfileString -Profile $Context.Profile -Name 'webPublisherUsername'
  $allowHttp = [bool]($Context.Profile.PSObject.Properties['webPublisherAllowHttp'] -and $Context.Profile.webPublisherAllowHttp)

  $args = @(
    $clientScript,
    '--file', $ZipPath,
    '--slug', $Slug,
    '--title', $title,
    '--json'
  )
  if (-not [string]::IsNullOrWhiteSpace($portal)) {
    $args += @('--portal', $portal)
  }
  if (-not [string]::IsNullOrWhiteSpace($username)) {
    $args += @('--username', $username)
  }
  if ($allowHttp) {
    $args += '--allow-http'
  }

  $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $processInfo.FileName = $python
  $processInfo.WorkingDirectory = $Context.ProjectRoot
  $processInfo.UseShellExecute = $false
  $processInfo.RedirectStandardOutput = $true
  $processInfo.RedirectStandardError = $true
  $processInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  $processInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  $processInfo.Environment['PYTHONUTF8'] = '1'
  $processInfo.Environment['PYTHONIOENCODING'] = 'utf-8'

  if ($processInfo.ArgumentList) {
    foreach ($arg in $args) {
      [void]$processInfo.ArgumentList.Add([string]$arg)
    }
  }
  else {
    $processInfo.Arguments = ($args | ForEach-Object { ConvertTo-WebPublisherProcessArgument -Value ([string]$_) }) -join ' '
  }

  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $processInfo
  [void]$process.Start()
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $process.WaitForExit()
  $stdoutTask.Wait()
  $stderrTask.Wait()

  $exitCode = $process.ExitCode
  $stdoutText = [string]$stdoutTask.Result
  $stderrText = [string]$stderrTask.Result
  [System.IO.File]::WriteAllText($stdoutPath, $stdoutText, [System.Text.Encoding]::UTF8)
  [System.IO.File]::WriteAllText($stderrPath, $stderrText, [System.Text.Encoding]::UTF8)

  $combined = @()
  if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
    $combined += Get-Content -LiteralPath $stderrPath -Encoding UTF8
  }
  if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) {
    $combined += Get-Content -LiteralPath $stdoutPath -Encoding UTF8
  }
  $combined | ForEach-Object { Protect-CiSecretText -Text ([string]$_) } | Set-Content -LiteralPath $uploadLog -Encoding UTF8

  if ($exitCode -ne 0) {
    $Context.Artifacts.uploadStatus = 'FAILED'
    $Context.Artifacts.uploadProvider = 'game-web-publisher'
    $Context.Artifacts.uploadLog = $uploadLog
    Write-CiArtifacts -Context $Context
    throw "web-mobile game-web-publisher failed with exit code $exitCode. See $uploadLog"
  }

  $stdout = Get-Content -Raw -LiteralPath $stdoutPath -Encoding UTF8
  $jsonLine = @($stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1)
  if ($jsonLine.Count -eq 0) {
    throw "web-mobile game-web-publisher did not return JSON. See $uploadLog"
  }

  try {
    return ($jsonLine[0] | ConvertFrom-Json)
  }
  catch {
    throw "web-mobile game-web-publisher returned invalid JSON. See $uploadLog"
  }
}

$slug = ([string]$Context.Profile.projectCode).ToLowerInvariant().Replace('_', '-')
if ($slug -notmatch '^[a-z0-9](?:[a-z0-9-]{0,46}[a-z0-9])?$') {
  throw "web-mobile game-web-publisher slug is invalid: $slug"
}

$sourceDir = Get-WebPublisherSourceDir
$zipPath = New-WebPublisherZip -SourceDir $sourceDir
$zipItem = Get-Item -LiteralPath $zipPath

$Context.Artifacts.uploadProvider = 'game-web-publisher'
$Context.Artifacts.uploadArchive = $zipPath
$Context.Artifacts.uploadArchiveBytes = [int64]$zipItem.Length
$Context.Artifacts.uploadSourceDir = $sourceDir
$Context.Artifacts.uploadLog = Join-Path $Context.OutputDir 'upload.log'

Write-CiLog -Level INFO -Message "web-mobile game-web-publisher upload started. slug=$slug archive=$zipPath bytes=$($zipItem.Length)"
$title = Get-WebPublisherTitle
$result = Invoke-WebPublisherClient -ZipPath $zipPath -Slug $slug

$Context.Artifacts.uploadStatus = 'SUCCESS'
$Context.Artifacts.previewUrl = [string]$result.url
$Context.Artifacts.uploadObject = [string]$result.release
$Context.Artifacts.webPublisher = @{
  url = [string]$result.url
  engine = [string]$result.engine
  release = [string]$result.release
  sha256 = [string]$result.sha256
  fileCount = $result.fileCount
  extractedBytes = $result.extractedBytes
  verified = [bool]$result.verified
}
Write-CiArtifacts -Context $Context
Write-CiLog -Level INFO -Message "web-mobile game-web-publisher upload completed: title=$title url=$($Context.Artifacts.previewUrl)"
return $true
