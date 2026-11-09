# Auto-upload the MyFood miniprogram to WeChat after each git commit on main.
# Requires: Node.js, miniprogram-ci (npm install -g miniprogram-ci),
# and the upload private key from mp.weixin.qq.com saved locally.
#
# Install (once, as current user):
#   powershell -ExecutionPolicy Bypass -File ci\install-git-hook.ps1
#
# Uninstall: delete ci\install-git-hook.marker or re-run with -Remove

param(
  [string]$PrivateKeyPath = "$env:USERPROFILE\.myfood\wechat-upload.key",
  [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$marker = Join-Path $repo 'ci\install-git-hook.marker'
$hookPath = Join-Path $repo '.git\hooks\post-commit'
$scriptBody = @'
#!/bin/sh
# MyFood auto upload to WeChat (installed by ci/install-git-hook.ps1)
if [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]; then
  cmd.exe /c "powershell -ExecutionPolicy Bypass -NoProfile -File ci\upload-on-commit.ps1" &
fi
exit 0
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

Set-Content -Path (Join-Path $repo 'ci\upload-on-commit.ps1') -Encoding UTF8 -Value @"
`$ErrorActionPreference = 'Continue'
`$repo = Split-Path -Parent (Split-Path -Parent `$MyInvocation.MyCommand.Path)
Set-Location `$repo
`$log = Join-Path `$repo 'ci\output\upload-on-commit.log'
if (-not (Test-Path (Split-Path -Parent `$log))) { New-Item -ItemType Directory -Force -Path (Split-Path -Parent `$log) | Out-Null }
"[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] upload start" | Add-Content `$log
try {
  node ci\upload-miniprogram.js --private-key-path "$PrivateKeyPath" *>> `$log
  "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] upload done" | Add-Content `$log
} catch {
  `$_ | Add-Content `$log
}
"@

# Write bash hook (git for windows uses sh hooks)
Set-Content -Path $hookPath -Value $scriptBody -Encoding UTF8
Set-Content -Path $marker -Value 'installed'
Write-Host "Hook installed. Every commit on 'main' will upload the miniprogram to WeChat."
Write-Host "Log: ci\output\upload-on-commit.log"
