#!/usr/bin/env python3
"""Worked example: recast a flat go-live journey document as a template-A paper.

This is a real production transform, kept as a reference, not a generalized builder.
It shows the flat-source case: a single document whose sections are `h2.section`
siblings directly in `body` (some wrapped in forced-page-break divs), walked as a
flat iteration that opens a new output <section> at each heading.

Content contract: every section, number, table and figure identical to the
source; only the visual form changes. Template A CSS is read verbatim from the
skill's asset file, with two small additions noted below (tag color classes for
chip inks, a compact rule for one oversized table).
"""
import re, sys, pathlib
from bs4 import BeautifulSoup, NavigableString

SRC = 'src/golive-journey.html'   # the source document; adapt per build
HERE = pathlib.Path(__file__).resolve().parent
ASSETS = HERE.parent / 'assets'

# source palette -> print palette (figure + chip inks; light fills stay)
COLORMAP = {
    '#1F3A5F': '#1f4e79',   # navy -> accent
    '#9E2222': '#b3362f',   # red
    '#3E6B4F': '#2e6b34',   # green
    '#B45309': '#9c6a1a',   # amber
    '#5A6B7B': '#555555',   # slate -> muted
    '#2c3a47': '#111111',   # body ink
    '#71828f': '#555555',
    '#9AA8B5': '#888888',
}
def recolor(s: str) -> str:
    for k, v in COLORMAP.items():
        s = s.replace(k, v).replace(k.lower(), v)
    return s

EXTRA_CSS = '''
/* additions for this document */
.tag.tgood { color:#2e6b34; } .tag.tbad { color:#b3362f; }
.tag.twarn { color:#9c6a1a; } .tag.tinfo { color:#444444; }
.srcnote { font-size: 9pt; font-style: italic; color:#333; }
td small { display:block; font-size:8pt; color:#555; }
/* the full-night timeline is a hair taller than one page at 9.5pt; set solid
   at 9pt so the section heading, its note and the whole table share a page */
table.longtl { font-size: 9pt; line-height: 1.28; }
table.longtl td { padding: 2.4pt 5pt; }
'''

# the running-header string is raw CSS text: no HTML entities ("&amp;" would
# print literally), so write "and", not "&"
SHORT = 'Go-live Journey · Portal and CMS · September 2026'

def text_of(el):
    return re.sub(r'\s+', ' ', el.get_text()).strip() if el else ''

def inner(el):
    return ''.join(str(c) for c in el.contents)

def frag(out, html):
    return BeautifulSoup(html, 'html.parser')

def new_tag(s, name, cls=None, text=None, **kw):
    t = s.new_tag(name, **kw)
    if cls: t['class'] = cls
    if text is not None: t.string = text
    return t

CHIPMAP = {'ok': 'tgood', 'fail': 'tbad', 'warn-chip': 'twarn', 'info': 'tinfo'}

def convert_chips(scope_soup):
    for chip in scope_soup.find_all('span', class_='chip'):
        cls = [c for c in chip.get('class', []) if c in CHIPMAP]
        chip['class'] = ['tag', CHIPMAP.get(cls[0], 'tinfo') if cls else 'tinfo']

