$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ConfigPath = Join-Path $Root 'config\repository.json'
$VersionPath = Join-Path $Root 'VERSION.json'
$Config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
$RepoOwner = [string]$Config.owner
$RepoName = [string]$Config.repo
$Branch = [string]$Config.branch
$RawBase = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch"
$ManifestUrl = "$RawBase/update-manifest.json"

function Get-LocalVersion {
    try {
        $v = Get-Content -Raw -LiteralPath $VersionPath | ConvertFrom-Json
        return [string]$v.version
    } catch { return '0.0.0' }
}

function Convert-ToVersion([string]$Value) {
    try { return [version](($Value.Trim()) -replace '^[vV]','') } catch { return [version]'0.0.0' }
}

function Get-RemoteManifest {
    $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    return Invoke-RestMethod -Uri "${ManifestUrl}?ts=$stamp" -Headers @{ 'User-Agent' = 'TanukiViewerKR-Updater' } -UseBasicParsing
}

function Get-UpdateStatus {
    $local = Get-LocalVersion
    $manifest = Get-RemoteManifest
    $latest = [string]$manifest.version
    return [ordered]@{
        ok = $true
        localVersion = $local
        latestVersion = $latest
        updateAvailable = ((Convert-ToVersion $latest) -gt (Convert-ToVersion $local))
        notes = [string]$manifest.notes
    }
}

function Get-RemoteFileUrl([string]$Path) {
    $parts = $Path -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }
    return "$RawBase/$($parts -join '/')"
}

function Assert-SafeRelativePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Unsafe update path: $Path"
    }
}

