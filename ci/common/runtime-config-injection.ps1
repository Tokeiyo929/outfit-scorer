function ConvertTo-PlainProfileValue {
  param([AllowNull()]$Value)

  if ($null -eq $Value) {
    return $null
  }

  if ($Value -is [System.Collections.IDictionary]) {
    $table = [ordered]@{}
    foreach ($key in $Value.Keys) {
      $table[$key] = ConvertTo-PlainProfileValue -Value $Value[$key]
    }
    return $table
  }

  if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
    $items = @()
    foreach ($item in $Value) {
      $items += ,(ConvertTo-PlainProfileValue -Value $item)
    }
    return ,$items
  }

  if ($Value -is [pscustomobject]) {
    $table = [ordered]@{}
    foreach ($property in $Value.PSObject.Properties) {
      $table[$property.Name] = ConvertTo-PlainProfileValue -Value $property.Value
    }
    return $table
  }

  return $Value
}

function ConvertFrom-CiJson {
  param([Parameter(Mandatory = $true)][string]$Json)

  if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('NoEnumerate')) {
    return $Json | ConvertFrom-Json -NoEnumerate
  }
  return $Json | ConvertFrom-Json
}

function Merge-OrderedHashtable {
  param(
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Target,
    [AllowNull()]$Source
  )

  if ($null -eq $Source) {
    return
  }

  $plainSource = ConvertTo-PlainProfileValue -Value $Source
  if ($plainSource -isnot [System.Collections.IDictionary]) {
    return
  }

  foreach ($key in $plainSource.Keys) {
    $value = $plainSource[$key]
    if ($value -is [System.Collections.IDictionary] -and $Target.Contains($key) -and $Target[$key] -is [System.Collections.IDictionary]) {
      Merge-OrderedHashtable -Target $Target[$key] -Source $value
    }
    else {
      $Target[$key] = $value
    }
  }
}

function Get-ProfileString {
  param(
    [Parameter(Mandatory = $true)]$Profile,
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Default = ''
  )

  if ($Profile.PSObject.Properties[$Name] -and $null -ne $Profile.$Name) {
    return [string]$Profile.$Name
  }
  return $Default
}

function Get-ProfileBoolean {
  param(
    [Parameter(Mandatory = $true)]$Profile,
    [Parameter(Mandatory = $true)][string]$Name,
    [bool]$Default = $false
  )

  if ($Profile.PSObject.Properties[$Name] -and $null -ne $Profile.$Name) {
    return [bool]$Profile.$Name
  }
  return $Default
}

function Get-ProfileArray {
  param(
    [Parameter(Mandatory = $true)]$Profile,
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$LegacyName = ''
  )

  $value = $null
  if ($Profile.PSObject.Properties[$Name] -and $null -ne $Profile.$Name) {
    $value = $Profile.$Name
  }
  elseif ($LegacyName -and $Profile.PSObject.Properties[$LegacyName] -and $null -ne $Profile.$LegacyName) {
    $value = $Profile.$LegacyName
  }

  if ($null -eq $value) {
    return @()
  }

  if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
    $result = @($value | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
    return ,$result
  }

  if ([string]::IsNullOrWhiteSpace([string]$value)) {
    return @()
  }

  return ,@([string]$value)
}

function Set-HashtablePathValue {
  param(
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Target,
    [Parameter(Mandatory = $true)][string]$Path,
    [AllowNull()]$Value,
    [switch]$AllowEmpty
  )

  if ($null -eq $Value) {
    return
  }
  if (-not $AllowEmpty -and $Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) {
    return
  }
  if (-not $AllowEmpty -and $Value -is [array] -and $Value.Count -eq 0) {
    return
  }

  $parts = $Path -split '\.'
  $current = $Target
  for ($i = 0; $i -lt $parts.Count - 1; $i++) {
    $part = $parts[$i]
    if (-not $current.Contains($part) -or $current[$part] -isnot [System.Collections.IDictionary]) {
      $current[$part] = [ordered]@{}
    }
    $current = $current[$part]
  }
  $current[$parts[$parts.Count - 1]] = $Value
}

