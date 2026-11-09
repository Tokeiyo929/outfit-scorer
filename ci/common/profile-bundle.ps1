function ConvertFrom-CiJson {
  param([Parameter(Mandatory = $true)][string]$Json)

  if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('NoEnumerate')) {
    return $Json | ConvertFrom-Json -NoEnumerate
  }
  return $Json | ConvertFrom-Json
}

function Resolve-ProfilePath {
  param(
    [Parameter(Mandatory = $true)][string]$BundleRoot,
    [AllowNull()][string]$PathValue,
    [switch]$MustExist
  )

  if ([string]::IsNullOrWhiteSpace($PathValue)) { return '' }

  $resolved = $PathValue
  if (-not [System.IO.Path]::IsPathRooted($PathValue)) {
    $resolved = Join-Path $BundleRoot $PathValue
  }
  $resolved = [System.IO.Path]::GetFullPath($resolved)

  if ($MustExist -and -not (Test-Path -LiteralPath $resolved)) {
    throw "Profile referenced file does not exist: $resolved"
  }

  return $resolved
}

function Test-RequiredProfileField {
  param(
    [Parameter(Mandatory = $true)]$Profile,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if (-not $Profile.PSObject.Properties[$Name] -or [string]::IsNullOrWhiteSpace([string]$Profile.$Name)) {
    throw "profile.json missing required field: $Name"
  }
}

function Test-BooleanProfileField {
  param(
    [Parameter(Mandatory = $true)]$Profile,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if (-not $Profile.PSObject.Properties[$Name]) {
    throw "profile.json missing required boolean field: $Name"
  }

  if ($Profile.$Name -isnot [bool]) {
    throw "profile.json field must be boolean: $Name"
  }
}

function Add-ProfileProperties {
  param(
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Target,
    [AllowNull()]$Source,
    [string[]]$SkipNames = @()
  )

  if ($null -eq $Source) { return }

  foreach ($property in $Source.PSObject.Properties) {
    if ($SkipNames -contains $property.Name) { continue }
    $Target[$property.Name] = $property.Value
  }
}

function ConvertTo-ProfileObject {
  param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Table)

  $object = [pscustomobject]@{}
  foreach ($key in $Table.Keys) {
    $object | Add-Member -NotePropertyName $key -NotePropertyValue $Table[$key]
  }
  return $object
}

function Read-ProfileBundle {
  param(
    [Parameter(Mandatory = $true)][string]$BundlePath,
    [Parameter(Mandatory = $true)][ValidateSet('web-mobile', 'wechatgame', 'bytedance')][string]$Platform
  )

  $bundleRoot = [System.IO.Path]::GetFullPath($BundlePath)
  if (-not (Test-Path -LiteralPath $bundleRoot -PathType Container)) {
    throw "ProfileBundle directory not found: $bundleRoot"
  }

  $profilePath = Join-Path $bundleRoot 'profile.json'
  if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
    throw "profile.json not found in ProfileBundle: $profilePath"
  }

  $rawProfile = ConvertFrom-CiJson -Json (Get-Content -Raw -LiteralPath $profilePath -Encoding UTF8)
  $profileTable = [ordered]@{}

  Add-ProfileProperties -Target $profileTable -Source $rawProfile -SkipNames @('common', 'platforms')
  if ($rawProfile.PSObject.Properties['common']) {
    Add-ProfileProperties -Target $profileTable -Source $rawProfile.common
  }
  if ($rawProfile.PSObject.Properties['platforms']) {
    if (-not $rawProfile.platforms.PSObject.Properties[$Platform]) {
      throw "profile.json missing platform config: platforms.$Platform"
    }
    Add-ProfileProperties -Target $profileTable -Source $rawProfile.platforms.$Platform
  }
  elseif ($rawProfile.PSObject.Properties['platform']) {
    if ([string]$rawProfile.platform -ne $Platform) {
      throw "Legacy profile platform '$($rawProfile.platform)' does not match requested platform '$Platform'."
    }
  }

  $profileTable['platform'] = $Platform
  $profile = ConvertTo-ProfileObject -Table $profileTable

  foreach ($field in @('schemaVersion', 'projectCode', 'name', 'channelCode', 'buildProfile', 'buildType', 'cocosCreatorVersion')) {
    Test-RequiredProfileField -Profile $profile -Name $field
  }
  foreach ($field in @('uploadEnabled', 'compressImages', 'notifyEnabled')) {
    Test-BooleanProfileField -Profile $profile -Name $field
  }

  if ($profile.buildType -notin @('release', 'debug')) {
    throw "Unsupported profile buildType: $($profile.buildType)"
  }

  foreach ($codeField in @('projectCode', 'channelCode', 'buildProfile')) {
    if ([string]$profile.$codeField -notmatch '^[A-Za-z0-9_-]+$') {
      throw "profile.json field only allows letters, numbers, underscore, and hyphen: $codeField"
    }
  }

  if ($Platform -eq 'wechatgame' -and $profile.PSObject.Properties['appId'] -and -not [string]::IsNullOrWhiteSpace([string]$profile.appId)) {
    if ([string]$profile.appId -notmatch '^wx[0-9A-Za-z]{16,}$') {
      throw "wechat appId format is invalid: $($profile.appId)"
    }
  }

  if ($profile.PSObject.Properties['wechatRobot'] -and $null -ne $profile.wechatRobot -and "$($profile.wechatRobot)" -ne '') {
    $robot = [int]$profile.wechatRobot
    if ($robot -lt 1 -or $robot -gt 30) {
      throw "wechatRobot must be between 1 and 30."
    }
  }

  $profile | Add-Member -NotePropertyName bundleRoot -NotePropertyValue $bundleRoot -Force
  $profile | Add-Member -NotePropertyName profilePath -NotePropertyValue $profilePath -Force

  foreach ($assetField in @('loadingLogoPath', 'bytedanceSidebarPath', 'wechatPrivateKeyPath', 'logoPath')) {
    if ($profile.PSObject.Properties[$assetField]) {
      $mustExist = -not [string]::IsNullOrWhiteSpace([string]$profile.$assetField)
      $resolved = Resolve-ProfilePath -BundleRoot $bundleRoot -PathValue ([string]$profile.$assetField) -MustExist:$mustExist
      $profile | Add-Member -NotePropertyName "${assetField}Resolved" -NotePropertyValue $resolved -Force
    }
  }

  return $profile
}

function Copy-ProfileForOutput {
  param([Parameter(Mandatory = $true)]$Profile)

  $copy = $Profile | ConvertTo-Json -Depth 20 | ConvertFrom-Json
  foreach ($secretField in @('tencentSecretKey', 'bytedanceUploadPassword')) {
    if ($copy.PSObject.Properties[$secretField] -and -not [string]::IsNullOrWhiteSpace([string]$copy.$secretField)) {
      $copy.$secretField = '***REDACTED***'
    }
  }
  return $copy
}
