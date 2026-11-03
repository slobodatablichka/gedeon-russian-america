#!/usr/bin/env python3
# Local, read-only source indexing. Never upload full copyrighted book text to a public repository.
from __future__ import annotations
import json
import sys
from pathlib import Path

try:
    import pymupdf
except ImportError:
    sys.exit("PyMuPDF is missing. Install with: python -m pip install pymupdf")

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PDF = Path(r"Y:\Личка\Семинария\Дергалев Гедеон\Православие-в-Русской-Америке.pdf")
SOURCE = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PDF
PRIVATE_DIR = ROOT / "research" / "local-private" / "kapalin-pages"
REPORT = ROOT / "research" / "kapalin-page-index.json"
TERMS = {
    "Gedeon_Fedotov": ("гедеон", "федотов"),
    "Orthodox_mission": ("мисс",),
    "Kodiak": ("кадьяк",),
    "Rezanov": ("резанов",),
    "Baranov": ("баранов",),
    "Russian_American_Company": ("российско-американск", "российско американск"),
}
if not SOURCE.is_file():
    sys.exit(f"PDF not found: {SOURCE}")

PRIVATE_DIR.mkdir(parents=True, exist_ok=True)
hits = {label: [] for label in TERMS}
readable_pages = 0
char_total = 0

with pymupdf.open(SOURCE) as pdf:
    total = len(pdf)
    for number, page in enumerate(pdf, start=1):
        page_text = page.get_text("text", sort=True)
        char_total += len(page_text)
        if sum(ch.isalpha() for ch in page_text) >= 40:
            readable_pages += 1
        (PRIVATE_DIR / f"pdf-page-{number:04d}.txt").write_text(
            f"PDF page: {number}; printed page number: NOT VERIFIED\n\n" + page_text,
            encoding="utf-8",
        )
        haystack = page_text.casefold()
        for label, needles in TERMS.items():
            if any(needle in haystack for needle in needles):
                hits[label].append(number)

report = {
    "source": "Klement (Kapalin), Pravoslavie v Russkoi Amerike (2020)",
    "zoteroKey": "XCMHD4U4",
    "pdfFilename": SOURCE.name,
    "pdfPages": total,
    "pagesWithExtractableText": readable_pages,
    "extractedCharacters": char_total,
    "hitsByPdfPage": hits,
    "warning": "PDF page numbers are not verified printed page numbers; inspect original before citation.",
    "textFiles": "LOCAL ONLY: research/local-private/kapalin-pages; excluded from Git",
}
REPORT.parent.mkdir(parents=True, exist_ok=True)
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

print(f"KAPALIN: PDF pages={total}, pages with text={readable_pages}")
for key, pages in hits.items():
    preview = ", ".join(str(p) for p in pages[:20])
    suffix = "..." if len(pages) > 20 else ""
    print(f"  {key}: {len(pages)} pages; {preview}{suffix}")
print(f"Report: {REPORT}")
print(f"Full extracted text: {PRIVATE_DIR} (local only; do NOT git add it)")
if readable_pages < total * 0.70:
    print("WARNING: Many pages lack readable text; OCR may be needed before research.")