function Get-HashtablePathValue {
  param(
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Source,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $parts = $Path -split '\.'
  $current = $Source
  foreach ($part in $parts) {
    if ($current -isnot [System.Collections.IDictionary] -or -not $current.Contains($part)) {
      return $null
    }
    $current = $current[$part]
  }
  Write-Output -NoEnumerate $current
}

function Test-RuntimeRequiredString {
  param(
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Config,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $value = Get-HashtablePathValue -Source $Config -Path $Path
  if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
    throw "Runtime channel config missing required field: runtime.$Path"
  }
}

function Test-RuntimeRequiredArray {
  param(
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Config,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $value = Get-HashtablePathValue -Source $Config -Path $Path
  $items = @()
  if ($null -ne $value -and $value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
    $items = @($value | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  }
  if ($items.Count -eq 0) {
    throw "Runtime channel config missing required array field: runtime.$Path"
  }
}

function Test-RuntimeOptionalObjectFields {
  param(
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Config,
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string[]]$RequiredFields
  )

  $value = Get-HashtablePathValue -Source $Config -Path $Path
  if ($null -eq $value) {
    return
  }
  if ($value -isnot [System.Collections.IDictionary]) {
    throw "Runtime channel config field must be an object: runtime.$Path"
  }
  foreach ($field in $RequiredFields) {
    Test-RuntimeRequiredString -Config $Config -Path "$Path.$field"
  }
}

function Test-CiRuntimeChannelConfig {
  param(
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Config,
    [Parameter(Mandatory = $true)][string]$Platform
  )

  foreach ($path in @(
    'channelCode',
    'platform',
    'version',
    'companyName',
    'copyrightNo',
    'ab.configUrl',
    'cloudSave.host',
    'cloudSave.platform',
    'cloudSave.gameCode',
    'cloudSave.version'
  )) {
    Test-RuntimeRequiredString -Config $Config -Path $path
  }

  if ($Platform -in @('wechatgame', 'bytedance')) {
    foreach ($path in @('appId', 'sdk.umaAppKey', 'sdk.sfAppKey')) {
      Test-RuntimeRequiredString -Config $Config -Path $path
    }
    Test-RuntimeRequiredArray -Config $Config -Path 'ads.rewardedVideoIds'
  }

  if ($Platform -eq 'bytedance') {
    foreach ($path in @('videoShareTitle')) {
      Test-RuntimeRequiredString -Config $Config -Path $path
    }
    foreach ($path in @('ads.bannerIds', 'ads.interstitialIds', 'videoTopics')) {
      Test-RuntimeRequiredArray -Config $Config -Path $path
    }
  }

  $wechatGameClubEnabled = Get-HashtablePathValue -Source $Config -Path 'wechatGameClub.enabled'
  if ($wechatGameClubEnabled) {
    Test-RuntimeRequiredString -Config $Config -Path 'wechatGameClub.appId'
    Test-RuntimeRequiredArray -Config $Config -Path 'wechatGameClub.rewardedVideoIds'
  }

  Test-RuntimeOptionalObjectFields -Config $Config -Path 'sdk.internalAnalytics' -RequiredFields @(
    'appKey',
    'endpoint',
    'gameId',
    'projectId',
    'gameName',
    'platform',
    'status'
  )
}

function Read-RawProfileBundle {
  param([Parameter(Mandatory = $true)][hashtable]$Context)

  $profilePath = [string]$Context.Profile.profilePath
  if ([string]::IsNullOrWhiteSpace($profilePath) -or -not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
    return $null
  }

  return ConvertFrom-CiJson -Json (Get-Content -Raw -LiteralPath $profilePath -Encoding UTF8)
}

function Get-MergedProfileSection {
  param(
    [AllowNull()]$RawProfile,
    [Parameter(Mandatory = $true)][string]$Platform,
    [Parameter(Mandatory = $true)][string]$SectionName
  )

  $result = [ordered]@{}
  if ($null -eq $RawProfile) {
    return $result
  }

  if ($RawProfile.PSObject.Properties[$SectionName]) {
    Merge-OrderedHashtable -Target $result -Source $RawProfile.$SectionName
  }
  if ($RawProfile.PSObject.Properties['common'] -and $RawProfile.common.PSObject.Properties[$SectionName]) {
    Merge-OrderedHashtable -Target $result -Source $RawProfile.common.$SectionName
  }
  if ($RawProfile.PSObject.Properties['platforms'] -and $RawProfile.platforms.PSObject.Properties[$Platform]) {
    $platformConfig = $RawProfile.platforms.$Platform
    if ($platformConfig.PSObject.Properties[$SectionName]) {
      Merge-OrderedHashtable -Target $result -Source $platformConfig.$SectionName
    }
  }

  return $result
}

function New-CiRuntimeChannelConfig {
  param([Parameter(Mandatory = $true)][hashtable]$Context)

  $profile = $Context.Profile
  $rawProfile = Read-RawProfileBundle -Context $Context
  $runtime = Get-MergedProfileSection -RawProfile $rawProfile -Platform ([string]$Context.Platform) -SectionName 'runtime'

  Set-HashtablePathValue -Target $runtime -Path 'channelCode' -Value (Get-ProfileString -Profile $profile -Name 'channelCode')
  Set-HashtablePathValue -Target $runtime -Path 'platform' -Value ([string]$Context.Platform)
  Set-HashtablePathValue -Target $runtime -Path 'appId' -Value (Get-ProfileString -Profile $profile -Name 'appId')

  $version = Get-ProfileString -Profile $profile -Name 'version'
  Set-HashtablePathValue -Target $runtime -Path 'version' -Value $version
  Set-HashtablePathValue -Target $runtime -Path 'companyName' -Value (Get-ProfileString -Profile $profile -Name 'companyName')
  Set-HashtablePathValue -Target $runtime -Path 'copyrightNo' -Value (Get-ProfileString -Profile $profile -Name 'copyrightNo')

  foreach ($flag in @('enableGM')) {
    if ($profile.PSObject.Properties[$flag]) {
      Set-HashtablePathValue -Target $runtime -Path $flag -Value (Get-ProfileBoolean -Profile $profile -Name $flag) -AllowEmpty
    }
  }
  Set-HashtablePathValue -Target $runtime -Path 'sdk.umaAppKey' -Value (Get-ProfileString -Profile $profile -Name 'umaAppKey')
  Set-HashtablePathValue -Target $runtime -Path 'sdk.sfAppKey' -Value (Get-ProfileString -Profile $profile -Name 'sfAppKey')

  $rewardedVideoIds = Get-ProfileArray -Profile $profile -Name 'rewardedVideoIds' -LegacyName 'rewardedVideoId'
  Set-HashtablePathValue -Target $runtime -Path 'ads.rewardedVideoIds' -Value $rewardedVideoIds
  Set-HashtablePathValue -Target $runtime -Path 'ads.bannerIds' -Value (Get-ProfileArray -Profile $profile -Name 'bannerIds' -LegacyName 'bannerId')
  Set-HashtablePathValue -Target $runtime -Path 'ads.interstitialIds' -Value (Get-ProfileArray -Profile $profile -Name 'interstitialIds' -LegacyName 'interstitialId')

  Set-HashtablePathValue -Target $runtime -Path 'ab.configUrl' -Value (Get-ProfileString -Profile $profile -Name 'abConfigUrl')

  Set-HashtablePathValue -Target $runtime -Path 'cloudSave.host' -Value (Get-ProfileString -Profile $profile -Name 'cloudSaveHost')
  Set-HashtablePathValue -Target $runtime -Path 'cloudSave.platform' -Value (Get-ProfileString -Profile $profile -Name 'cloudSavePlatform')
  Set-HashtablePathValue -Target $runtime -Path 'cloudSave.gameCode' -Value (Get-ProfileString -Profile $profile -Name 'cloudSaveGameCode')
  Set-HashtablePathValue -Target $runtime -Path 'cloudSave.version' -Value (Get-ProfileString -Profile $profile -Name 'cloudSaveVersion')

  if ($profile.PSObject.Properties['enableWechatGameClub']) {
    Set-HashtablePathValue -Target $runtime -Path 'wechatGameClub.enabled' -Value (Get-ProfileBoolean -Profile $profile -Name 'enableWechatGameClub') -AllowEmpty
  }
  Set-HashtablePathValue -Target $runtime -Path 'wechatGameClub.appId' -Value (Get-ProfileString -Profile $profile -Name 'wechatGameClubAppId')
  Set-HashtablePathValue -Target $runtime -Path 'wechatGameClub.rewardedVideoIds' -Value (Get-ProfileArray -Profile $profile -Name 'wechatGameClubRewardedVideoIds' -LegacyName 'wechatGameClubRewardedVideoId')

  Set-HashtablePathValue -Target $runtime -Path 'videoShareTitle' -Value (Get-ProfileString -Profile $profile -Name 'videoShareTitle')
  $videoTopics = Get-ProfileArray -Profile $profile -Name 'videoTopics'
  Set-HashtablePathValue -Target $runtime -Path 'videoTopics' -Value $videoTopics

  Test-CiRuntimeChannelConfig -Config $runtime -Platform ([string]$Context.Platform)
  return $runtime
}

function ConvertTo-ChannelConfigJavaScript {
  param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Config)

  $json = ConvertTo-Json -InputObject $Config -Depth 80 -Compress
  $json = $json -replace '</script', '<\/script'
  return @"
;(function () {
  var root = (typeof globalThis !== 'undefined') ? globalThis : ((typeof window !== 'undefined') ? window : ((typeof GameGlobal !== 'undefined') ? GameGlobal : this));
  var config = $json;
  root.__CHANNEL_CONFIG__ = config;
  if (typeof window !== 'undefined') window.__CHANNEL_CONFIG__ = config;
})();
"@
}

function Add-TextBeforeFirstMatch {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Insertion
  )

  $match = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if (-not $match.Success) {
    return $Insertion + [Environment]::NewLine + $Text
  }
  return $Text.Substring(0, $match.Index) + $Insertion + [Environment]::NewLine + $Text.Substring($match.Index)
}

