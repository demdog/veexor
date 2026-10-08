param([string]$Destination)
$ErrorActionPreference = 'Stop'
$taskRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
if (-not $Destination) { $Destination = Join-Path (Split-Path -Parent $taskRoot) 'Veexor-Flutter.zip' }
Add-Type -AssemblyName System.IO.Compression
$topFiles = @('.gitattributes','.gitignore','.metadata','analysis_options.yaml','pubspec.yaml','pubspec.lock','README.md','VALIDATION.md')
$folders = @('lib','test','tool','assets','docs','android','ios')
$files = @($topFiles | ForEach-Object { Get-Item -LiteralPath (Join-Path $taskRoot $_) })
foreach ($folder in $folders) {
    $files += Get-ChildItem -LiteralPath (Join-Path $taskRoot $folder) -Recurse -File -Force
}
$stream = [System.IO.File]::Open($Destination, [System.IO.FileMode]::Create)
$archive = New-Object System.IO.Compression.ZipArchive $stream, ([System.IO.Compression.ZipArchiveMode]::Create), $false
try {
    foreach ($file in $files) {
        $relative = [System.IO.Path]::GetRelativePath($taskRoot, $file.FullName).Replace('\','/')
        if ($relative -match '(^|/)(build|\.gradle|\.dart_tool|\.idea|\.cxx|\.swiftpm|Pods|\.symlinks|xcuserdata|ephemeral|\.generated)/') { continue }
        if ($relative -match '(^|/)(local\.properties|key\.properties|GeneratedPluginRegistrant\.(java|h|m)|Generated\.xcconfig|flutter_export_environment\.sh|\.DS_Store)$') { continue }
        if ($relative -match '\.(jks|keystore|iml|log|lock\.pid)$') { continue }
        $entry = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, "VeexorFlutter/$relative", [System.IO.Compression.CompressionLevel]::Optimal)
        # Preserve a runnable Gradle script when extracting on macOS/Linux.
        if ($relative -eq 'android/gradlew') { $entry.ExternalAttributes = [int]0x81ED0000 }
    }
} finally {
    $archive.Dispose()
    $stream.Dispose()
}
Get-Item -LiteralPath $Destination | Select-Object FullName,Length
