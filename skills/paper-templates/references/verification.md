# Verification checklist

A paper build is done only when every check below passes.
Presentation is part of correctness: a dropped figure, a wrong TOC number, or a stranded heading is a defect, not a nitpick.

## 1. Structure counts

Have the transform print its own counts - sections, subsections, figures, tables - and check them against the source by hand (both worked examples do this in their `__main__` block).
The counts catch dropped chapters and dropped stray figures, which are the most common walk bugs.

## 2. Content-parity token scan

Tokenize the source body and the paper body (excluding the contents lists on both sides, which are rebuilt) and compare:

- Every numeric token in the source must be present in the paper; report any missing.
- Diff the word tokens and account for every difference; acceptable differences are punctuation artifacts of re-emitted labels and metadata like the `<title>` tag, never content.

```python
import re
from bs4 import BeautifulSoup
def tokens(path, drop_selector):
    s = BeautifulSoup(open(path).read(), 'html.parser')
    for el in s.select(drop_selector): el.extract()
    return re.findall(r'[\w.%/-]+', s.body.get_text(' '))  # ' ' separator: bare get_text() glues adjacent elements into false tokens
src, out = set(tokens('source.html', '.contents')), set(tokens('paper.html', '.toc'))
missing_numeric = {t for t in src - out if re.search(r'\d', t)}
print('numeric tokens missing:', sorted(missing_numeric) or 'none')
```

## 3. Recolor completeness (dark-hex scan)

Scan the built HTML for any 6-digit hex with `r + g + b < 240` outside the allowed print set (`#1f4e79 #2e6b34 #9c6a1a #b3362f #6d4e87 #111111 #333333 #444444 #555555 #888888 #000000`).
The result must be none; each hit is a source color the `COLORMAP` missed.
Both worked examples end with this scan.

## 4. Page count

Parse the delivered PDF in place with `pypdf` and record the page count:

```python
from pypdf import PdfReader
print(len(PdfReader('paper.pdf').pages))
```

A count far below the pagination log's `paged pages:` line means a truncated print.

## 5. Page previews

Rasterize and inspect the title page, the contents, and every chapter/figure/table page with `pypdfium2`:

```python
import pypdfium2 as pdfium
pdf = pdfium.PdfDocument('paper.pdf')
for i in pages_to_check:
    pdf[i].render(scale=2).to_pil().save(f'preview-p{i+1}.png')
```

Be frugal on memory-constrained machines: render one page at a time and tear down between steps.
In the previews, check:

- No orphaned headings: every heading shares its page with body text or its table.
- No table or figure split across pages.
- TOC page numbers match the actual page each section starts on.
- The running header is correct (and absent on the title page) and the folio is centered in the footer.
- SVG text labels fit their figures under the serif override (no clipping at the viewBox edge).
- No near-empty pages from an oversized `break-inside: avoid` block.