function Write-CiRuntimeConfigFile {
  param(
    [Parameter(Mandatory = $true)][string]$BuildDir,
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Config
  )

  $configPath = Join-Path $BuildDir 'channel-config.js'
  $script = ConvertTo-ChannelConfigJavaScript -Config $Config
  Set-Content -LiteralPath $configPath -Value $script -Encoding UTF8
  return $configPath
}

function Inject-CiRuntimeConfigIntoWebIndex {
  param([Parameter(Mandatory = $true)][string]$IndexPath)

  $text = Get-Content -Raw -LiteralPath $IndexPath -Encoding UTF8
  if ($text -match 'channel-config\.js') {
    return
  }

  $tag = '<script src="channel-config.js" charset="utf-8"></script>'
  $text = Add-TextBeforeFirstMatch -Text $text -Pattern '<script\s+src="src/settings\.js"' -Insertion $tag
  Set-Content -LiteralPath $IndexPath -Value $text -Encoding UTF8
}

function Inject-CiRuntimeConfigIntoGameJs {
  param([Parameter(Mandatory = $true)][string]$GameJsPath)

  $text = Get-Content -Raw -LiteralPath $GameJsPath -Encoding UTF8
  if ($text -match 'channel-config\.js') {
    return
  }

  $requireLine = 'require("./channel-config.js");'
  Set-Content -LiteralPath $GameJsPath -Value ($requireLine + [Environment]::NewLine + $text) -Encoding UTF8
}

