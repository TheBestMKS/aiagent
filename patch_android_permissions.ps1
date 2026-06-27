param(
  [Parameter(Mandatory=$true)][string]$ManifestPath
)

$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $ManifestPath)) { exit 0 }

function Save-Utf8NoBom([string]$Path, [string]$Text) {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

$text = [System.IO.File]::ReadAllText($ManifestPath, [System.Text.Encoding]::UTF8)
# Repair a bad older patch that could have inserted literal PowerShell escape text.
$text = $text -replace '`r`n', [Environment]::NewLine
$text = $text -replace '`n', [Environment]::NewLine

$permissions = @(
  'android.permission.READ_EXTERNAL_STORAGE',
  'android.permission.WRITE_EXTERNAL_STORAGE',
  'android.permission.MANAGE_EXTERNAL_STORAGE',
  'android.permission.INTERNET',
  'android.permission.ACCESS_NETWORK_STATE',
  'android.permission.QUERY_ALL_PACKAGES'
)

# Ensure xmlns:android exists on <manifest>.
if ($text -notmatch 'xmlns:android=') {
  $text = [regex]::Replace($text, '<manifest\b', '<manifest xmlns:android="http://schemas.android.com/apk/res/android"', 1)
}

foreach ($perm in $permissions) {
  if ($text -notmatch [regex]::Escape($perm)) {
    $line = '    <uses-permission android:name="' + $perm + '" />'
    $text = [regex]::Replace($text, '(<manifest\b[^>]*>)', '$1' + [Environment]::NewLine + $line, 1)
  }
}


# Allow the built-in Web tab and local OpenAI-compatible endpoints to use HTTP on Android.
if ($text -notmatch 'usesCleartextTraffic') {
  $text = [regex]::Replace($text, '<application\b', '<application android:usesCleartextTraffic="true" android:hardwareAccelerated="true"', 1)
}


# Set visible Android app label.
if ($text -match '<application\b[^>]*android:label=') {
  $text = [regex]::Replace($text, 'android:label="[^"]*"', 'android:label="AI Agent"', 1)
} else {
  $text = [regex]::Replace($text, '<application\b', '<application android:label="AI Agent"', 1)
}

# Validate XML. If still invalid, report clear error and stop before Gradle.
try {
  [xml]$xml = $text
} catch {
  Save-Utf8NoBom -Path $ManifestPath -Text $text
  Write-Host "AndroidManifest.xml is still invalid after repair:" -ForegroundColor Red
  Write-Host $_.Exception.Message
  exit 1
}

Save-Utf8NoBom -Path $ManifestPath -Text $text
exit 0
