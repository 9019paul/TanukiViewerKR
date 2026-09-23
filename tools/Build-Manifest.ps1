$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Version = Get-Content -Raw -LiteralPath (Join-Path $Root 'VERSION.json') | ConvertFrom-Json

$Files = @(
    'index.html',
    'css/style.css',
    'js/app.js',
    'js/parser.js',
    'js/catalog.js',
    'assets/ui/tanuki-icon.png',
    'assets/ui/tanuki-loader.gif',
    'VERSION.json',
    'README.txt',
    'launcher/server.ps1',
    'START_Tanuki_Viewer.bat',
    'config/repository.json'
)

$Entries = foreach ($rel in $Files) {
    $path = Join-Path $Root ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $rel" }
    $item = Get-Item -LiteralPath $path
    [ordered]@{
        path = $rel
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        size = $item.Length
    }
}

$Manifest = [ordered]@{
    schema = 'tanuki-viewer-update/v1'
    version = [string]$Version.version
    publishedAt = (Get-Date).ToUniversalTime().ToString('o')
    notes = 'Tanuki Viewer KR stable update'
    files = $Entries
}
$Manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Root 'update-manifest.json') -Encoding UTF8
Write-Host "update-manifest.json generated for v$($Version.version)"
