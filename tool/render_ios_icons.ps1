# Rasterize the existing Veexor vector branding for the iOS asset catalog.
Add-Type -AssemblyName PresentationCore, WindowsBase
$taskRoot = Split-Path -Parent $PSScriptRoot
$catalog = Join-Path $taskRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
[xml]$vector = Get-Content -LiteralPath (Join-Path $taskRoot 'assets/veexor-icon.svg')
$entries = (Get-Content -LiteralPath (Join-Path $catalog 'Contents.json') -Raw | ConvertFrom-Json).images
foreach ($entry in $entries) {
    $pixels = [int]([double]($entry.size.Split('x')[0]) * [double]($entry.scale.TrimEnd('x')))
    $visual = New-Object System.Windows.Media.DrawingVisual
    $drawing = $visual.RenderOpen()
    $drawing.PushTransform((New-Object System.Windows.Media.ScaleTransform ($pixels / 108), ($pixels / 108)))
    $greenBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#1C7360'))
    $drawing.DrawRectangle($greenBrush, $null, (New-Object System.Windows.Rect 0,0,108,108))
    foreach ($path in $vector.svg.path) {
        $brush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($path.fill))
        $drawing.DrawGeometry($brush, $null, [System.Windows.Media.Geometry]::Parse($path.d))
    }
    $drawing.Pop()
    $drawing.Close()
    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap $pixels,$pixels,96,96,([System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [System.IO.File]::Create((Join-Path $catalog $entry.filename))
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}
