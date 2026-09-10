---
name: paper-templates
description: Produce paper-style PDF documents - journey papers, technical reports, post-mortems, journal-style write-ups - from an HTML source using the house print templates and a verified Paged.js render pipeline. Use whenever a document is destined for print or for an upward-facing reader (management, a client, a stakeholder) as a PDF, whenever someone asks for a "paper", "report PDF", or "journal-style" document, and whenever an existing web-styled document needs to be recast in a durable print form; web-card styling is never acceptable for those documents, even if the user does not name a template.
---

<!-- maintainers: this is a public, installer-facing skill. Keep it standalone, with no private project paths or environment branching. -->

# paper-templates

Turn an HTML document into a print-quality PDF paper using one of two durable house templates, a per-document transform, and a Paged.js render pipeline.
Presentation is part of correctness here: an upward-facing document never ships with web-card styling (stat tiles, filled pills, left-accent admonitions, zebra striping), and every number, table, and figure in the paper must be identical to the source - only the visual form changes.

## Choose the template

- **Template C - two-column journal** (`assets/template-c.css`) is the **default** for paper-style documents: IEEE/ACM-like, dense two-column serif, small-caps section heads, roman-numeral sections, black ink only.
- **Template A - classic report** (`assets/template-a.css`) is the alternate: all-serif single column, centered title page, booktabs tables, numbered sections, running header, footer folios, TOC with real page numbers.
  Prefer it when the document is long and chapter-structured (journey papers and technical reports have shipped with it).

Default to C and offer A as the alternative; do not invent a third style, and never fall back to plain web styling.
If the user should see the direction before a full build, render the same short excerpt in both templates and let them pick.

Template A is production-ready as shipped.
Template C is the approved sample-scale stylesheet (scoped under `.sC`); to productionize it, drop the `.sC` scoping prefix, add template A's `@page` rules, and keep `.cols { column-count: 2 }` for the body flow.

## Pipeline

1. **Write a per-document transform** that parses the source HTML (BeautifulSoup) and re-emits it into the template's classes.
   Read `references/transform-guide.md` for the document shape (title block, executive summary and headline table, contents, numbered sections, captioned figures and tables, references/colophon) and the print color map.
   Copy the closest worked example rather than writing from scratch: `references/example-sectioned-transform.py` or `references/example-flat-transform.py`.
   There is deliberately no generalized builder - sources differ too much structurally, and a wrong walk drops content silently.
2. **Read the template CSS from the asset file at build time**, never paste it, so the paper cannot drift from the ruled stylesheet.
   Replace the `%%SHORT%%` placeholder with the document's running-header string.
   That replacement is the contract: Paged.js ignores `string-set: attr(...)`, so the header must be a literal string in the CSS - and it is raw CSS text, so never put an HTML entity in it.
3. **End the body with the Paged.js polyfill script tag**: copy `assets/paged.polyfill.js` (Paged.js v0.4.3, MIT) alongside the built HTML, load it with a relative script `src` as the last element in `<body>`, and render with the settle-wait driver:

   ```
   node render.js paper.html paper.pdf
   ```

   `assets/render.js` waits for the Paged.js page count to stabilize before printing.
   That wait is required, not an optimization: printing while Paged.js is still paginating has truncated a 28-page document to 7 pages.
4. **Verify** with the checklist in `references/verification.md`: structure counts, content-parity token scan, recolor-completeness dark-hex scan, `pypdf` page count, and `pypdfium2` page previews checked for orphaned headings, split tables, TOC accuracy, and clipped figure labels.

Before writing the transform, and again before calling the build done, read `references/pitfalls.md` - every entry in it was hit for real by this pipeline.

## Dependencies

- Python: `beautifulsoup4` (transform), `pypdf`, `pypdfium2`, `pillow` (verification); a venv is fine.
- Node: `puppeteer-core` next to `render.js`.
- A Chrome binary (`/usr/bin/google-chrome` by default; override with `CHROME_PATH`).
- A Times-class serif font: the templates use Liberation Serif with Georgia and Times New Roman fallbacks, so at least one must be installed for faithful output.
