[CmdletBinding()]
param(
  [ValidateSet('All', 'Windows', 'Web', 'Android', 'Analyze', 'Test', 'Diagnose', 'Clean')]
  [string]$Target = 'All',

  [switch]$SkipChecks,

  [switch]$ForceRebuild,

  [switch]$DisableLowDiskCleanup,

  [ValidateRange(1, 32)]
  [int]$MinimumAndroidFreeSpaceGB = 3,

  [string]$FlutterRoot = 'N:\Codex\Compilers\flutter'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = $PSScriptRoot
$FlutterBat = Join-Path $FlutterRoot 'bin\flutter.bat'
$PubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'
$LogRoot = Join-Path $ProjectRoot 'build_logs'
$TranscriptStarted = $false
$CurrentReleaseDirectory = $null

function Write-Step {
  param([string]$Message)
  Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Save-Utf8NoBom {
  param([string]$Path, [string]$Text)
  $Encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Text, $Encoding)
}

function Invoke-Flutter {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)

  Write-Host ("flutter " + ($Arguments -join ' ')) -ForegroundColor DarkGray
  & $script:FlutterBat @Arguments
  $ExitCode = $LASTEXITCODE
  if ($ExitCode -ne 0) {
    $CommandText = $Arguments -join ' '
    throw ("Flutter command failed with exit code {0}: flutter {1}" -f $ExitCode, $CommandText)
  }
}

function Get-ProjectVersion {
  if (-not (Test-Path -LiteralPath $script:PubspecPath)) {
    throw "pubspec.yaml not found: $script:PubspecPath"
  }

  $Match = Select-String -LiteralPath $script:PubspecPath -Pattern '^\s*version:\s*([^\s#]+)' | Select-Object -First 1
  if ($null -eq $Match) {
    throw 'Version is missing in pubspec.yaml.'
  }

  $FullVersion = $Match.Matches[0].Groups[1].Value.Trim()
  $Parts = $FullVersion -split '\+', 2
  $Name = $Parts[0]
  $Number = if ($Parts.Count -gt 1 -and $Parts[1]) { $Parts[1] } else { '1' }

  if ($Name -notmatch '^\d+\.\d+\.\d+([-.][0-9A-Za-z.-]+)?$') {
    throw "Unsupported version format in pubspec.yaml: $FullVersion"
  }
  if ($Number -notmatch '^\d+$') {
    throw "Android build number must be numeric: $Number"
  }

  [PSCustomObject]@{
    Full = $FullVersion
    Name = $Name
    Number = $Number
    ReleaseName = "AIAgent_v.$Name"
  }
}

function Assert-Environment {
  if (-not (Test-Path -LiteralPath $script:FlutterBat -PathType Leaf)) {
    throw "Flutter was not found at the required path: $script:FlutterBat"
  }
  if (-not (Test-Path -LiteralPath $script:PubspecPath -PathType Leaf)) {
    throw "Flutter project was not found: $script:ProjectRoot"
  }
}

function Assert-RequiredSourceFiles {
  $RequiredFiles = @(
    'lib\agent_core\build\build_failure_analyzer.dart',
    'lib\agent_core\build\build_working_directory_resolver.dart',
    'lib\agent_core\build\cmake_command_resolver.dart',
    'lib\agent_core\build\cpp_build_command_builder.dart',
    'lib\agent_core\build\project_build_recipe.dart',
    'lib\agent_core\dependencies\cpp_dependency_preflight.dart',
    'lib\agent_core\memory\context_archive_service.dart',
    'lib\agent_core\memory\local_memory_service.dart',
    'lib\agent_core\planning\guided_execution_coach.dart',
    'lib\agent_core\planning\project_agent_configuration.dart',
    'lib\agent_core\planning\project_task_mode.dart',
    'lib\agent_core\planning\task_execution_state.dart',
    'lib\agent_core\prompts\agent_prompt_templates.dart',
    'lib\agent_core\release\project_release_packager.dart',
    'lib\agent_core\safety\tool_call_contract.dart',
    'lib\agent_core\safety\tool_call_json_repair.dart',
    'lib\agent_core\safety\unsupported_success_claim_guard.dart',
    'documents\README_RU.txt'
  )

  $MissingFiles = @()
  foreach ($RelativePath in $RequiredFiles) {
    $FullPath = Join-Path $script:ProjectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
      $MissingFiles += $RelativePath
    }
  }

  if ($MissingFiles.Count -gt 0) {
    $MissingText = $MissingFiles -join ', '
    throw ("Required source modules are missing from the project archive: {0}. Agent-core source packages must not be excluded as generated output." -f $MissingText)
  }
}

