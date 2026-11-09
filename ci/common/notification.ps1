function Get-CiNotificationField {
  param(
    [Parameter(Mandatory = $true)]$Profile,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if ($Profile.PSObject.Properties[$Name] -and $null -ne $Profile.$Name) {
    return [string]$Profile.$Name
  }
  return ''
}

function Invoke-CiNotification {
  param([Parameter(Mandatory = $true)][hashtable]$Context)

  $Context.Artifacts.notificationStatus = 'NOT_RUN'

  if (-not $Context.Profile -or -not [bool]$Context.Profile.notifyEnabled) {
    $Context.Artifacts.notificationStatus = 'SKIPPED'
    $Context.Artifacts.notificationReason = 'profile.notifyEnabled=false'
    Write-CiArtifacts -Context $Context
    return
  }

  $webhookUrl = Get-CiNotificationField -Profile $Context.Profile -Name 'notifyWebhookUrl'
  if ([string]::IsNullOrWhiteSpace($webhookUrl)) {
    $Context.Artifacts.notificationStatus = 'SKIPPED'
    $Context.Artifacts.notificationReason = 'notifyWebhookUrl is empty'
    Write-CiArtifacts -Context $Context
    Write-CiLog -Level WARN -Message 'Notification skipped because notifyWebhookUrl is empty.'
    return
  }

  $payload = [ordered]@{
    buildId = [string]$Context.BuildId
    status = [string]$Context.Result.status
    stage = [string]$Context.Result.stage
    projectCode = [string]$Context.Result.projectCode
    channelCode = [string]$Context.Result.channelCode
    platform = [string]$Context.Platform
    version = [string]$Context.Result.version
    outputDir = [string]$Context.OutputDir
    previewUrl = [string]$Context.Artifacts.previewUrl
    uploadStatus = [string]$Context.Artifacts.uploadStatus
    errorCode = [string]$Context.Result.errorCode
    errorMessage = [string]$Context.Result.errorMessage
    endedAt = [string]$Context.Result.endedAt
  }

  $notifyLog = Join-Path $Context.OutputDir 'notification.json'
  $payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $notifyLog -Encoding UTF8
  $Context.Artifacts.notificationPayload = $notifyLog

  try {
    Write-CiLog -Level INFO -Message 'Sending build notification.'
    $body = $payload | ConvertTo-Json -Depth 20
    $response = Invoke-RestMethod -Uri $webhookUrl -Method Post -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 30
    $Context.Artifacts.notificationStatus = 'SUCCESS'
    $Context.Artifacts.notificationResponse = if ($null -eq $response) { '' } else { ($response | ConvertTo-Json -Depth 10 -Compress) }
    Write-CiLog -Level INFO -Message 'Build notification sent.'
  }
  catch {
    $Context.Artifacts.notificationStatus = 'FAILED'
    $Context.Artifacts.notificationError = Protect-CiSecretText -Text $_.Exception.Message
    Write-CiLog -Level WARN -Message "Build notification failed: $($Context.Artifacts.notificationError)"
  }

  Write-CiArtifacts -Context $Context
}