def main():
    s = BeautifulSoup(open(SRC).read(), 'html.parser')
    # template CSS read from the asset file at build time, never pasted, so the
    # paper cannot drift from the ruled stylesheet
    css = (ASSETS / 'template-a.css').read_text().replace('%%SHORT%%', SHORT) + EXTRA_CSS
    out = BeautifulSoup(f'''<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<title>Go-live Journey - Portal and CMS - Technical Report</title>
<style>{css}</style></head><body></body></html>''', 'html.parser')
    body = out.body
    tab_n = 0
    fig_n = 0

    # ---------- title page ----------
    src_tp = s.select_one('.titlepage')
    tp = new_tag(out, 'div', 'titlepage')
    org = text_of(src_tp.select_one('.band .org')).replace('\xa0', ' ')
    kind = text_of(src_tp.select_one('.band .kind'))
    tp.append(new_tag(out, 'div', 'kicker', f'{org} · {kind}'))
    h1 = new_tag(out, 'h1'); h1.append(frag(out, inner(src_tp.find('h1')))); tp.append(h1)
    tp.append(new_tag(out, 'p', 'sub', text_of(src_tp.select_one('.subtitle'))))
    tp.append(new_tag(out, 'p', 'date', 'Technical Report · September 2026'))
    env = new_tag(out, 'div', 'envbox')
    badge = text_of(src_tp.select_one('.outcome-badge'))
    note = text_of(src_tp.select_one('.outcome-note'))
    env.append(frag(out, f'<p style="margin:0 0 4pt"><b>{badge}.</b> {note}</p>'))
    for row in src_tp.select('.meta table tr'):
        k = text_of(row.select_one('td.k'))
        v = inner(row.find_all('td')[1])
        env.append(frag(out, f'<p style="margin:0 0 2pt"><b>{k}.</b> {v}</p>'))
    tp.append(env)
    body.append(tp)

    # ---------- contents (rebuilt with real page numbers) ----------
    toc = new_tag(out, 'div', 'toc')
    toc.append(new_tag(out, 'h2', None, 'Contents'))
    ul = new_tag(out, 'ul')
    for li_src in src_tp.select('.contents ol li'):
        n = text_of(li_src.select_one('.n'))
        a_src = li_src.find('a')
        li = new_tag(out, 'li')
        li.append(new_tag(out, 'a', None, f'{n}. {text_of(a_src)}', href=a_src['href']))
        ul.append(li)
    toc.append(ul)
    body.append(toc)

    # ---------- walk document body, flattening .newpage wrappers ----------
    def flat_children():
        for el in s.body.find_all(recursive=False):
            if isinstance(el, NavigableString): continue
            cls = el.get('class', [])
            if 'titlepage' in cls: continue
            if el.name == 'div' and 'newpage' in cls:
                for c in el.find_all(recursive=False):
                    yield c
            else:
                yield el

    cur = None          # current output <section>
    cur_num = None      # current section number
    sub_n = 0           # subsection counter for sections without pre-numbered h3s

    def emit_table(el, caption, widen=None):
        nonlocal tab_n
        tab_n += 1
        is_timeline = 'timeline' in el.get('class', [])
        tb = frag(out, str(el)).table
        for a in ('class', 'style'):
            if tb.has_attr(a): del tb[a]
        if is_timeline: tb['class'] = 'longtl'
        convert_chips(tb)
        for cell in tb.find_all(['td', 'th']):
            c = cell.get('class', [])
            if not isinstance(c, list): c = [c]
            cell['class'] = c + ['left']
            if 'k' in c:
                cell.insert(0, frag(out, '<b></b>'))
                b = cell.find('b'); rest = [x for x in cell.contents if x is not b]
                # bold the key cell text
                txt = ''.join(str(x) for x in rest)
                for x in rest: x.extract()
                b.append(frag(out, txt))
        cap = new_tag(out, 'caption')
        cap.append(frag(out, f'<b>Table {tab_n}:</b> {caption}'))
        tb.insert(0, cap)
        return tb

    def emit_metrics(el):
        nonlocal tab_n
        tab_n += 1
        rows = []
        for td in el.select('table td'):
            v = td.select_one('.v'); l = td.select_one('.l')
            if not (v and l): continue
            rows.append(f'<tr><td class="left"><b>{text_of(v)}</b></td><td class="left">{inner(l)}</td></tr>')
        cap = text_of(el.select_one('.m-tag'))
        return frag(out, f'<table><caption><b>Table {tab_n}:</b> {cap}.</caption>'
                         f'<tr><th class="left" style="width:24%">Result</th>'
                         f'<th class="left">What it measures</th></tr>{"".join(rows)}</table>')

    def emit_pnote(tag_text, el_ps):
        nb = new_tag(out, 'div', 'pnote')
        first = True
        for pp in el_ps:
            p = frag(out, str(pp)).p
            if p.has_attr('style'): del p['style']
            if first:
                p.insert(0, frag(out, f'<span class="nt">{tag_text}.</span> '))
                first = False
            nb.append(p)
        return nb

    # the source tables carry no captions; numbered captions are a template
    # requirement, so these are authored - they state only what the table is,
    # never a fact the body does not already carry (and never restate a note
    # that already precedes the table)
    TABLE_CAPTIONS = {
        2: 'Component versions and deploy paths, before and after the night.',
        3: 'Timeline of the night.',
        4: 'The six CMS production deploy runs and the three hand-built images behind them.',
        5: 'Follow-up work left by the night, in the order the team should take it.',
    }

    for el in flat_children():
        cls = el.get('class', [])
        dest = cur if cur is not None else body

        if el.name == 'h2' and 'section' in cls:
            num = text_of(el.select_one('.no'))
            title = text_of(el).replace(num, '', 1).strip()
            cur = new_tag(out, 'section')
            cur_num = num
            sub_n = 0
            # id on the heading, not the section box: target-counter must give
            # the page the heading prints on, not where the box opens
            cur.append(new_tag(out, 'h2', 'sec', f'{num}. {title}', id=el['id']))
            body.append(cur)
            continue
        if el.name == 'h3':
            t = text_of(el)
            if re.match(r'^\d+\.\d+\s', t):
                dest.append(new_tag(out, 'h3', 'subsec', t))
            else:
                sub_n += 1
                dest.append(new_tag(out, 'h3', 'subsec', f'{cur_num}.{sub_n} {t}'))
            continue
        if el.name == 'div' and 'bottomline' in cls:
            dest.append(emit_pnote(text_of(el.select_one('.bl-tag')), el.find_all('p', recursive=False)))
            continue
        if el.name == 'div' and 'callout' in cls:
            dest.append(emit_pnote(text_of(el.select_one('.c-tag')), el.find_all('p', recursive=False)))
            continue
        if el.name == 'div' and 'metrics' in cls:
            dest.append(emit_metrics(el))
            continue
        if el.name == 'div' and 'lesson' in cls:
            sub_n += 1
            dest.append(new_tag(out, 'h3', 'subsec', f'{cur_num}.{sub_n} {text_of(el.select_one(".lt"))}'))
            for pp in el.find_all('p', recursive=False):
                dest.append(frag(out, str(pp)))
            continue
        if el.name == 'table':
            dest.append(emit_table(el, TABLE_CAPTIONS[tab_n + 1]))
            continue
        if el.name == 'figure':
            fig_n += 1
            # drop svg letter-spacing: the labels were sized for the source's
            # sans font and clip at the viewBox edge once the template's serif
            # is applied
            fg = frag(out, recolor(str(el)).replace(' letter-spacing="1.5"', '')).figure
            cap = fg.find('figcaption')
            old = text_of(cap)
            old = re.sub(rf'^Figure {fig_n}\.\s*', '', old)
            cap.clear()
            cap.append(frag(out, f'<b>Figure {fig_n}:</b> {old}'))
            dest.append(fg)
            continue
        if el.name == 'p' and 'small-note' in cls:
            p = frag(out, str(el)).p
            p['class'] = 'srcnote'
            if p.has_attr('style'): del p['style']
            dest.append(p)
            continue
        if el.name == 'ol' and 'steps' in cls:
            ol = frag(out, str(el)).ol
            del ol['class']
            dest.append(ol)
            continue
        # default: paragraphs, ul, etc. pass through
        dest.append(frag(out, str(el)))

    # Paged.js polyfill loads last, after all content
    body.append(frag(out, '<script src="paged.polyfill.js"></script>'))
    html = str(out)
    open('golive-paper.html', 'w').write(html)

    # verification: leftover suspicious dark hexes, structure counts
    allowed = {'#1f4e79', '#2e6b34', '#9c6a1a', '#b3362f', '#6d4e87',
               '#111111', '#444444', '#555555', '#333333', '#888888', '#000000'}
    dark = set()
    for m in re.finditer(r'#[0-9a-fA-F]{6}\b', html):
        h = m.group(0).lower()
        r, g, b = int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16)
        if r + g + b < 240 and h not in allowed:
            dark.add(h)
    print('suspicious dark hexes:', sorted(dark) or 'none')
    print('sections:', html.count('<h2 class="sec"'),
          'subsections:', html.count('<h3 class="subsec"'),
          'figures:', fig_n, 'tables:', tab_n, 'bytes:', len(html))

if __name__ == '__main__':
    main()
