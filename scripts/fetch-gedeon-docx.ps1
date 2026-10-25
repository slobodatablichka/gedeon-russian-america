# ASCII-only PowerShell 5.1 compatible file: reads exact UTF-8 filenames from JSON catalog.
$ErrorActionPreference = 'Stop'
$PublicUrl = 'https://disk.yandex.ru/d/wgQU-ef5jouKZw'
$InterfaceIP = '192.168.0.108'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Catalog = Join-Path $Root 'research\yandex-disk-files.json'
$Target = Join-Path $Root 'research\originals'
$Api = 'https://cloud-api.yandex.net/v1/disk/public/resources'
if (-not (Test-Path -LiteralPath $Catalog)) { throw 'Catalog missing. Run list-yandex-public.ps1 first.' }
$catalogObj = [IO.File]::ReadAllText($Catalog, [Text.Encoding]::UTF8) | ConvertFrom-Json
$targets = @(
    $catalogObj.items | Where-Object {
        $_.type -eq 'file' -and $_.name -match '(?i)\.docx$' -and
        ($_.name -match '(?i)^\u0417\u0410\u041f\u0418\u0421\u041a\u0418\s' -or $_.name -match '(?i)^\u0417\u0430\u043f\u0438\u0441\u043a\u0438\s')
    }
)
if ($targets.Count -ne 2) { throw "Expected 2 notes DOCX files; found $($targets.Count). No files downloaded." }
New-Item -ItemType Directory -Force -Path $Target | Out-Null
function Curl-ToFile([string]$Url, [string]$Destination) {
    & curl.exe --interface $InterfaceIP --silent --show-error --fail --location --retry 4 --retry-all-errors --retry-delay 3 --connect-timeout 20 --max-time 180 -o $Destination $Url
    if ($LASTEXITCODE -ne 0) { throw "curl failed: $LASTEXITCODE" }
}
foreach ($item in $targets) {
    if ($item.size -gt 1000000) { throw 'File exceeds 1 MB safety limit.' }
    $dest = Join-Path $Target $item.name
    if ((Test-Path -LiteralPath $dest) -and (Get-Item -LiteralPath $dest).Length -eq $item.size) {
        Write-Host "Already downloaded: $($item.name)"
        continue
    }
    $query = 'public_key=' + [uri]::EscapeDataString($PublicUrl) + '&path=' + [uri]::EscapeDataString([string]$item.path)
    $tmp = [IO.Path]::GetTempFileName()
    try {
        Curl-ToFile ($Api + '/download?' + $query) $tmp
        $meta = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8) | ConvertFrom-Json
    } finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    if (-not $meta.href) { throw 'API returned no download URL.' }
    Curl-ToFile $meta.href $dest
    if ((Get-Item -LiteralPath $dest).Length -ne $item.size) { throw 'Downloaded size mismatch.' }
    Write-Host "OK: $($item.name) ($($item.size) bytes)"
}
Write-Host 'Two DOCX source files are ready in research/originals.'
