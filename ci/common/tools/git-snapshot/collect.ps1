[CmdletBinding()]
param([Parameter(Mandatory = $true)][hashtable]$Context)

$status = & git -C $Context.ProjectRoot status --short 2>$null
$snapshot = @{
  gitStatus = @($status)
  snapshotAt = (Get-Date).ToString('o')
}
$snapshot | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Context.OutputDir 'git-snapshot.json') -Encoding UTF8

if ($status) {
  Write-CiLog -Level WARN -Message 'Project working tree has existing changes. CI records them without modifying source files.'
}
