# Fetch two selected public Yandex Disk DOCX files into the Git repository.
# Works around Happ routing by binding curl.exe to the verified Wi-Fi IP.
$ErrorActionPreference = 'Stop'
$PublicUrl = 'https://disk.yandex.ru/d/wgQU-ef5jouKZw'
$InterfaceIP = '192.168.0.108'
$Target = Join-Path $PSScriptRoot '..\research\originals'
$Api = 'https://cloud-api.yandex.net/v1/disk/public/resources'
$Names = @(
  'ЗАПИСКИ ИЕРОМОНАХА ГЕДЕОНА О КРУГОСВЕТНОМ ПУТЕШЕСТВИИ И РУССКОЙ АМЕРИКЕ.docx',
  'Записки иеромонаха Гедеона о кругосветном путешествии.docx'
)
New-Item -ItemType Directory -Force -Path $Target | Out-Null
function Request-Json([string]$Url) {
    $tmp = [IO.Path]::GetTempFileName()
    try {
        & curl.exe --interface $InterfaceIP --silent --show-error --fail --location --connect-timeout 10 --max-time 60 -o $tmp $Url
        if ($LASTEXITCODE -ne 0) { throw "API request failed (curl $LASTEXITCODE)." }
        return ([IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8) | ConvertFrom-Json)
    } finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
}
foreach ($name in $Names) {
    $query = 'public_key=' + [uri]::EscapeDataString($PublicUrl) + '&path=' + [uri]::EscapeDataString('/' + $name)
    $metadata = Request-Json ($Api + '?' + $query)
    if ($metadata.type -ne 'file') { throw "Not a file: $name" }
    if ($metadata.size -gt 1000000) { throw "Safety limit (1 MB) exceeded: $name" }
    $download = Request-Json ($Api + '/download?' + $query)
    if (-not $download.href) { throw "No download URL: $name" }
    $destination = Join-Path $Target $name
    & curl.exe --interface $InterfaceIP --silent --show-error --fail --location --connect-timeout 10 --max-time 120 -o $destination $download.href
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $name" }
    if ((Get-Item -LiteralPath $destination).Length -ne $metadata.size) { throw "Size mismatch: $name" }
    Write-Host "Downloaded: $name ($($metadata.size) bytes)"
}
Write-Host 'Files saved in research/originals/. Review them, then git add/commit/push.'