function Inject-CiRuntimeConfigInlineHtml {
  param(
    [Parameter(Mandatory = $true)][string]$HtmlPath,
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Config
  )

  $text = Get-Content -Raw -LiteralPath $HtmlPath -Encoding UTF8
  if ($text -match '__CHANNEL_CONFIG__') {
    return
  }

  $script = ConvertTo-ChannelConfigJavaScript -Config $Config
  $tag = "<script type=""text/javascript"">`n$script`n</script>"
  $text = Add-TextBeforeFirstMatch -Text $text -Pattern '<script\b' -Insertion $tag
  Set-Content -LiteralPath $HtmlPath -Value $text -Encoding UTF8
}

function Update-JsonFileProperties {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Properties
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $false
  }

  $json = Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json
  foreach ($key in $Properties.Keys) {
    if ($json.PSObject.Properties[$key]) {
      $json.$key = $Properties[$key]
    }
    else {
      $json | Add-Member -NotePropertyName $key -NotePropertyValue $Properties[$key]
    }
  }
  $jsonText = $json | ConvertTo-Json -Depth 80
  [System.IO.File]::WriteAllText($Path, $jsonText, [System.Text.UTF8Encoding]::new($false))
  return $true
}

function Update-CiRuntimeManifest {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Context,
    [Parameter(Mandatory = $true)][string]$BuildDir
  )

  $rawProfile = Read-RawProfileBundle -Context $Context
  $manifest = Get-MergedProfileSection -RawProfile $rawProfile -Platform ([string]$Context.Platform) -SectionName 'manifest'
  $appId = Get-ProfileString -Profile $Context.Profile -Name 'appId'
  if (-not [string]::IsNullOrWhiteSpace($appId) -and [string]$Context.Platform -in @('wechatgame', 'bytedance')) {
    $manifest['appid'] = $appId
  }

  $updated = @()
  if ($manifest.Count -gt 0) {
    $projectConfigPath = Join-Path $BuildDir 'project.config.json'
    if (Update-JsonFileProperties -Path $projectConfigPath -Properties $manifest) {
      $updated += $projectConfigPath
    }
  }

  return $updated
}

