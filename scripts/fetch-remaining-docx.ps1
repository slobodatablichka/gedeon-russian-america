# Collect the remaining small DOCX files from the previously catalogued public folder.
# Windows PowerShell 5.1; keep originals and extracted texts LOCAL until reviewed.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$catalogPath=Join-Path $root 'research\yandex-disk-files.json'
if(!(Test-Path -LiteralPath $catalogPath)){throw 'Run scripts\list-yandex-public.ps1 first'}
$catalog=[IO.File]::ReadAllText($catalogPath,[Text.Encoding]::UTF8)|ConvertFrom-Json
$sourceDir=Join-Path $root 'research\originals'
$outDir=Join-Path $root 'research\transcriptions\additional'
New-Item -ItemType Directory -Force -Path $sourceDir,$outDir|Out-Null
$api='https://cloud-api.yandex.net/v1/disk/public/resources/download'
$public='https://disk.yandex.ru/d/wgQU-ef5jouKZw'
$wifi='192.168.0.108'
$items=@($catalog.items|Where-Object{$_.type -eq 'file' -and $_.name -match '(?i)\.docx$'}|Sort-Object name)
$downloaded=0
foreach($item in $items){
 $dest=Join-Path $sourceDir ([string]$item.name)
 if(Test-Path -LiteralPath $dest){continue}
 if($item.size -gt 15000000){throw 'DOCX size above 15 MB limit'}
 $q='public_key='+[uri]::EscapeDataString($public)+'&path='+[uri]::EscapeDataString([string]$item.path)
 $tmp=[IO.Path]::GetTempFileName()
 try {
  & curl.exe --noproxy '*' --interface $wifi --silent --show-error --fail --location --connect-timeout 20 --max-time 60 -o $tmp ($api+'?'+$q)
  if($LASTEXITCODE -ne 0){throw 'Metadata download failed'}
  $meta=[IO.File]::ReadAllText($tmp,[Text.Encoding]::UTF8)|ConvertFrom-Json
  if(!$meta.href){throw 'Missing download link'}
 } finally {Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue}
 & curl.exe --noproxy '*' --interface $wifi --silent --show-error --fail --location --connect-timeout 20 --max-time 180 -o $dest $meta.href
 if($LASTEXITCODE -ne 0){throw 'File download failed'}
 if((Get-Item -LiteralPath $dest).Length -ne $item.size){throw 'File size mismatch'}
 $downloaded++
 Write-Host "Downloaded: $($item.name)"
}
# Extract all DOCX whose text was not already processed by earlier scripts.
$already=@{}
foreach($old in @('gedeon-docx-1.txt','gedeon-docx-2.txt','bio-docx-1.txt','bio-docx-2.txt','bio-docx-3.txt')){
 $path=Join-Path (Join-Path $root 'research\transcriptions') $old
 if(Test-Path -LiteralPath $path){
  $line=Get-Content -LiteralPath $path -TotalCount 1 -Encoding UTF8
  if($line -match '^# Source: (.+)$'){$already[$Matches[1]]=$true}
 }
}
$files=@(Get-ChildItem -LiteralPath $sourceDir -Filter '*.docx' -File|Where-Object{!$already.ContainsKey($_.Name)}|Sort-Object Name)
$index=0
foreach($file in $files){
 $index++
 $zip=[IO.Compression.ZipFile]::OpenRead($file.FullName)
 try{
  $entry=$zip.GetEntry('word/document.xml')
  if(!$entry){throw 'Missing document.xml'}
  $sr=New-Object IO.StreamReader($entry.Open(),[Text.Encoding]::UTF8)
  try{$xmlText=$sr.ReadToEnd()}finally{$sr.Dispose()}
  [xml]$xml=$xmlText
  $ns=New-Object Xml.XmlNamespaceManager($xml.NameTable)
  $ns.AddNamespace('w','http://schemas.openxmlformats.org/wordprocessingml/2006/main')
  $lines=@(foreach($p in $xml.SelectNodes('//w:body//w:p',$ns)){($p.SelectNodes('.//w:t',$ns)|ForEach-Object{$_.InnerText}) -join ''})
  $output=Join-Path $outDir ('additional-docx-{0:D2}.txt' -f $index)
  $header="# Source: $($file.Name)`r`n# Body only; no notes or layout.`r`n`r`n"
  [IO.File]::WriteAllText($output,$header+($lines -join "`r`n"),(New-Object Text.UTF8Encoding($false)))
  Write-Host "EXTRACTED: $($file.Name) -> $([IO.Path]::GetFileName($output)) ; paragraphs=$($lines.Count)"
 } finally {$zip.Dispose()}
}
Write-Host "DONE: new downloads=$downloaded, new extracts=$index"
Write-Host 'Texts remain local under research\transcriptions\additional; review before sharing or committing.'
