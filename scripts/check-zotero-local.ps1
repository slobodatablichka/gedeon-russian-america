# Zotero Desktop local API: read-only connectivity and project item-key export.
# No cloud API key, no writes to Zotero, no Git changes except local JSON output.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$base = 'http://127.0.0.1:23119/api/users/0'
$collectionKey = 'YWQFHUER'
$dest = Join-Path $root 'research\zotero\local-catalog.json'
function Get-Local([string]$endpoint) {
  $url = $base + $endpoint
  $tmp = [IO.Path]::GetTempFileName()
  try {
    & curl.exe --noproxy '*' --http1.1 --silent --show-error --fail --max-time 20 -H 'Zotero-API-Version: 3' --output $tmp $url
    if($LASTEXITCODE -ne 0){throw "curl exit code $LASTEXITCODE for $endpoint"}
    $json=[IO.File]::ReadAllText($tmp,[Text.Encoding]::UTF8)
    if([string]::IsNullOrWhiteSpace($json)){return @()}
    return ($json|ConvertFrom-Json)
  } finally {Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue}
}
function Get-All([string]$endpoint) {
  $out = @()
  for($start=0;$start -lt 10000;$start+=100){
    $sep=if($endpoint.Contains('?')){'&'}else{'?'}
    $page=@(Get-Local ($endpoint+"$($sep)limit=100&start=$start"))
    $out+= $page
    if($page.Count -lt 100){break}
  }
  return $out
}
$collections = @(Get-All '/collections')
$matched = @($collections | Where-Object { $_.key -eq $collectionKey })
if($matched.Count -ne 1){throw "Expected collection key $collectionKey, found $($matched.Count)."}
$rootKey=[string]$matched[0].key
$collectionName=[string]$matched[0].data.name
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
