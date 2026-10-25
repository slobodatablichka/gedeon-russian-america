# Read-only listing of a public Yandex Disk folder. No OAuth token required.
$ErrorActionPreference = 'Stop'
$PublicUrl = 'https://disk.yandex.ru/d/wgQU-ef5jouKZw'
$Output = Join-Path $PSScriptRoot '..\research\yandex-disk-files.json'
$api = 'https://cloud-api.yandex.net/v1/disk/public/resources'
$items = New-Object System.Collections.Generic.List[object]
$offset = 0
$limit = 100
do {
    $request = $api + '?public_key=' + [uri]::EscapeDataString($PublicUrl) + "&limit=$limit&offset=$offset"
    $response = Invoke-RestMethod -Method Get -Uri $request -Headers @{ Accept = 'application/json' }
    if ($response.type -ne 'dir') { throw 'Public link is not a directory.' }
    $page = @($response._embedded.items)
    foreach ($entry in $page) {
        $items.Add([ordered]@{
            name = $entry.name
            path = $entry.path
            type = $entry.type
            size = $entry.size
            modified = $entry.modified
        })
    }
    $offset += $page.Count
} while ($page.Count -eq $limit)
$result = [ordered]@{
    source = $PublicUrl
    folder = $response.name
    count = $items.Count
    items = @($items.ToArray())
}
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Output -Encoding UTF8
Write-Host "Folder: $($result.folder)"
Write-Host "Items: $($result.count)"
Write-Host "Catalog: $Output"
