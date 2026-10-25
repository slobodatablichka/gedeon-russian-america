# Catalog a public Yandex Disk folder recursively without downloading file contents.
# Requires curl.exe; bypasses Happ by binding curl to a selected local interface.
$ErrorActionPreference = 'Stop'
$PublicUrl = 'https://disk.yandex.ru/d/wgQU-ef5jouKZw'
$InterfaceIP = '192.168.0.108' # Verified Wi-Fi IP; adjust if DHCP changes.
$Output = Join-Path $PSScriptRoot '..\research\yandex-disk-files.json'
$Api = 'https://cloud-api.yandex.net/v1/disk/public/resources'
$Limit = 100
$folders = New-Object 'System.Collections.Generic.Queue[string]'
$folders.Enqueue('')
$visited = New-Object 'System.Collections.Generic.HashSet[string]'
$items = New-Object 'System.Collections.Generic.List[object]'
$folderCount = 0
$fileCount = 0
while ($folders.Count -gt 0) {
    $folderPath = $folders.Dequeue()
    if (-not $visited.Add($folderPath)) { continue }
    $offset = 0
    do {
        $uri = $Api + '?public_key=' + [uri]::EscapeDataString($PublicUrl) +
            '&path=' + [uri]::EscapeDataString($folderPath) +
            '&limit=' + $Limit + '&offset=' + $offset
        $json = & curl.exe --interface $InterfaceIP --silent --show-error --fail --connect-timeout 10 --max-time 45 $uri
        if ($LASTEXITCODE -ne 0) { throw "Yandex request failed at path '$folderPath' (curl $LASTEXITCODE)." }
        $response = ($json -join "`n") | ConvertFrom-Json
        if ($response.type -ne 'dir') { throw "Not a directory: '$folderPath'" }
        $page = @($response._embedded.items)
        foreach ($entry in $page) {
            $items.Add([ordered]@{
                name = $entry.name
                path = $entry.path
                type = $entry.type
                size = $entry.size
                modified = $entry.modified
            })
            if ($entry.type -eq 'dir') {
                $folderCount++
                $folders.Enqueue([string]$entry.path)
            } else {
                $fileCount++
            }
        }
        $offset += $page.Count
    } while ($page.Count -eq $Limit)
    Write-Host "Folders checked: $($visited.Count); files: $fileCount"
}
$result = [ordered]@{ source = $PublicUrl; folders = $folderCount; files = $fileCount; items = @($items.ToArray()) }
# Explicit UTF-8 to avoid Cyrillic corruption in JSON on Windows PowerShell 5.1.
$jsonOut = $result | ConvertTo-Json -Depth 12
[IO.File]::WriteAllText($Output, $jsonOut, (New-Object Text.UTF8Encoding($false)))
Write-Host "Complete. Folders: $folderCount; Files: $fileCount"
Write-Host "Catalog: $Output"