function Format-ByteSize {
  param([Parameter(Mandatory = $true)][long]$Bytes)

  if ($Bytes -ge 1099511627776) { return ('{0:N2} TB' -f ($Bytes / 1099511627776)) }
  if ($Bytes -ge 1073741824) { return ('{0:N2} GB' -f ($Bytes / 1073741824)) }
  if ($Bytes -ge 1048576) { return ('{0:N2} MB' -f ($Bytes / 1048576)) }
  if ($Bytes -ge 1024) { return ('{0:N2} KB' -f ($Bytes / 1024)) }
  return ("$Bytes bytes")
}

function Get-DiskSpaceInfo {
  param([Parameter(Mandatory = $true)][string]$Path)

  try {
    $FullPath = [System.IO.Path]::GetFullPath($Path)
    $Root = [System.IO.Path]::GetPathRoot($FullPath)
    if ([string]::IsNullOrWhiteSpace($Root)) { return $null }

    try {
      $Drive = New-Object -TypeName System.IO.DriveInfo -ArgumentList $Root
      if ($Drive.IsReady) {
        return [PSCustomObject]@{
          Root = $Root
          AvailableBytes = [long]$Drive.AvailableFreeSpace
          TotalBytes = [long]$Drive.TotalSize
        }
      }
    } catch {
      # Mapped or provider-backed drives are handled by Get-PSDrive below.
    }

    $Qualifier = Split-Path -Qualifier $FullPath
    if ([string]::IsNullOrWhiteSpace($Qualifier)) { return $null }
    $DriveName = $Qualifier.TrimEnd([char]'\').TrimEnd([char]':')
    $PsDrive = Get-PSDrive -Name $DriveName -ErrorAction SilentlyContinue
    if ($null -eq $PsDrive -or $null -eq $PsDrive.Free) { return $null }

    return [PSCustomObject]@{
      Root = $Qualifier
      AvailableBytes = [long]$PsDrive.Free
      TotalBytes = [long]($PsDrive.Used + $PsDrive.Free)
    }
  } catch {
    return $null
  }
}

function Remove-GeneratedBuildData {
  param([string]$Reason = 'low disk space')

  Write-Step ("Cleaning generated caches because of {0}" -f $Reason)
  $GeneratedPaths = @(
    'build',
    '.dart_tool\flutter_build',
    'android\.gradle',
    'android\.cxx',
    'android\app\.cxx'
  )

  foreach ($RelativePath in $GeneratedPaths) {
    $FullPath = Join-Path $script:ProjectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $FullPath)) { continue }
    try {
      Remove-Item -LiteralPath $FullPath -Recurse -Force
      Write-Host ("Removed generated path: {0}" -f $FullPath) -ForegroundColor DarkYellow
    } catch {
      Write-Warning ("Generated path could not be removed: {0}. {1}" -f $FullPath, $_.Exception.Message)
    }
  }
}

