$global:GameNexusCiLogFile = $null

function Initialize-CiLog {
  param([Parameter(Mandatory = $true)][string]$OutputDir)

  New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
  $global:GameNexusCiLogFile = Join-Path $OutputDir 'run.log'
  Set-Content -LiteralPath $global:GameNexusCiLogFile -Value '' -Encoding UTF8
}

function Protect-CiSecretText {
  param([AllowNull()][string]$Text)

  if ($null -eq $Text) { return '' }
  $redacted = $Text
  $patterns = @(
    '(?i)(secret|token|key|webhook|private|password)[^=:"'']*([=:"'']\s*)[^,;}\s]+',
    '-----BEGIN [^-]+ PRIVATE KEY-----[\s\S]*?-----END [^-]+ PRIVATE KEY-----'
  )
  foreach ($pattern in $patterns) {
    $redacted = [regex]::Replace($redacted, $pattern, '$1$2***REDACTED***')
  }
  return $redacted
}

function Write-CiLog {
  param(
    [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
    [string]$Level = 'INFO',
    [Parameter(Mandatory = $true)][string]$Message
  )

  $safe = Protect-CiSecretText -Text $Message
  $line = '{0} [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $safe
  Write-Host $line
  if ($global:GameNexusCiLogFile) {
    Add-Content -LiteralPath $global:GameNexusCiLogFile -Value $line -Encoding UTF8
  }
}

function Get-CiLogTail {
  param([string]$OutputDir, [int]$LineCount = 200)

  $path = Join-Path $OutputDir 'run.log'
  if (-not (Test-Path -LiteralPath $path)) { return '' }
  return ((Get-Content -LiteralPath $path -Tail $LineCount) -join [Environment]::NewLine)
}
