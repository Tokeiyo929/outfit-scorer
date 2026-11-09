# Auto-upload the outfit-scorer miniprogram to WeChat after each git commit on main.
# Requires: Node.js, miniprogram-ci (npm install -g miniprogram-ci),
# and the upload private key from mp.weixin.qq.com saved locally.
#
# Install (once, as current user):
#   powershell -ExecutionPolicy Bypass -File ci\install-git-hook.ps1
#
# Uninstall: delete ci\install-git-hook.marker or re-run with -Remove

param(
  [string]$PrivateKeyPath = '',
  [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $PrivateKeyPath) { $PrivateKeyPath = Join-Path $repo 'ci\profiles\private.wxd40973d90aa34b31.key' }
$marker = Join-Path $repo 'ci\install-git-hook.marker'
$hookPath = Join-Path $repo '.git\hooks\post-commit'
$scriptBody = @'
#!/bin/sh
# outfit-scorer auto upload to WeChat (installed by ci/install-git-hook.ps1)
if [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]; then
  powershell.exe -ExecutionPolicy Bypass -NoProfile -File "ci/upload-on-commit.ps1" >/dev/null 2>&1 &
fi
exit 0
'@

$ps1Body = @'
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
'@

if ($Remove) {
  if (Test-Path $hookPath) { Remove-Item $hookPath -Force }
  if (Test-Path $marker) { Remove-Item $marker -Force }
  Write-Host 'post-commit hook removed.'
  exit 0
}

if (-not (Test-Path $PrivateKeyPath)) {
  Write-Warning "Private key not found at $PrivateKeyPath"
  Write-Host "Download the upload key: mp.weixin.qq.com -> 开发管理 -> 开发设置 -> 小程序代码上传 -> 生成并下载代码上传密钥"
  Write-Host "Then save it to $PrivateKeyPath"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $PrivateKeyPath) | Out-Null
  Write-Host "Directory created. Put the key file there and re-run this script."
}

# Write upload-on-commit.ps1 as UTF-8 with BOM (PowerShell 5.1 needs BOM for non-ASCII safety)
[IO.File]::WriteAllText((Join-Path $repo 'ci\upload-on-commit.ps1'), $ps1Body.Replace("`r`n", "`n"), [Text.Encoding]::UTF8)

# Write bash hook — 必须无 BOM + LF，否则 shebang 解析失败
[IO.File]::WriteAllText($hookPath, $scriptBody.Replace("`r`n", "`n"), [Text.Encoding]::ASCII)
Set-Content -Path $marker -Value 'installed'
Write-Host "Hook installed. Every commit on 'main' will upload the miniprogram to WeChat."
Write-Host "Log: ci\output\upload-on-commit.log"
