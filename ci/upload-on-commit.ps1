$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $repo
$log = Join-Path $repo 'ci\output\upload-on-commit.log'
if (-not (Test-Path (Split-Path -Parent $log))) { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $log) | Out-Null }
"[2026-10-30 21:53:58] upload start" | Add-Content $log
try {
  node ci\upload-miniprogram.js --private-key-path "D:\GitHub\MyFood\myfood-app\ci\profiles\private.wxd40973d90aa34b31.key" *>> $log
  "[2026-10-30 21:53:58] upload done" | Add-Content $log
} catch {
  $_ | Add-Content $log
}
