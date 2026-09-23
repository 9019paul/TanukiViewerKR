param(
    [string]$Notes = 'Tanuki Viewer KR stable update'
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Version = Get-Content -Raw -LiteralPath (Join-Path $Root 'VERSION.json') | ConvertFrom-Json
$ListPath = Join-Path $Root 'config\update-files.txt'

if (-not (Test-Path -LiteralPath $ListPath -PathType Leaf)) {
    throw "Missing file list: config/update-files.txt"
}

$Files = Get-Content -LiteralPath $ListPath |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') } |
    Sort-Object -Unique

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
    notes = $Notes
    files = @($Entries)
}

$Manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Root 'update-manifest.json') -Encoding UTF8
Write-Host "update-manifest.json generated for v$($Version.version) with $($Entries.Count) cumulative update file(s)."