function Ensure-BuildDiskSpace {
  param(
    [Parameter(Mandatory = $true)][string]$Stage,
    [Parameter(Mandatory = $true)][int]$RequiredGB
  )

  $RequiredBytes = [long]$RequiredGB * 1073741824
  $Info = Get-DiskSpaceInfo -Path $script:ProjectRoot
  if ($null -eq $Info) {
    Write-Warning "Free disk space could not be determined for $script:ProjectRoot. Continuing without the preflight threshold."
    return
  }

  Write-Host ("Disk preflight [{0}]: {1} free on {2}; recommended minimum {3}." -f `
      $Stage, (Format-ByteSize $Info.AvailableBytes), $Info.Root, (Format-ByteSize $RequiredBytes)) -ForegroundColor DarkGray
  if ($Info.AvailableBytes -ge $RequiredBytes) { return }

  if (-not $script:DisableLowDiskCleanup) {
    Remove-GeneratedBuildData -Reason ("insufficient space before {0}" -f $Stage)
    $Info = Get-DiskSpaceInfo -Path $script:ProjectRoot
    if ($null -ne $Info) {
      Write-Host ("Free space after safe cleanup: {0}." -f (Format-ByteSize $Info.AvailableBytes)) -ForegroundColor DarkGray
      if ($Info.AvailableBytes -ge $RequiredBytes) { return }
    }
  }

  $Available = if ($null -eq $Info) { 'unknown' } else { Format-ByteSize $Info.AvailableBytes }
  $Message = ("Not enough free space for {0}. Available: {1}; recommended minimum: {2}. " +
    "Completed release artifacts in dist are preserved. Free space on the project drive, remove obsolete dist versions manually, " +
    "or retry a single target with build_android.bat/build_web.bat/build_windows.bat. Generated caches can be removed with build.ps1 -Target Clean.") -f `
    $Stage, $Available, (Format-ByteSize $RequiredBytes)
  throw $Message
}

function Test-ReleaseArtifact {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [long]$MinimumBytes = 1024
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $Item = Get-Item -LiteralPath $Path
  return $Item.Length -ge $MinimumBytes
}

function Write-SkippedArtifact {
  param(
    [Parameter(Mandatory = $true)][string]$Platform,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $Item = Get-Item -LiteralPath $Path
  Write-Step ("Skipping {0}: completed artifact already exists" -f $Platform)
  Write-Host ("Existing: {0} ({1})" -f $Item.FullName, (Format-ByteSize $Item.Length)) -ForegroundColor Green
  Write-Host 'Use -ForceRebuild to rebuild existing artifacts for the same version.' -ForegroundColor DarkGray
}

function Patch-AndroidManifest {
  $ManifestPath = Join-Path $script:ProjectRoot 'android\app\src\main\AndroidManifest.xml'
  if (-not (Test-Path -LiteralPath $ManifestPath)) { return }

  $Text = [System.IO.File]::ReadAllText($ManifestPath, [System.Text.Encoding]::UTF8)
  $Text = $Text -replace '`r`n', [Environment]::NewLine
  $Text = $Text -replace '`n', [Environment]::NewLine

  if ($Text -notmatch 'xmlns:android=') {
    $Text = [regex]::Replace(
      $Text,
      '<manifest\b',
      '<manifest xmlns:android="http://schemas.android.com/apk/res/android"',
      1
    )
  }

  $Permissions = @(
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.READ_EXTERNAL_STORAGE',
    'android.permission.WRITE_EXTERNAL_STORAGE',
    'android.permission.MANAGE_EXTERNAL_STORAGE',
    'android.permission.QUERY_ALL_PACKAGES'
  )

  foreach ($Permission in $Permissions) {
    if ($Text -notmatch [regex]::Escape($Permission)) {
      $Line = '    <uses-permission android:name="' + $Permission + '" />'
      $Text = [regex]::Replace(
        $Text,
        '(<manifest\b[^>]*>)',
        '$1' + [Environment]::NewLine + $Line,
        1
      )
    }
  }

  if ($Text -match '<application\b[^>]*android:label=') {
    $Text = [regex]::Replace($Text, 'android:label="[^"]*"', 'android:label="AI Agent"', 1)
  } else {
    $Text = [regex]::Replace($Text, '<application\b', '<application android:label="AI Agent"', 1)
  }

  if ($Text -notmatch '<application\b[^>]*android:usesCleartextTraffic=') {
    $Text = [regex]::Replace(
      $Text,
      '<application\b',
      '<application android:usesCleartextTraffic="true"',
      1
    )
  }

  if ($Text -notmatch '<application\b[^>]*android:hardwareAccelerated=') {
    $Text = [regex]::Replace(
      $Text,
      '<application\b',
      '<application android:hardwareAccelerated="true"',
      1
    )
  }

  try {
    [void]([xml]$Text)
  } catch {
    throw "AndroidManifest.xml is invalid after patching: $($_.Exception.Message)"
  }

  Save-Utf8NoBom -Path $ManifestPath -Text $Text
}

function Patch-WindowsRunner {
  $CMakePath = Join-Path $script:ProjectRoot 'windows\CMakeLists.txt'
  if (Test-Path -LiteralPath $CMakePath) {
    $Text = [System.IO.File]::ReadAllText($CMakePath, [System.Text.Encoding]::UTF8)
    $Text = [regex]::Replace(
      $Text,
      'set\(BINARY_NAME\s+"[^"]+"\)',
      'set(BINARY_NAME "AIAgent")',
      1
    )
    Save-Utf8NoBom -Path $CMakePath -Text $Text
  }

  $MainPath = Join-Path $script:ProjectRoot 'windows\runner\main.cpp'
  if (Test-Path -LiteralPath $MainPath) {
    $Text = [System.IO.File]::ReadAllText($MainPath, [System.Text.Encoding]::UTF8)
    $Text = [regex]::Replace(
      $Text,
      'CreateAndShow\(L"[^"]*"',
      'CreateAndShow(L"AI Agent"',
      1
    )
    Save-Utf8NoBom -Path $MainPath -Text $Text
  }
}

function Patch-WebRunner {
  $IndexPath = Join-Path $script:ProjectRoot 'web\index.html'
  if (Test-Path -LiteralPath $IndexPath) {
    $Text = [System.IO.File]::ReadAllText($IndexPath, [System.Text.Encoding]::UTF8)
    $Text = [regex]::Replace($Text, '<title>.*?</title>', '<title>AI Agent</title>', 1)
    $Text = [regex]::Replace(
      $Text,
      '<meta name="apple-mobile-web-app-title" content="[^"]*">',
      '<meta name="apple-mobile-web-app-title" content="AI Agent">',
      1
    )
    Save-Utf8NoBom -Path $IndexPath -Text $Text
  }

  $ManifestPath = Join-Path $script:ProjectRoot 'web\manifest.json'
  if (Test-Path -LiteralPath $ManifestPath) {
    $Manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
    $Manifest.name = 'AI Agent'
    $Manifest.short_name = 'AI Agent'
    $Json = $Manifest | ConvertTo-Json -Depth 20
    Save-Utf8NoBom -Path $ManifestPath -Text $Json
  }
}

function Resize-Png {
  param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [Parameter(Mandatory = $true)][int]$Size
  )

  Add-Type -AssemblyName System.Drawing
  $SourceImage = [System.Drawing.Image]::FromFile($SourcePath)
  try {
    $Bitmap = New-Object System.Drawing.Bitmap -ArgumentList $Size, $Size
    try {
      $Bitmap.SetResolution(96, 96)
      $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
      try {
        $Graphics.Clear([System.Drawing.Color]::Transparent)
        $Graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $Graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $Graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $Graphics.DrawImage($SourceImage, 0, 0, $Size, $Size)
      } finally {
        $Graphics.Dispose()
      }

      $Parent = Split-Path -Parent $DestinationPath
      New-Item -ItemType Directory -Path $Parent -Force | Out-Null
      $Bitmap.Save($DestinationPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
      $Bitmap.Dispose()
    }
  } finally {
    $SourceImage.Dispose()
  }
}

function Update-AppIcons {
  $PngSource = Join-Path $script:ProjectRoot 'icon\logo.png'
  $IcoSource = Join-Path $script:ProjectRoot 'icon\logo.ico'

  if (Test-Path -LiteralPath $IcoSource) {
    $WindowsIcon = Join-Path $script:ProjectRoot 'windows\runner\resources\app_icon.ico'
    if (Test-Path -LiteralPath (Split-Path -Parent $WindowsIcon)) {
      Copy-Item -LiteralPath $IcoSource -Destination $WindowsIcon -Force
    }
  }

  if (-not (Test-Path -LiteralPath $PngSource)) { return }

  try {
    $WebIcons = @(
      @{ Path = 'web\favicon.png'; Size = 32 },
      @{ Path = 'web\icons\Icon-192.png'; Size = 192 },
      @{ Path = 'web\icons\Icon-512.png'; Size = 512 },
      @{ Path = 'web\icons\Icon-maskable-192.png'; Size = 192 },
      @{ Path = 'web\icons\Icon-maskable-512.png'; Size = 512 }
    )
    foreach ($Icon in $WebIcons) {
      $Destination = Join-Path $script:ProjectRoot $Icon.Path
      if (Test-Path -LiteralPath (Split-Path -Parent $Destination)) {
        Resize-Png -SourcePath $PngSource -DestinationPath $Destination -Size $Icon.Size
      }
    }

    $AndroidIcons = @(
      @{ Folder = 'mipmap-mdpi'; Size = 48 },
      @{ Folder = 'mipmap-hdpi'; Size = 72 },
      @{ Folder = 'mipmap-xhdpi'; Size = 96 },
      @{ Folder = 'mipmap-xxhdpi'; Size = 144 },
      @{ Folder = 'mipmap-xxxhdpi'; Size = 192 }
    )
    foreach ($Icon in $AndroidIcons) {
      $Destination = Join-Path $script:ProjectRoot ("android\app\src\main\res\{0}\ic_launcher.png" -f $Icon.Folder)
      Resize-Png -SourcePath $PngSource -DestinationPath $Destination -Size $Icon.Size
    }
  } catch {
    Write-Warning "Application icons could not be refreshed: $($_.Exception.Message)"
  }
}

function Ensure-Platforms {
  Write-Step 'Enabling Flutter desktop and web targets'
  Invoke-Flutter -Arguments @('config', '--enable-windows-desktop', '--enable-web')

  $Missing = @()
  foreach ($Name in @('windows', 'web', 'android')) {
    if (-not (Test-Path -LiteralPath (Join-Path $script:ProjectRoot $Name))) {
      $Missing += $Name
    }
  }

  if ($Missing.Count -gt 0) {
    Write-Step ("Creating missing Flutter platform files: " + ($Missing -join ', '))
    Invoke-Flutter -Arguments @(
      'create',
      '--platforms=windows,web,android',
      '--project-name=ii_agent',
      '.'
    )
  }

  Patch-WindowsRunner
  Patch-WebRunner
  Patch-AndroidManifest
  Update-AppIcons
}

function Restore-Packages {
  Write-Step 'Restoring Flutter packages'
  Invoke-Flutter -Arguments @('pub', 'get')
}

function Invoke-Analyze {
  Write-Step 'Analyzing application sources'
  Invoke-Flutter -Arguments @(
    'analyze',
    '--no-fatal-infos',
    '--no-fatal-warnings',
    'lib'
  )

  $Tests = @(Get-ChildItem -LiteralPath (Join-Path $script:ProjectRoot 'test') -Filter '*_test.dart' -File -Recurse -ErrorAction SilentlyContinue)
  if ($Tests.Count -gt 0) {
    Invoke-Flutter -Arguments @(
      'analyze',
      '--no-fatal-infos',
      '--no-fatal-warnings',
      'test'
    )
  }
}

function Invoke-Tests {
  $TestRoot = Join-Path $script:ProjectRoot 'test'
  $Tests = @(Get-ChildItem -LiteralPath $TestRoot -Filter '*_test.dart' -File -Recurse -ErrorAction SilentlyContinue)
  if ($Tests.Count -eq 0) {
    Write-Host 'No Flutter tests were found. Test step skipped.' -ForegroundColor Yellow
    return
  }

  Write-Step 'Running Flutter tests'
  Invoke-Flutter -Arguments @('test', 'test')
}

function Invoke-Checks {
  Invoke-Analyze
  Invoke-Tests
}

function Ensure-ReleaseDirectory {
  param(
    [Parameter(Mandatory = $true)]$Version,
    [switch]$Reset
  )

  $DistRoot = Join-Path $script:ProjectRoot 'dist'
  $ReleaseDirectory = Join-Path $DistRoot $Version.ReleaseName

  if ($Reset -and (Test-Path -LiteralPath $ReleaseDirectory)) {
    Remove-Item -LiteralPath $ReleaseDirectory -Recurse -Force
  }
  New-Item -ItemType Directory -Path $ReleaseDirectory -Force | Out-Null
  return $ReleaseDirectory
}

function Compress-Directory {
  param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$DestinationZip
  )

  if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
    throw "Directory to archive was not found: $SourceDirectory"
  }
  if (Test-Path -LiteralPath $DestinationZip) {
    Remove-Item -LiteralPath $DestinationZip -Force
  }

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::CreateFromDirectory(
    $SourceDirectory,
    $DestinationZip,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
  )
}

