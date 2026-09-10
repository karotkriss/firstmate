# Writing the per-document transform

Each document gets its own small transform script; there is deliberately no generalized builder.
Source documents differ too much in structure for one builder to walk them safely, and a wrong walk silently drops content - the worked examples each hit a structural surprise (see `pitfalls.md`).
Write a fresh transform per document with BeautifulSoup, copying the closest worked example:

- `example-sectioned-transform.py` - sources whose chapters are `<section>` elements, including the sibling-chapters-after-era-headers variant that needs an ordered walk over the wrapper's direct children.
- `example-flat-transform.py` - a flat source whose sections are `h2` siblings directly in `body`.

The transform's job is form only: every section, number, table cell, and chart datum in the output must be identical to the source.
The verification checklist (`verification.md`) is how you prove that.

## Document shape

Emit the paper in this order, using the template's classes.

### Title block

`div.titlepage` with `.kicker` (small line above the title), `h1`, `p.sub` (italic subtitle), `p.date` ("Technical Report · Month Year"), and a bordered `div.envbox` for the document's standing context: a test-environment statement, an outcome line, or the source's metadata rows as small-caps-labelled lines.
The template suppresses the running header and folio on this page.

### Executive summary and headline table

A `div.front` holding an `h2` "Executive summary", the document's own arc paragraph as `p.abstract`, and the source's hero/KPI stats re-emitted as **Table 1** in the headline-results shape: two left-aligned columns, "Result" (bold value) and "What it measures".
This replaces web stat tiles and KPI grids, which must never survive into the paper.

### Contents

A `div.toc` listing every section (and part heading, if the source has eras/parts) as anchors.
Page numbers are real: the template's `.toc a::after { content: target-counter(attr(href), page) }` resolves them at pagination time.
Put the anchor `id` on the `h2` heading itself, never on a `<section>` wrapper - a wrapper's box can open at the bottom of the previous page and `target-counter` then reports that page (off by one).

### Numbered sections

Each source chapter becomes `<section>` with `h2.sec` ("N. Title", carrying the anchor id) and subsections as `h3.subsec` ("N.M Title").
Preserve the source's own numbering exactly when it has one; number unnumbered headings yourself, continuing one counter per section.
Chapter metadata (dates, run-heads) becomes `div.secmeta`.
Callout/note boxes become `div.pnote` with a small-caps `span.nt` lead-in - print-style hairline boxes, never left-accent web admonitions.
Labeled item lists (walls, tiers) become `p.wallitem` with a small-caps `span.wk` key.

### Tables

Booktabs rules only: the template gives `th` a heavy top rule and light bottom rule, and the last row a heavy bottom rule; no vertical rules, no zebra striping, no header bands.
Every table gets a numbered `<caption>`: `<b>Table N:</b> text.`, `caption-side: top`.
When the source table has no caption, author one that states only what the table is - no new facts, and never a restatement of a note that already precedes the table.
Colored status chips become small-caps text in the print palette's ink colors (`.tag` plus a color class), not filled pills.

### Figures

`<figure>` with the SVG geometry byte-identical to the source - only colors change, through the color map below.
Every figure gets a numbered `<figcaption>`: `<b>Figure N:</b> text.`.
Keep charts at aspect ratio <= 0.5 so no figure can exceed a page under `break-inside: avoid`.
Re-check SVG text labels under the template's serif override: labels sized for a sans font can overrun the viewBox, and dropping decorative `letter-spacing` attributes is usually the fix.

### References and colophon

Close with `div.refs`: an `h2` "References and sourcing", an ordered list built from the source's per-chapter source lines, and the source's original footer as `div.colophon`.

## Print color map

The print palette, used by both templates:

| Role | Hex |
| --- | --- |
| accent | `#1f4e79` |
| good | `#2e6b34` |
| warn | `#9c6a1a` |
| bad | `#b3362f` |
| optional | `#6d4e87` |
| ink | `#111` |
| muted | `#444` / `#555` |
| gridlines | `#ccc` |
| axis | `#888` |

Build a `COLORMAP` dict per document: every dark or web-palette hex the source uses, mapped to its print-palette role, and recolor figures by string replacement over the serialized SVG (both case variants) so geometry, values, and labels stay byte-identical.
Light fills in an already-light source need only palette alignment, not a dark-to-print rescue.

The map is only complete when the completeness scan says so: after the build, scan the output for any residual hex with `r + g + b < 240` outside the allowed print set (see the scan at the bottom of either worked example).
Two unmapped hexes hiding in one architecture diagram is exactly how this fails silently.
