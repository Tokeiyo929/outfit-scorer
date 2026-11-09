[CmdletBinding()]
param(
  [string]$OutputRun = '',
  [string]$OutputRoot = '',
  [string]$SourceDir = '',
  [switch]$List
)

$ErrorActionPreference = 'Stop'

$CiRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $CiRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $CiRoot 'output'
}

. (Join-Path $CiRoot 'common/logging.ps1')
. (Join-Path $CiRoot 'common/profile-bundle.ps1')
. (Join-Path $CiRoot 'common/result-writer.ps1')
. (Join-Path $CiRoot 'common/tools/standalone-upload-context/context.ps1')

if ($List) {
  $runs = Get-CiUploadOutputRuns -Root ([System.IO.Path]::GetFullPath($OutputRoot)) -Platform 'wechatgame'
  if ($runs.Count -eq 0) {
    Write-Host "No uploadable wechatgame output directories found under: $OutputRoot"
    exit 0
  }
  $index = 1
  foreach ($item in $runs) {
    Write-Host ('{0}. {1}  {2}' -f $index, $item.Name, $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
    $index += 1
  }
  exit 0
}

$Context = New-CiStandaloneUploadContext -CiRoot $CiRoot -ProjectRoot $ProjectRoot -Platform 'wechatgame' -OutputRoot $OutputRoot -OutputRun $OutputRun -SourceDir $SourceDir
Write-CiLog -Level INFO -Message "Standalone wechatgame upload started. OutputDir=$($Context.OutputDir) SourceDir=$($Context.Artifacts.buildDir)"
& (Join-Path $CiRoot 'platforms/wechatgame/tools/miniprogram-ci/upload.ps1') -Context $Context | Out-Null
Write-CiLog -Level INFO -Message "Standalone wechatgame upload completed. status=$($Context.Artifacts.uploadStatus)"