function Get-DartDefines {
  param([Parameter(Mandatory = $true)]$Version)
  return @(
    "--dart-define=APP_VERSION=$($Version.Name)",
    "--dart-define=APP_BUILD_NUMBER=$($Version.Number)"
  )
}

function Build-Windows {
  param(
    [Parameter(Mandatory = $true)]$Version,
    [Parameter(Mandatory = $true)][string]$ReleaseDirectory
  )

  $ZipPath = Join-Path $ReleaseDirectory "$($Version.ReleaseName)_win.zip"
  if (-not $script:ForceRebuild -and (Test-ReleaseArtifact -Path $ZipPath -MinimumBytes 1048576)) {
    Write-SkippedArtifact -Platform 'Windows release' -Path $ZipPath
    return
  }

  Ensure-BuildDiskSpace -Stage 'Windows release build' -RequiredGB 2
  Write-Step 'Building Windows release'
  $Arguments = @('build', 'windows', '--release') + (Get-DartDefines -Version $Version)
  Invoke-Flutter -Arguments $Arguments

  $Preferred = Join-Path $script:ProjectRoot 'build\windows\x64\runner\Release'
  $SourceDirectory = $Preferred
  if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
    $Candidate = Get-ChildItem -LiteralPath (Join-Path $script:ProjectRoot 'build\windows') -Directory -Recurse -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -eq 'Release' -and (Get-ChildItem -LiteralPath $_.FullName -Filter '*.exe' -File -ErrorAction SilentlyContinue) } |
      Select-Object -First 1
    if ($null -eq $Candidate) {
      throw 'Windows release directory was not found after a successful Flutter build.'
    }
    $SourceDirectory = $Candidate.FullName
  }

  $Stage = Join-Path $script:ProjectRoot 'build\package_stage\windows'
  if (Test-Path -LiteralPath $Stage) {
    Remove-Item -LiteralPath $Stage -Recurse -Force
  }
  New-Item -ItemType Directory -Path $Stage -Force | Out-Null
  Copy-Item -Path (Join-Path $SourceDirectory '*') -Destination $Stage -Recurse -Force
  $DocumentsSource = Join-Path $script:ProjectRoot 'documents'
  if (Test-Path -LiteralPath $DocumentsSource -PathType Container) {
    $DocumentsDestination = Join-Path $Stage 'documents'
    New-Item -ItemType Directory -Path $DocumentsDestination -Force | Out-Null
    Copy-Item -Path (Join-Path $DocumentsSource '*') -Destination $DocumentsDestination -Recurse -Force
  }

  $ExpectedExe = Join-Path $Stage 'AIAgent.exe'
  if (-not (Test-Path -LiteralPath $ExpectedExe)) {
    $BuiltExe = Get-ChildItem -LiteralPath $Stage -Filter '*.exe' -File | Select-Object -First 1
    if ($null -eq $BuiltExe) {
      throw 'Windows executable was not found in the release directory.'
    }
    Rename-Item -LiteralPath $BuiltExe.FullName -NewName 'AIAgent.exe'
  }

  try {
    Compress-Directory -SourceDirectory $Stage -DestinationZip $ZipPath
    Write-Host "Created: $ZipPath" -ForegroundColor Green
  } finally {
    if (Test-Path -LiteralPath $Stage) {
      Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

function Build-Web {
  param(
    [Parameter(Mandatory = $true)]$Version,
    [Parameter(Mandatory = $true)][string]$ReleaseDirectory
  )

  $ZipPath = Join-Path $ReleaseDirectory "$($Version.ReleaseName)_web.zip"
  if (-not $script:ForceRebuild -and (Test-ReleaseArtifact -Path $ZipPath -MinimumBytes 1048576)) {
    Write-SkippedArtifact -Platform 'Web release' -Path $ZipPath
    return
  }

  Ensure-BuildDiskSpace -Stage 'Web release build' -RequiredGB 1
  Write-Step 'Building Web release'
  $Arguments = @('build', 'web', '--release') + (Get-DartDefines -Version $Version)
  Invoke-Flutter -Arguments $Arguments

  $SourceDirectory = Join-Path $script:ProjectRoot 'build\web'
  if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory 'index.html'))) {
    throw 'Web release files were not found after a successful Flutter build.'
  }

  Compress-Directory -SourceDirectory $SourceDirectory -DestinationZip $ZipPath
  Write-Host "Created: $ZipPath" -ForegroundColor Green
}

