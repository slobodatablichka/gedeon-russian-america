$ErrorActionPreference = 'Stop'

$RootCollectionName = 'Гедеон — Русская Америка'
$OutputPath = Join-Path $PSScriptRoot '..\research\zotero\catalog.json'

if ([string]::IsNullOrWhiteSpace($env:ZOTERO_API_KEY)) {
    throw 'ZOTERO_API_KEY не задан в текущем окне PowerShell.'
}

Add-Type -AssemblyName System.Net.Http

$client = New-Object System.Net.Http.HttpClient
$client.DefaultRequestHeaders.Add('Zotero-API-Key', $env:ZOTERO_API_KEY)
$client.DefaultRequestHeaders.Add('Zotero-API-Version', '3')

function Get-ZoteroJson([string]$Uri) {
    $response = $client.GetAsync($Uri).Result

    if (-not $response.IsSuccessStatusCode) {
        $body = $response.Content.ReadAsStringAsync().Result
        throw "Zotero API error $([int]$response.StatusCode): $body"
    }

    $bytes = $response.Content.ReadAsByteArrayAsync().Result
    $json  = [System.Text.Encoding]::UTF8.GetString($bytes)

    if ([string]::IsNullOrWhiteSpace($json)) {
        return $null
    }

    return ($json | ConvertFrom-Json)
}

function Get-ZoteroPaged([string]$BaseUri) {
    $all = @()
    $start = 0
    $limit = 100

    while ($true) {
        $separator = if ($BaseUri.Contains('?')) { '&' } else { '?' }
        $uri = "${BaseUri}${separator}limit=$limit&start=$start"

        $page = @(Get-ZoteroJson $uri)

        if ($page.Count -eq 0) {
            break
        }

        $all += $page

        if ($page.Count -lt $limit) {
            break
        }

        $start += $limit
    }

    return $all
}

# Проверка ключа и userID
$keyInfo = Get-ZoteroJson 'https://api.zotero.org/keys/current'
$userID = $keyInfo.userID

# Все коллекции нужны временно только для построения дерева
$allCollections = @(
    Get-ZoteroPaged "https://api.zotero.org/users/$userID/collections"
)

$rootMatches = @(
    $allCollections |
    Where-Object { $_.data.name -eq $RootCollectionName }
)

if ($rootMatches.Count -ne 1) {
    throw "Ожидалась ровно одна коллекция '$RootCollectionName'. Найдено: $($rootMatches.Count)"
}

$root = $rootMatches[0]
$rootKey = $root.key

# Выбираем корневую коллекцию Гедеона и её дочерние коллекции
$allowedKeys = New-Object System.Collections.Generic.HashSet[string]
[void]$allowedKeys.Add($rootKey)

$changed = $true

while ($changed) {
    $changed = $false

    foreach ($collection in $allCollections) {
        $parent = $collection.data.parentCollection

        if (
            $parent -and
            $allowedKeys.Contains([string]$parent) -and
            -not $allowedKeys.Contains([string]$collection.key)
        ) {
            [void]$allowedKeys.Add([string]$collection.key)
            $changed = $true
        }
    }
}

$projectCollections = @(
    $allCollections |
    Where-Object { $allowedKeys.Contains([string]$_.key) }
)

# Получаем записи из корня и всех вложенных коллекций, без повторов.
$byKey = @{}
foreach ($collectionKey in $allowedKeys) {
    $itemsInCollection = @(Get-ZoteroPaged "https://api.zotero.org/users/$userID/collections/$collectionKey/items/top")
    foreach ($entry in $itemsInCollection) {
        if ($entry.data.itemType -notin @('attachment','note','annotation')) {
            $byKey[$entry.key] = $entry
        }
    }
}
$sourceItems = @($byKey.Values)
$exportItems = @()

foreach ($item in $sourceItems) {

    # citationKey берется напрямую из данных Zotero Web API.
    # Связь с Zotero item key тем самым не зависит от совпадения заглавий.
    $citationKey = $item.data.citationKey

    # Не выгружаем содержимое заметок, вложения и личные поля в публичный GitHub.
    # Скан и PDF остаются в Zotero или отдельном хранилище.
    $attachments = @()
    $notes = @()

    # Защита от случайного попадания посторонней коллекции
    $itemCollections = @(
        $item.data.collections |
        Where-Object { $allowedKeys.Contains([string]$_) }
    )

    $exportItems += [ordered]@{
        key         = $item.key
        version     = $item.version
        citationKey = $citationKey
        itemType    = $item.data.itemType
        title       = $item.data.title

        tags = @(
            $item.data.tags |
            ForEach-Object { $_.tag }
        )

        collections = $itemCollections
        zoteroURL   = "https://www.zotero.org/users/$userID/items/$($item.key)"
        notesCount  = 0
        attachmentsCount = 0
    }
}

# STABLE-EXPORT-NORMALIZATION
foreach ($entry in $exportItems) {

    $entry['tags'] = @(
        $entry['tags'] |
        Sort-Object
    )

    $entry['collections'] = @(
        $entry['collections'] |
        Sort-Object
    )

    $entry['notes'] = @(
        $entry['notes'] |
        Sort-Object key
    )

    $entry['attachments'] = @(
        $entry['attachments'] |
        Sort-Object key
    )

}

$exportItems = @(
    $exportItems |
    Sort-Object { $_['key'] }
)

$exportCollections = @(
    $projectCollections |
    ForEach-Object {
        [ordered]@{
            key              = $_.key
            name             = $_.data.name
            parentCollection = $_.data.parentCollection
            version          = $_.version
        }
    }
)

# STABLE-COLLECTION-SORT
$exportCollections = @(
    $exportCollections |
    Sort-Object { $_['name'] }, { $_['key'] }
)

$result = [ordered]@{
    schemaVersion = 1

    rootCollection = [ordered]@{
        key  = $rootKey
        name = $RootCollectionName
    }

    collections = $exportCollections
    items       = $exportItems
}

$json = $result | ConvertTo-Json -Depth 50

[System.IO.File]::WriteAllText(
    $OutputPath,
    $json,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host 'Zotero research export complete.'
Write-Host "Root:        $RootCollectionName"
Write-Host "Collections: $($exportCollections.Count)"
Write-Host "Items:       $($exportItems.Count)"
Write-Host "Output:      $OutputPath"