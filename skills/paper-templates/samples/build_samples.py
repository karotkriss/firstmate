#!/usr/bin/env python3
"""Build the generic style samples: the same invented excerpt in template A and
template C, so a reader (or a user picking a direction) can see what each
template produces without any real document content.

Reads each stylesheet from ../assets at build time (never pastes it), and
productionizes template C exactly as SKILL.md describes: drop the .sC scoping
prefix, add template A's @page rules, keep the two-column body flow.

Usage: python3 build_samples.py
Then render each output with the settle-wait driver, e.g.
  node render.js sample-a.html sample-a.pdf
"""
import pathlib, re

HERE = pathlib.Path(__file__).resolve().parent
ASSETS = HERE.parent / 'assets'
SHORT = 'The Widget Pipeline · Sample Technical Report'

# Invented content: one excerpt exercising the template surfaces - title block,
# context box, a numbered section with a subsection, a booktabs table, a
# print-palette SVG figure with caption, and a hairline note box.
FIGURE = '''<figure>
<svg viewBox="0 0 640 200" role="img">
  <line class="gridline" x1="60" y1="30" x2="600" y2="30"/>
  <line class="gridline" x1="60" y1="80" x2="600" y2="80"/>
  <line class="gridline" x1="60" y1="130" x2="600" y2="130"/>
  <line class="axis" x1="60" y1="20" x2="60" y2="170"/>
  <line class="axis" x1="60" y1="170" x2="600" y2="170"/>
  <rect x="100" y="115" width="70" height="55" fill="#1f4e79"/>
  <rect x="230" y="40" width="70" height="130" fill="#9c6a1a"/>
  <rect x="360" y="130" width="70" height="40" fill="#1f4e79"/>
  <rect x="490" y="95" width="70" height="75" fill="#1f4e79"/>
  <text x="135" y="185" font-size="11" text-anchor="middle" fill="#444444">parse</text>
  <text x="265" y="185" font-size="11" text-anchor="middle" fill="#444444">assemble</text>
  <text x="395" y="185" font-size="11" text-anchor="middle" fill="#444444">paint</text>
  <text x="525" y="185" font-size="11" text-anchor="middle" fill="#444444">ship</text>
  <text x="52" y="174" font-size="11" text-anchor="end" fill="#444444">0</text>
  <text x="52" y="84" font-size="11" text-anchor="end" fill="#444444">40</text>
</svg>
<figcaption><b>Figure 1:</b> Wall-clock seconds per pipeline stage in run 42. Assembly dominates; the ship stage is network-bound and holds the only cross-host dependency.</figcaption>
</figure>'''

TABLE = '''<table>
<caption><b>Table 1:</b> Headline results of the widget pipeline, runs 40-42.</caption>
<tr><th class="left" style="width:28%">Result</th><th class="left">What it measures</th></tr>
<tr><td class="left"><b>96 s</b></td><td class="left">Wall clock of run 42, cold cache.</td></tr>
<tr><td class="left"><b>3,412</b></td><td class="left">Widgets assembled, identical in all runs.</td></tr>
<tr><td class="left"><b>0</b></td><td class="left">Escaped paint defects after the run-41 fix.</td></tr>
</table>'''

BODY_A = f'''<div class="titlepage">
<div class="kicker">Widget Works · Engineering Report</div>
<h1>The Widget Pipeline</h1>
<p class="sub">Three instrumented runs, one bottleneck, and the fixture that fixed it</p>
<p class="date">Technical Report · September 2026</p>
<div class="envbox"><b>Test environment.</b> All three runs executed serially on one 8-core / 16 GB build host with a cold cache. Absolute times carry that ceiling; the stage-ranking conclusions hold regardless.</div>
</div>
<div class="front">
<h2>Executive summary</h2>
<p class="abstract">Across runs 40-42 the pipeline's wall clock fell from 141 to 96 seconds without changing the widget count, entirely by removing redundant work in the assembly stage. This excerpt shows the shape of the full report: every claim traces to a numbered table or figure.</p>
{TABLE}
</div>
<section>
<h2 class="sec" id="s1">1. Where the time goes</h2>
<div class="secmeta">Runs 40-42, 2026-09-06 to 2026-09-08.</div>
<p>Instrumenting the four stages shows assembly holding more than half of the wall clock in every run. The paint stage is short but serial, and the ship stage varies with the artifact registry's latency rather than with anything the pipeline controls.</p>
{FIGURE}
<h3 class="subsec">1.1 The assembly bottleneck</h3>
<p>Run 40 assembled every widget twice: once to size it and once to place it. Run 41 memoized the sizing pass behind a content hash, and run 42 confirmed the effect holds on a cold cache.</p>
<div class="pnote"><span class="nt">Rule.</span> A stage may only be declared the bottleneck from a run that instruments all four stages; partial traces ranked the wrong stage twice during this work.</div>
</section>'''

# The same excerpt in template C's journal idiom: roman-numeral small-caps
# section heads and a two-column flow after the title block.
BODY_C = f'''<div class="titleblock">
<h1>The Widget Pipeline</h1>
<p class="sub">Three instrumented runs, one bottleneck, and the fixture that fixed it</p>
<p class="date">Widget Works · Technical Report · September 2026</p>
</div>
<div class="envbox"><b>Test environment.</b> All three runs executed serially on one 8-core / 16 GB build host with a cold cache. Absolute times carry that ceiling; the stage-ranking conclusions hold regardless.</div>
<div class="cols">
<h2><span class="no">I.</span> Where the time goes</h2>
<p>Across runs 40-42 the pipeline's wall clock fell from 141 to 96 seconds without changing the widget count, entirely by removing redundant work in the assembly stage. Instrumenting the four stages shows assembly holding more than half of the wall clock in every run.</p>
{TABLE}
<p>The paint stage is short but serial, and the ship stage varies with the artifact registry's latency rather than with anything the pipeline controls.</p>
{FIGURE}
<h2><span class="no">II.</span> The assembly bottleneck</h2>
<p>Run 40 assembled every widget twice: once to size it and once to place it. Run 41 memoized the sizing pass behind a content hash, and run 42 confirmed the effect holds on a cold cache.</p>
</div>'''

def page_rules(css_a: str) -> str:
    """Template A's @page rules, taken from the stylesheet itself."""
    m = re.match(r'(.*?@page :first[^}]*}.*?}\n)', css_a, re.S)
    return m.group(1)

def shell(css: str, body: str, title: str) -> str:
    return (f'<!DOCTYPE html>\n<html lang="en"><head><meta charset="utf-8">'
            f'<title>{title}</title>\n<style>{css}</style></head>\n<body>{body}\n'
            f'<script src="paged.polyfill.js"></script></body></html>\n')

def main():
    css_a = (ASSETS / 'template-a.css').read_text().replace('%%SHORT%%', SHORT)
    (HERE / 'sample-a.html').write_text(shell(css_a, BODY_A, 'Template A sample'))

    # productionize C per SKILL.md: drop the .sC prefix, add A's @page rules,
    # keep .cols { column-count: 2 }
    css_c = (ASSETS / 'template-c.css').read_text().replace('.sC ', '').replace('.sC{', 'body{')
    css_c = page_rules(css_a) + 'body { margin: 0 }\n' + css_c
    (HERE / 'sample-c.html').write_text(shell(css_c, BODY_C, 'Template C sample'))
    print('wrote sample-a.html sample-c.html')

if __name__ == '__main__':
    main()