function Build-Android {
  param(
    [Parameter(Mandatory = $true)]$Version,
    [Parameter(Mandatory = $true)][string]$ReleaseDirectory
  )

  $DestinationApk = Join-Path $ReleaseDirectory "$($Version.ReleaseName)_android.apk"
  if (-not $script:ForceRebuild -and (Test-ReleaseArtifact -Path $DestinationApk -MinimumBytes 1048576)) {
    Write-SkippedArtifact -Platform 'Android release' -Path $DestinationApk
    return
  }

  Ensure-BuildDiskSpace -Stage 'Android release build' -RequiredGB $script:MinimumAndroidFreeSpaceGB
  Write-Step 'Building Android release APK'
  $Arguments = @(
    'build',
    'apk',
    '--release',
    "--build-name=$($Version.Name)",
    "--build-number=$($Version.Number)"
  ) + (Get-DartDefines -Version $Version)
  try {
    Invoke-Flutter -Arguments $Arguments
  } catch {
    $Info = Get-DiskSpaceInfo -Path $script:ProjectRoot
    $LowSpaceAfterFailure = $null -ne $Info -and $Info.AvailableBytes -lt 1073741824
    if ($script:DisableLowDiskCleanup -or -not $LowSpaceAfterFailure) {
      throw
    }

    Write-Warning ("Android build failed while only {0} remained free. Generated caches will be removed and the Android build will be retried once." -f (Format-ByteSize $Info.AvailableBytes))
    Remove-GeneratedBuildData -Reason 'disk exhaustion during Android build'
    Ensure-BuildDiskSpace -Stage 'Android release retry' -RequiredGB $script:MinimumAndroidFreeSpaceGB
    Invoke-Flutter -Arguments $Arguments
  }

  $SourceApk = Join-Path $script:ProjectRoot 'build\app\outputs\flutter-apk\app-release.apk'
  if (-not (Test-Path -LiteralPath $SourceApk -PathType Leaf)) {
    $Candidate = Get-ChildItem -LiteralPath (Join-Path $script:ProjectRoot 'build') -Filter 'app-release.apk' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $Candidate) {
      throw 'Android release APK was not found after a successful Flutter build.'
    }
    $SourceApk = $Candidate.FullName
  }

  Copy-Item -LiteralPath $SourceApk -Destination $DestinationApk -Force
  Write-Host "Created: $DestinationApk" -ForegroundColor Green
}

