# Extract DOCX paragraph text locally for comparison, without modifying sources.
# ASCII-only for Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sourceDir = Join-Path $root 'research\originals'
$outDir = Join-Path $root 'research\transcriptions'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$files = @(Get-ChildItem -LiteralPath $sourceDir -Filter '*.docx' -File | Sort-Object Name)
if ($files.Count -ne 2) { throw "Expected exactly 2 DOCX files; found $($files.Count)." }
for ($i = 0; $i -lt $files.Count; $i++) {
    $zip = [IO.Compression.ZipFile]::OpenRead($files[$i].FullName)
    try {
        $entry = $zip.GetEntry('word/document.xml')
        if ($null -eq $entry) { throw 'DOCX main document XML missing.' }
        $stream = $entry.Open()
        $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8)
        try { $xmlText = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $xml = New-Object xml
        $xml.LoadXml($xmlText)
        $ns = New-Object Xml.XmlNamespaceManager($xml.NameTable)
        $ns.AddNamespace('w', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main')
        $parts = New-Object 'System.Collections.Generic.List[string]'
        foreach ($p in $xml.SelectNodes('//w:body//w:p', $ns)) {
            $line = ($p.SelectNodes('.//w:t', $ns) | ForEach-Object { $_.InnerText }) -join ''
            $parts.Add($line)
        }
        $dest = Join-Path $outDir ("gedeon-docx-{0}.txt" -f ($i+1))
        $header = "# Source: " + $files[$i].Name + "`r`n# Plain text extraction; layout, images, footnotes, and comments are not included.`r`n`r`n"
        [IO.File]::WriteAllText($dest, $header + ($parts -join "`r`n"), (New-Object Text.UTF8Encoding($false)))
        Write-Host "Extracted $($parts.Count) paragraphs to $dest"
    } finally { $zip.Dispose() }
}
