# Known pitfalls

Every entry below was hit for real while producing papers with this pipeline.
Read this before writing a transform and again before calling a build done.

## Rendering

- **Racing Paged.js truncates the PDF.**
  Plain `chrome --headless --print-to-pdf --virtual-time-budget` printed 7 pages of a 28-page document.
  Always render through `assets/render.js`, which waits for the `.pagedjs_page` count to be stable for 2 seconds before printing.
- **Paged.js ignores `string-set: attr(...)`.**
  The running header cannot be pulled from the document; it must be a literal string in the CSS, which is why the templates carry the `%%SHORT%%` placeholder for the build to replace.
- **HTML entities in CSS `content` print literally.**
  The short title lands inside `content: "..."` in a `<style>` block, which is raw CSS text: `&amp;` renders as `&AMP;` in the running header.
  Write "and", never an entity, in the short-title string.

## Pagination

- **A table slightly taller than one page strands its heading.**
  `break-inside: avoid` pushes the whole table to the next page, leaving the section heading and its note alone on a near-empty page.
  Fix deliberately: give that one table a compact rule (slightly smaller font, tighter padding) so it shares the page, rather than letting the template's default strand content.
- **TOC page numbers off by one.**
  When the anchor id sits on a `<section>` wrapper, the wrapper's box can technically open at the bottom of the previous page and `target-counter` reports that page.
  Put anchor ids on the `h2` headings themselves.
- **Orphaned-heading and split-table checks are part of done.**
  `break-after: avoid` on headings and `break-inside: avoid` on figures/tables handle the normal cases, but only the page previews prove it (see `verification.md`).

## Figures

- **SVG labels clip under the serif override.**
  Labels sized for the source's sans font can overrun the viewBox once the template's `figure svg text { font-family: serif }` applies, especially with `letter-spacing` attributes.
  Dropping the decorative letter-spacing (presentation only) usually fits them; verify in the rendered page preview.
- **Unmapped dark hexes survive recoloring silently.**
  A hand-built color map misses hexes that only appear in one diagram.
  Run the completeness scan (dark-hex scan in both worked examples) after every build; it must report none.

## Structure walks

- **Chapters that are siblings, not children.**
  One source kept chapters as siblings after each era header; a per-era walk emitted all era headings then all chapters and dropped chapter entries from the TOC.
  Walk the wrapper's direct children in document order.
- **Content outside any section gets dropped.**
  A figure living as a direct child of the page wrapper (outside every chapter) was silently lost by a section-only walk.
  Account for every direct child of the wrapper.

## Editorial

- **Caption duplication.**
  An authored table caption must not restate a note that already precedes the table; state only what the table is.
- **Web admonition styling leaks through.**
  Left-accent callout borders are web styling; the print form is a hairline box (`div.pnote`) or top/bottom hairlines.
  The same goes for stat tiles, KPI grids, filled pill badges, zebra striping, and colored header bands - each has a print-form equivalent in `transform-guide.md`.