function Show-ReleaseFiles {
  param([string]$ReleaseDirectory)

  Write-Step 'Release artifacts'
  Get-ChildItem -LiteralPath $ReleaseDirectory -File |
    Sort-Object Name |
    ForEach-Object {
      $SizeMb = [Math]::Round($_.Length / 1048576, 2)
      Write-Host ("{0} ({1} MB)" -f $_.FullName, $SizeMb) -ForegroundColor Green
    }
}

function Invoke-Diagnostics {
  param([Parameter(Mandatory = $true)]$Version)

  Write-Step 'Build environment'
  Write-Host "Project: $script:ProjectRoot"
  Write-Host "Flutter: $script:FlutterBat"
  Write-Host "Version: $($Version.Full)"
  Write-Host "Release folder: $(Join-Path (Join-Path $script:ProjectRoot 'dist') $Version.ReleaseName)"
  Invoke-Flutter -Arguments @('--version')
  Invoke-Flutter -Arguments @('doctor', '-v')
}

function Invoke-Clean {
  param([Parameter(Mandatory = $true)]$Version)

  Write-Step 'Cleaning generated build files'
  Invoke-Flutter -Arguments @('clean')
  Remove-GeneratedBuildData -Reason 'explicit clean target'

  $ReleaseDirectory = Join-Path (Join-Path $script:ProjectRoot 'dist') $Version.ReleaseName
  if ($script:ForceRebuild -and (Test-Path -LiteralPath $ReleaseDirectory)) {
    Remove-Item -LiteralPath $ReleaseDirectory -Recurse -Force
    Write-Host "Removed release artifacts because -ForceRebuild was supplied: $ReleaseDirectory" -ForegroundColor DarkYellow
  } elseif (Test-Path -LiteralPath $ReleaseDirectory) {
    Write-Host "Release artifacts were preserved: $ReleaseDirectory" -ForegroundColor Green
  }
}

