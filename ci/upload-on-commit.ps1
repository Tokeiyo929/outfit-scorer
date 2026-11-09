$ErrorActionPreference = 'Continue'
# Auto-upload the miniprogram after each commit on main (called by .git/hooks/post-commit)
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$log = Join-Path $repo 'ci\output\upload-on-commit.log'
$key = Join-Path $repo 'ci\profiles\private.wxd40973d90aa34b31.key'
$outDir = Split-Path -Parent $log
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
"[$stamp] upload start (commit $(git rev-parse --short HEAD))" | Add-Content -Encoding UTF8 $log

try {
  $out = node ci\upload-miniprogram.js --private-key-path $key 2>&1 | Out-String
  $out | Add-Content -Encoding UTF8 $log
  $stamp2 = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  if ($out -match 'UPLOAD_SUCCESS') {
    "[$stamp2] UPLOAD_SUCCESS (exit 0)" | Add-Content -Encoding UTF8 $log
  } else {
    "[$stamp2] UPLOAD_FAILED" | Add-Content -Encoding UTF8 $log
  }
} catch {
  $_ | Add-Content -Encoding UTF8 $log
}
