# Read-only audit of project Zotero items and their child attachments.
# Uses the proven local API client. No cloud key, no export of PDF content.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'check-zotero-local.ps1')
$reportPath = Join-Path $root 'research\zotero\attachment-audit.json'
$rows = @()
foreach ($entry in @($entries)) {
  $key = [string]$entry.key
  $children = @(Get-All ("/items/$key/children"))
  $attachments = @()
  foreach ($child in $children) {
    if ($child.data.itemType -ne 'attachment') { continue }
    $d = $child.data
    $filename = [string]$d.filename
    $contentType = [string]$d.contentType
    $isPdf = ($contentType -eq 'application/pdf') -or ($filename -match '(?i)\.pdf$')
    $attachments += [ordered]@{
      key = [string]$child.key
      title = [string]$d.title
      filename = $filename
      contentType = $contentType
      linkMode = [string]$d.linkMode
      isPdf = [bool]$isPdf
    }
  }
  $pdfs = @($attachments | Where-Object { $_.isPdf })
  $rows += [ordered]@{
    key = $key
    title = [string]$entry.title
    itemType = [string]$entry.itemType
    attachmentCount = $attachments.Count
    pdfCount = $pdfs.Count
    attachments = @($attachments)
  }
}
$report = [ordered]@{
  collectionKey = [string]$rootKey
  itemCount = $rows.Count
  pdfAttachmentCount = 0
  items = @($rows)
}
$report.pdfAttachmentCount = [int](($rows | ForEach-Object { [int]$_.pdfCount } | Measure-Object -Sum).Sum)
[IO.File]::WriteAllText(
  $reportPath,
  ($report | ConvertTo-Json -Depth 20),
  (New-Object Text.UTF8Encoding($false))
)
Write-Host "ZOTERO AUDIT: items=$($rows.Count); pdf_attachments=$($report.pdfAttachmentCount)"
foreach ($row in $rows) {
  Write-Host ("{0}  pdf={1}  attachments={2}  {3}" -f $row.key, $row.pdfCount, $row.attachmentCount, $row.title)
}
Write-Host "Output: $reportPath"
Write-Host 'NOTE: Attachment metadata only; physical file presence was not checked.'