try {
  Assert-Environment
  Assert-RequiredSourceFiles
  $Version = Get-ProjectVersion

  New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
  $Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $LogPath = Join-Path $LogRoot "build_${Target}_$Stamp.log"
  try {
    Start-Transcript -LiteralPath $LogPath -Force | Out-Null
    $TranscriptStarted = $true
  } catch {
    Write-Warning "Transcript could not be started: $($_.Exception.Message)"
  }

  Write-Host 'AI Agent release builder' -ForegroundColor White
  Write-Host "Target: $Target"
  Write-Host "Project: $ProjectRoot"
  Write-Host "Flutter: $FlutterBat"
  Write-Host "Version: $($Version.Full)"

  Push-Location $ProjectRoot
  try {
    if ($Target -eq 'Diagnose') {
      Invoke-Diagnostics -Version $Version
      exit 0
    }

    if ($Target -eq 'Clean') {
      Invoke-Clean -Version $Version
      exit 0
    }

    Ensure-Platforms
    Restore-Packages

    if ($Target -eq 'Analyze') {
      Invoke-Analyze
      exit 0
    }

    if ($Target -eq 'Test') {
      Invoke-Tests
      exit 0
    }

    if (-not $SkipChecks) {
      Invoke-Checks
    } else {
      Write-Host 'Analyze and tests were skipped by -SkipChecks.' -ForegroundColor Yellow
    }

    # Platform builders replace only their own artifact. A forced Android
    # rebuild must not delete an already completed Windows or Web release.
    $ResetRelease = $false
    $ReleaseDirectory = Ensure-ReleaseDirectory -Version $Version -Reset:$ResetRelease
    $script:CurrentReleaseDirectory = $ReleaseDirectory

    switch ($Target) {
      'All' {
        Build-Windows -Version $Version -ReleaseDirectory $ReleaseDirectory
        Build-Web -Version $Version -ReleaseDirectory $ReleaseDirectory
        Build-Android -Version $Version -ReleaseDirectory $ReleaseDirectory
      }
      'Windows' {
        Build-Windows -Version $Version -ReleaseDirectory $ReleaseDirectory
      }
      'Web' {
        Build-Web -Version $Version -ReleaseDirectory $ReleaseDirectory
      }
      'Android' {
        Build-Android -Version $Version -ReleaseDirectory $ReleaseDirectory
      }
    }

    Show-ReleaseFiles -ReleaseDirectory $ReleaseDirectory
    Write-Host "`nBUILD SUCCESS" -ForegroundColor Green
    Write-Host "Output: $ReleaseDirectory" -ForegroundColor Green
  } finally {
    Pop-Location
  }
} catch {
  Write-Host "`nBUILD FAILED" -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red
  if ($_.ScriptStackTrace) {
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
  }

  if ($null -ne $script:CurrentReleaseDirectory -and (Test-Path -LiteralPath $script:CurrentReleaseDirectory -PathType Container)) {
    $Completed = @(Get-ChildItem -LiteralPath $script:CurrentReleaseDirectory -File -ErrorAction SilentlyContinue)
    if ($Completed.Count -gt 0) {
      Write-Host "`nCompleted artifacts were preserved:" -ForegroundColor Yellow
      foreach ($Item in ($Completed | Sort-Object Name)) {
        Write-Host ("  {0} ({1})" -f $Item.FullName, (Format-ByteSize $Item.Length)) -ForegroundColor Green
      }
      Write-Host 'A repeated build_all.bat run will skip these artifacts unless -ForceRebuild is supplied.' -ForegroundColor DarkGray
    }
  }
  exit 1
} finally {
  if ($TranscriptStarted) {
    try { Stop-Transcript | Out-Null } catch { }
  }
}