function Apply-Update {
    $local = Get-LocalVersion
    $manifest = Get-RemoteManifest
    $latest = [string]$manifest.version
    if ((Convert-ToVersion $latest) -le (Convert-ToVersion $local)) {
        return [ordered]@{ ok=$true; updated=$false; localVersion=$local; latestVersion=$latest }
    }

    $pending = @()
    foreach ($entry in $manifest.files) {
        $rel = [string]$entry.path
        Assert-SafeRelativePath $rel
        $target = Join-Path $Root ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        $expected = ([string]$entry.sha256).ToLowerInvariant()
        $needsFile = -not (Test-Path -LiteralPath $target -PathType Leaf)
        if (-not $needsFile -and $expected) {
            $current = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()
            $needsFile = ($current -ne $expected)
        }
        if ($needsFile) { $pending += $entry }
    }
    $pending = @($pending | Sort-Object @{ Expression = { if ([string]$_.path -eq 'VERSION.json') { 1 } else { 0 } } })

    $tempRoot = Join-Path $Root ('.update-temp-' + [Guid]::NewGuid().ToString('N'))
    $backupRoot = Join-Path $Root ('.update-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $newFiles = New-Object System.Collections.Generic.List[string]
    $backedUp = New-Object System.Collections.Generic.List[string]

    try {
        foreach ($entry in $pending) {
            $rel = [string]$entry.path
            $tmp = Join-Path $tempRoot ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            $tmpDir = Split-Path -Parent $tmp
            if ($tmpDir) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
            Invoke-WebRequest -Uri (Get-RemoteFileUrl $rel) -OutFile $tmp -Headers @{ 'User-Agent' = 'TanukiViewerKR-Updater' } -UseBasicParsing
            $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $tmp).Hash.ToLowerInvariant()
            $expected = ([string]$entry.sha256).ToLowerInvariant()
            if ($expected -and $actual -ne $expected) { throw "SHA256 mismatch: $rel" }
        }

        foreach ($entry in $pending) {
            $rel = [string]$entry.path
            $target = Join-Path $Root ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            $tmp = Join-Path $tempRoot ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            $targetDir = Split-Path -Parent $target
            if ($targetDir) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
            if (Test-Path -LiteralPath $target) {
                $backup = Join-Path $backupRoot ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
                $backupDir = Split-Path -Parent $backup
                if ($backupDir) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
                Copy-Item -LiteralPath $target -Destination $backup -Force
                $backedUp.Add($rel)
            } else { $newFiles.Add($rel) }
            Copy-Item -LiteralPath $tmp -Destination $target -Force
        }

        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
        return [ordered]@{ ok=$true; updated=$true; version=$latest; files=$pending.Count }
    } catch {
        foreach ($rel in $backedUp) {
            $backup = Join-Path $backupRoot ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            $target = Join-Path $Root ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            if (Test-Path -LiteralPath $backup) { Copy-Item -LiteralPath $backup -Destination $target -Force }
        }
        foreach ($rel in $newFiles) {
            $target = Join-Path $Root ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Get-ContentType([string]$Path) {
    switch ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.html' { 'text/html; charset=utf-8' }
        '.css'  { 'text/css; charset=utf-8' }
        '.js'   { 'application/javascript; charset=utf-8' }
        '.json' { 'application/json; charset=utf-8' }
        '.png'  { 'image/png' }
        '.gif'  { 'image/gif' }
        '.webp' { 'image/webp' }
        '.svg'  { 'image/svg+xml' }
        '.txt'  { 'text/plain; charset=utf-8' }
        default { 'application/octet-stream' }
    }
}

function Send-Response($Stream, [int]$StatusCode, [string]$StatusText, [byte[]]$Body, [string]$ContentType) {
    $header = "HTTP/1.1 $StatusCode $StatusText`r`nContent-Type: $ContentType`r`nContent-Length: $($Body.Length)`r`nCache-Control: no-store, no-cache, must-revalidate`r`nPragma: no-cache`r`nAccess-Control-Allow-Origin: *`r`nConnection: close`r`n`r`n"
    $headerBytes = [Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes,0,$headerBytes.Length)
    if ($Body.Length -gt 0) { $Stream.Write($Body,0,$Body.Length) }
    $Stream.Flush()
}

function Send-Json($Stream, [int]$StatusCode, $Object) {
    $json = $Object | ConvertTo-Json -Compress -Depth 8
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $text = if ($StatusCode -eq 200) { 'OK' } else { 'Error' }
    Send-Response $Stream $StatusCode $text $bytes 'application/json; charset=utf-8'
}

$Listener = $null
$Port = 43119
foreach ($candidate in 43119..43123) {
    try {
        $Listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$candidate)
        $Listener.Start()
        $Port = $candidate
        break
    } catch { $Listener = $null }
}
if (-not $Listener) { exit 1 }

$Url = "http://127.0.0.1:$Port/"
Start-Process $Url
$LastRequest = Get-Date

try {
    while ($true) {
        if (-not $Listener.Pending()) {
            Start-Sleep -Milliseconds 100
            if (((Get-Date) - $LastRequest).TotalSeconds -gt 150) { break }
            continue
        }
        $Client = $Listener.AcceptTcpClient()
        $LastRequest = Get-Date
        try {
            $Stream = $Client.GetStream()
            $Reader = New-Object IO.StreamReader($Stream,[Text.Encoding]::ASCII,$false,4096,$true)
            $RequestLine = $Reader.ReadLine()
            if (-not $RequestLine) { continue }
            $parts = $RequestLine.Split(' ')
            $method = $parts[0]
            $rawTarget = if ($parts.Length -gt 1) { $parts[1] } else { '/' }
            while (($line = $Reader.ReadLine()) -ne $null -and $line -ne '') { }
            $target = ($rawTarget -split '\?')[0]

            if ($target -eq '/api/ping') {
                Send-Json $Stream 200 @{ ok=$true; app='TanukiViewerKR' }
                continue
            }
            if ($target -eq '/api/status') {
                try { Send-Json $Stream 200 (Get-UpdateStatus) }
                catch { Send-Json $Stream 503 @{ ok=$false; error=$_.Exception.Message; localVersion=(Get-LocalVersion) } }
                continue
            }
            if ($target -eq '/api/update' -and $method -eq 'POST') {
                try { Send-Json $Stream 200 (Apply-Update) }
                catch { Send-Json $Stream 500 @{ ok=$false; error=$_.Exception.Message } }
                continue
            }

            $decoded = [Uri]::UnescapeDataString($target).TrimStart('/')
            if ([string]::IsNullOrWhiteSpace($decoded)) { $decoded = 'index.html' }
            Assert-SafeRelativePath $decoded
            $candidatePath = Join-Path $Root ($decoded -replace '/', [IO.Path]::DirectorySeparatorChar)
            $full = [IO.Path]::GetFullPath($candidatePath)
            if (-not $full.StartsWith($Root,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
                Send-Response $Stream 404 'Not Found' ([Text.Encoding]::UTF8.GetBytes('Not Found')) 'text/plain; charset=utf-8'
                continue
            }
            $bytes = [IO.File]::ReadAllBytes($full)
            Send-Response $Stream 200 'OK' $bytes (Get-ContentType $full)
        } catch {
            try { Send-Json $Stream 500 @{ ok=$false; error=$_.Exception.Message } } catch {}
        } finally {
            if ($Reader) { $Reader.Dispose() }
            if ($Stream) { $Stream.Dispose() }
            $Client.Close()
        }
    }
} finally {
    $Listener.Stop()
}
