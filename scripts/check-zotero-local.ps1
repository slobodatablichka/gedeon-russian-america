# Zotero Desktop local API: read-only connectivity and project item-key export.
# No cloud API key, no writes to Zotero, no Git changes except local JSON output.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$base = 'http://127.0.0.1:23119/api/users/0'
$collectionName = 'Гедеон — Русская Америка'
$dest = Join-Path $root 'research\zotero\local-catalog.json'
function Get-Local([string]$endpoint) {
  $url = $base + $endpoint
  try { return Invoke-RestMethod -Method Get -Uri $url -TimeoutSec 12 -Proxy $null -Headers @{'Zotero-API-Version'='3'} }
  catch { throw "Zotero Desktop local API unavailable for $endpoint. Check Zotero Settings > Advanced > Allow other applications on this computer to communicate with Zotero. Details: $($_.Exception.Message)" }
}
function Get-All([string]$endpoint) {
  $out = @()
  for($start=0;$start -lt 10000;$start+=100){
    $sep=if($endpoint.Contains('?')){'&'}else{'?'}
    $page=@(Get-Local ($endpoint+"$($sep)limit=100&start=$start"))
    $out+= $page
    if($page.Count -lt 100){break}
  }
  return ,$out
}
$collections = @(Get-All '/collections')
$matched = @($collections | Where-Object { $_.data.name -eq $collectionName })
if($matched.Count -ne 1){throw "Expected one collection '$collectionName', found $($matched.Count)."}
$rootKey=[string]$matched[0].key
$allowed=New-Object 'System.Collections.Generic.HashSet[string]'
[void]$allowed.Add($rootKey)
do {
  $change=$false
  foreach($c in $collections){
    if($c.data.parentCollection -and $allowed.Contains([string]$c.data.parentCollection) -and $allowed.Add([string]$c.key)){$change=$true}
  }
} while($change)
$byKey=@{}
foreach($key in $allowed){
  foreach($item in @(Get-All ("/collections/$key/items/top"))){
    if($item.data.itemType -notin @('attachment','note','annotation')){$byKey[[string]$item.key]=$item}
  }
}
$entries=@($byKey.Values | Sort-Object key | ForEach-Object {
  [ordered]@{ key=$_.key; title=$_.data.title; itemType=$_.data.itemType; collections=@($_.data.collections) }
})
$result=[ordered]@{rootCollection=[ordered]@{name=$collectionName;key=$rootKey};itemCount=$entries.Count;items=$entries}
[IO.File]::WriteAllText($dest,($result|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
Write-Host "OK Zotero Desktop local API; collection=$rootKey; items=$($entries.Count)"
Write-Host "Output: $dest"
