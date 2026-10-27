# Download and extract three biography DOCX from the existing Yandex catalog.
# Compatible with Windows PowerShell 5.1. Original files are preserved.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$catalogPath=Join-Path $root 'research\yandex-disk-files.json'
if(!(Test-Path -LiteralPath $catalogPath)){ throw 'Run scripts\list-yandex-public.ps1 first.' }
$catalog=[IO.File]::ReadAllText($catalogPath,[Text.Encoding]::UTF8)|ConvertFrom-Json
$names=@(
  [string]::Concat([char]0x0418,[char]0x0435,[char]0x0440,[char]0x043E,[char]0x043C,[char]0x043E,[char]0x043D,[char]0x0430,[char]0x0445,' ',[char]0x0413,[char]0x0435,[char]0x0434,[char]0x0435,[char]0x043E,[char]0x043D,'.docx'),
  [string]::Concat([char]0x0418,[char]0x0435,[char]0x0440,[char]0x043E,[char]0x043C,[char]0x043E,[char]0x043D,[char]0x0430,[char]0x0445,' ',[char]0x0413,[char]0x0435,[char]0x0434,[char]0x0435,[char]0x043E,[char]0x043D,' ',[char]0x0441,[char]0x0442,[char]0x0430,[char]0x0442,[char]0x044C,[char]0x044F,'.docx'),
  [string]::Concat([char]0x041E,' ',[char]0x0413,[char]0x0435,[char]0x0434,[char]0x0435,[char]0x043E,[char]0x043D,[char]0x0435,'.docx')
)
$sourceDir=Join-Path $root 'research\originals'
$outDir=Join-Path $root 'research\transcriptions'
New-Item -ItemType Directory -Force -Path $sourceDir,$outDir|Out-Null
$public='https://disk.yandex.ru/d/wgQU-ef5jouKZw'
$api='https://cloud-api.yandex.net/v1/disk/public/resources/download'
# The verified Wi-Fi address avoids Happ; adjust if DHCP changed.
$interfaceIP='192.168.0.108'
for($i=0;$i -lt $names.Count;$i++){
  $name=$names[$i]
  $item=@($catalog.items|Where-Object{$_.type -eq 'file' -and $_.name -ceq $name})
  if($item.Count -ne 1){throw "Not found uniquely in catalog: $name"}
  if($item[0].size -gt 15000000){throw "Unexpectedly large DOCX: $name"}
  $dest=Join-Path $sourceDir $name
  if(!(Test-Path -LiteralPath $dest) -or (Get-Item -LiteralPath $dest).Length -ne $item[0].size){
    $query='public_key='+[uri]::EscapeDataString($public)+'&path='+[uri]::EscapeDataString([string]$item[0].path)
    $tmp=[IO.Path]::GetTempFileName()
    try{
      & curl.exe --interface $interfaceIP --silent --show-error --fail --location --connect-timeout 20 --max-time 60 -o $tmp ($api+'?'+$query)
      if($LASTEXITCODE -ne 0){throw "Yandex metadata download failed for $name"}
      $meta=[IO.File]::ReadAllText($tmp,[Text.Encoding]::UTF8)|ConvertFrom-Json
      if(!$meta.href){throw "No download URL for $name"}
    }finally{Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue}
    & curl.exe --interface $interfaceIP --silent --show-error --fail --location --connect-timeout 20 --max-time 180 -o $dest $meta.href
    if($LASTEXITCODE -ne 0){throw "Yandex file download failed for $name"}
  }
  if((Get-Item -LiteralPath $dest).Length -ne $item[0].size){throw "Size mismatch for $name"}
  $zip=[IO.Compression.ZipFile]::OpenRead($dest)
  try{
    $entry=$zip.GetEntry('word/document.xml')
    if($null -eq $entry){throw "No document.xml in $name"}
    $sr=New-Object IO.StreamReader($entry.Open(),[Text.Encoding]::UTF8)
    try{$xmlText=$sr.ReadToEnd()}finally{$sr.Dispose()}
    [xml]$xml=$xmlText
    $ns=New-Object Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('w','http://schemas.openxmlformats.org/wordprocessingml/2006/main')
    $lines=@(foreach($p in $xml.SelectNodes('//w:body//w:p',$ns)){
      ($p.SelectNodes('.//w:t',$ns)|ForEach-Object{$_.InnerText}) -join ''
    })
    $output=Join-Path $outDir ('bio-docx-{0}.txt' -f ($i+1))
    $header="# Source: $name`r`n# Extracted body only; footnotes, headers, graphics not included.`r`n`r`n"
    [IO.File]::WriteAllText($output,$header+($lines -join "`r`n"),(New-Object Text.UTF8Encoding($false)))
    Write-Host ('OK bio-docx-{0}.txt; paragraphs={1}' -f ($i+1),$lines.Count)
  }finally{$zip.Dispose()}
}
Write-Host 'Ready: research\transcriptions\bio-docx-1.txt .. bio-docx-3.txt'