function Invoke-CiRuntimeConfigInjection {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Context,
    [string]$BuildDir = '',
    [switch]$InlineHtmlOnly
  )

  if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    $BuildDir = [string]$Context.Artifacts.buildDir
  }
  if ([string]::IsNullOrWhiteSpace($BuildDir) -or -not (Test-Path -LiteralPath $BuildDir -PathType Container)) {
    Write-CiLog -Level WARN -Message 'Runtime channel config injection skipped because buildDir is empty.'
    return
  }

  $config = New-CiRuntimeChannelConfig -Context $Context
  $configPath = ''
  $injectedEntries = @()
  $manifestFiles = @()

  if ($InlineHtmlOnly) {
    $htmlFiles = @(Get-ChildItem -LiteralPath $BuildDir -Recurse -File -Filter '*.html' -ErrorAction SilentlyContinue)
    foreach ($htmlFile in $htmlFiles) {
      Inject-CiRuntimeConfigInlineHtml -HtmlPath $htmlFile.FullName -Config $config
      $injectedEntries += $htmlFile.FullName
    }
  }
  else {
    $configPath = Write-CiRuntimeConfigFile -BuildDir $BuildDir -Config $config

    if ([string]$Context.Platform -eq 'web-mobile') {
      $indexPath = Join-Path $BuildDir 'index.html'
      if (Test-Path -LiteralPath $indexPath -PathType Leaf) {
        Inject-CiRuntimeConfigIntoWebIndex -IndexPath $indexPath
        $injectedEntries += $indexPath
      }
    }
    elseif ([string]$Context.Platform -in @('wechatgame', 'bytedance')) {
      $gameJsPath = Join-Path $BuildDir 'game.js'
      if (Test-Path -LiteralPath $gameJsPath -PathType Leaf) {
        Inject-CiRuntimeConfigIntoGameJs -GameJsPath $gameJsPath
        $injectedEntries += $gameJsPath
      }
      $manifestFiles = Update-CiRuntimeManifest -Context $Context -BuildDir $BuildDir
    }
  }

  $artifact = @{
    status = 'SUCCESS'
    buildDir = $BuildDir
    configPath = $configPath
    inlineHtmlOnly = [bool]$InlineHtmlOnly
    entries = $injectedEntries
    manifestFiles = $manifestFiles
  }
  if ($InlineHtmlOnly) {
    $Context.Artifacts.runtimeConfigInlineHtml = $artifact
  }
  else {
    $Context.Artifacts.runtimeConfig = $artifact
  }
  Write-CiArtifacts -Context $Context
  Write-CiLog -Level INFO -Message "Runtime channel config injected. buildDir=$BuildDir entries=$($injectedEntries.Count)"
}

function Test-CiRuntimeConfigInjection {
  param([Parameter(Mandatory = $true)][hashtable]$Context)

  $buildDir = [string]$Context.Artifacts.buildDir
  if ([string]::IsNullOrWhiteSpace($buildDir) -or -not (Test-Path -LiteralPath $buildDir -PathType Container)) {
    return
  }

  $checks = @()
  $configPath = Join-Path $buildDir 'channel-config.js'
  $checks += @{ field = 'channel-config.js'; found = (Test-Path -LiteralPath $configPath -PathType Leaf) }

  $entryPath = [string]$Context.Artifacts.entry
  if (-not [string]::IsNullOrWhiteSpace($entryPath) -and (Test-Path -LiteralPath $entryPath -PathType Leaf)) {
    $entryText = Get-Content -Raw -LiteralPath $entryPath -Encoding UTF8
    $checks += @{ field = 'entry-reference'; found = [bool]($entryText -match 'channel-config\.js|__CHANNEL_CONFIG__') }
  }

  $Context.Artifacts.runtimeConfigValidation = $checks
  Write-CiArtifacts -Context $Context

  $failed = @($checks | Where-Object { -not $_.found })
  if ($failed.Count -gt 0) {
    Write-CiLog -Level WARN -Message "Runtime config validation did not find: $(($failed | ForEach-Object { $_.field }) -join ', ')"
  }
  else {
    Write-CiLog -Level INFO -Message 'Runtime config validation completed.'
  }
}

