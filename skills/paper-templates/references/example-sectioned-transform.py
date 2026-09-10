#!/usr/bin/env python3
"""Worked example: recast two chapter-structured journey documents as template-A papers.

This is a real production transform, kept as a reference, not a generalized builder.
It shows the sectioned-source case: one source whose chapters are `section.ch`
elements, and one whose chapters are *siblings* of their era headers inside a
flat wrapper (the ordered-walk pattern in build_k8s).

Content contract: every chapter, number, and chart's data identical to the
source; only the visual form changes.

Adapt SRC/OUT and the selectors to your document; keep the shape:
title page -> executive summary + headline table -> contents -> numbered
sections -> references/colophon, with figures and tables renumbered and
captioned as they are emitted.
"""
import re, sys, copy, pathlib
from bs4 import BeautifulSoup, NavigableString, Tag

SRC = 'src'          # directory holding the source journey.html files
OUT = 'build'        # output directory; render.js and paged.polyfill.js go alongside
ASSETS = pathlib.Path(__file__).resolve().parent.parent / 'assets'

# ---------- print color map (this source's dark web palette -> print-safe) ----------
# Build one of these per document: every dark/web hex the source uses, mapped to
# the print palette. The completeness scan at the bottom catches any hex you missed.
COLORMAP = {
    '#4fc3f7': '#1f4e79', '#66bb6a': '#2e6b34', '#ffb74d': '#9c6a1a',
    '#ef5350': '#b3362f', '#ff8a80': '#b3362f', '#ce93d8': '#6d4e87',
    '#e8ecf4': '#111111', '#e8edf7': '#111111',
    '#9aa7bd': '#444444', '#a7b3ca': '#444444',
    '#6f7d95': '#555555', '#71809d': '#555555',
    '#2a3550': '#cccccc', '#26304a': '#cccccc',
    '#171e2e': '#f5f5f5', '#1c2537': '#efefef', '#1c2436': '#efefef',
    '#20304a': '#e4e9f0', '#0f1420': '#ffffff', '#0d1220': '#f5f5f5',
    '#0c1018': '#f5f5f5', '#141c2c': '#ffffff', '#1b2436': '#efefef',
    '#3a2020': '#f2dedd', '#3a2f18': '#f0e8d5', '#173a2a': '#dfeae1',
    '#33203d': '#ece2f0', '#141d29': '#eef2f6', '#151f1a': '#e9f0ea',
    '#211819': '#f6e9e8', '#1b1f26': '#f2f2f2', '#1a2132': '#f2f2f2',
    '#a5d6ff': '#1f4e79', '#2a2233': '#ece2f0', '#3a4767': '#888888',
}
def recolor(s: str) -> str:
    for k, v in COLORMAP.items():
        s = s.replace(k, v).replace(k.upper(), v)
    return s

# Template CSS is read from the skill's asset file at build time, never pasted,
# so the paper cannot drift from the ruled stylesheet.
CSS = (ASSETS / 'template-a.css').read_text()

def soup_of(path):
    return BeautifulSoup(open(path).read(), 'html.parser')

def text_of(el):
    return re.sub(r'\s+', ' ', el.get_text()).strip() if el else ''

def new_tag(s, name, cls=None, text=None, **kw):
    t = s.new_tag(name, **kw)
    if cls: t['class'] = cls
    if text is not None: t.string = text
    return t

def strip_attrs(el):
    for a in ('style',):
        if el.has_attr(a): del el[a]

def keep_inline_html(el):
    """inner HTML of el as string"""
    return ''.join(str(c) for c in el.contents)

def shell(title_html, short_title):
    # %%SHORT%% must be replaced with a literal string: Paged.js ignores
    # string-set: attr(...), and CSS content is raw text (no HTML entities).
    return BeautifulSoup(f'''<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>{title_html}</title>
<style>{CSS.replace('%%SHORT%%', short_title)}</style></head>
<body></body></html>''', 'html.parser')

def finish(out):
    # Paged.js polyfill loads last, after all content
    out.body.append(BeautifulSoup('<script src="paged.polyfill.js"></script>', 'html.parser'))
    return str(out)

# =====================================================================
# DOCUMENT 1: chapters are section.ch elements
# =====================================================================
def build_compose():
    s = soup_of(f'{SRC}/compose-track-journey/journey.html')
    out = shell('The Compose Track - Technical Report', 'The Compose Track · Frappe Production Boilerplate · August 2026')
    body = out.body
    fig_n = tab_n = 0
    refs = []   # (label, text)

    def add(el): body.append(el)

    # ---- title page ----
    h1 = s.select_one('header.top h1')
    sub = text_of(s.select_one('header.top p.sub'))
    meta = text_of(s.select_one('header.top .meta'))
    tp = new_tag(out, 'div', 'titlepage')
    tp.append(new_tag(out, 'div', 'kicker', meta))
    t = new_tag(out, 'h1'); t.append(BeautifulSoup(keep_inline_html(h1), 'html.parser')); tp.append(t)
    tp.append(new_tag(out, 'p', 'sub', sub))
    tp.append(new_tag(out, 'p', 'date', 'Technical Report · August 2026'))
    env = new_tag(out, 'div', 'envbox')
    env.append(BeautifulSoup('<b>Test environment.</b> Except where noted, every measurement in this report was taken on a single shared development host with 20 cores and 8 GB of memory. Absolute throughput figures carry that ceiling; the bottleneck attributions (which resource saturated) are resource-saturation facts that hold regardless.', 'html.parser'))
    tp.append(env)
    add(tp)

    # ---- front matter: executive summary ----
    front = new_tag(out, 'div', 'front')
    front.append(new_tag(out, 'h2', None, 'Executive summary'))
    ab = new_tag(out, 'p', 'abstract', sub + ' Every figure in this document traces to a specific measurement run or merge request; the companion sourcing record maps each one.')
    front.append(ab)
    tab_n += 1
    tbl = BeautifulSoup('<table><caption><b>Table 1:</b> Headline results of the Compose track, start of the journey to 2026-08-11.</caption><tr><th class="left" style="width:28%">Result</th><th class="left">What it measures</th></tr></table>', 'html.parser')
    for st in s.select('.hero .stat'):
        n, l = text_of(st.select_one('.n')), text_of(st.select_one('.l'))
        row = BeautifulSoup(f'<tr><td class="left"><b>{n}</b></td><td class="left">{l}</td></tr>', 'html.parser')
        tbl.table.append(row.tr)
    front.append(tbl.table)

    # how-to-read card -> reading guide
    card = s.select_one('div.wrap > div.card')  # first card
    front.append(new_tag(out, 'h2', None, 'How to read this document'))
    p = card.find('p')
    gp = new_tag(out, 'p'); gp.append(BeautifulSoup(keep_inline_html(p), 'html.parser')); front.append(gp)
    for item in card.select('.wall > div'):
        k, v = text_of(item.select_one('.k')), keep_inline_html(item.select_one('.v'))
        wi = new_tag(out, 'p', 'wallitem')
        wi.append(BeautifulSoup(f'<span class="wk">{k}.</span> {v}', 'html.parser'))
        front.append(wi)
    add(front)

    # ---- contents ----
    toc = new_tag(out, 'div', 'toc')
    toc.append(new_tag(out, 'h2', None, 'Contents'))
    ul = new_tag(out, 'ul')
    secs = s.select('section.ch')
    for sec in secs:
        sid = sec.get('id')
        h2t = text_of(sec.find('h2'))
        num = sid[1:] + '. ' if sid and sid != 'end' else ''
        li = new_tag(out, 'li')
        a = new_tag(out, 'a', None, num + h2t, href=f'#{sid}')
        li.append(a); ul.append(li)
    li = new_tag(out, 'li'); li['class'] = 'part'
    a = new_tag(out, 'a', None, 'References and sourcing', href='#refs'); li.append(a); ul.append(li)
    toc.append(ul); add(toc)

    # ---- stray figures that are direct children of div.wrap (era timeline) ----
    # a figure outside any section is silently dropped by a section-only walk;
    # emit direct children in document order instead
    wrap = s.select('div.wrap')[1] if len(s.select('div.wrap')) > 1 else s.select_one('div.wrap')
    for el in wrap.find_all('figure', recursive=False):
        fig_n += 1
        fg = BeautifulSoup(recolor(str(el)), 'html.parser').figure
        cap = fg.find('figcaption')
        if cap is None:
            cap = new_tag(out, 'figcaption'); fg.append(cap)
        cap.insert(0, BeautifulSoup(f'<b>Figure {fig_n}:</b> ', 'html.parser'))
        add(fg)

    # ---- chapters ----
    for sec in secs:
        sid = sec.get('id'); is_end = (sid == 'end')
        num = None if is_end else int(sid[1:])
        osec = new_tag(out, 'section', None)
        htitle = text_of(sec.find('h2'))
        # anchor id goes on the heading (not the section wrapper): target-counter
        # must report the page the heading prints on, not where the box opens
        osec.append(new_tag(out, 'h2', 'sec', (f'{num}. ' if num else '') + htitle, id=sid))
        meta_el = sec.select_one('.chmeta')
        if meta_el: osec.append(new_tag(out, 'div', 'secmeta', text_of(meta_el)))
        sub_n = 0

        def emit(el, dest):
            nonlocal fig_n, tab_n, sub_n
            if isinstance(el, NavigableString): return
            name = el.name
            cls = el.get('class', [])
            if name in ('h2',) or 'chhead' in cls or 'chmeta' in cls: return
            if name in ('h3', 'h4'):
                sub_n += 1
                pre = f'{num}.{sub_n} ' if num else ''
                dest.append(new_tag(out, 'h3', 'subsec', pre + text_of(el)))
                return
            if name == 'p' and 'src' in cls:
                refs.append((f'ch. {num}' if num else 'end state', text_of(el)))
                sp = new_tag(out, 'p'); sp['style'] = 'font-size:9pt;font-style:italic;margin-top:-4pt'
                sp.string = text_of(el); dest.append(sp); return
            if name == 'div' and 'wall' in cls:
                for item in el.find_all('div', recursive=False):
                    k = item.select_one('.k'); v = item.select_one('.v')
                    if not (k and v): continue
                    wi = new_tag(out, 'p', 'wallitem')
                    wi.append(BeautifulSoup(f'<span class="wk">{text_of(k)}.</span> {keep_inline_html(v)}', 'html.parser'))
                    dest.append(wi)
                return
            if name == 'div' and 'note' in cls:
                nb = new_tag(out, 'div', 'pnote')
                nb.append(BeautifulSoup(keep_inline_html(el), 'html.parser'))
                fb = nb.find('b')
                if fb: fb['class'] = 'nt'
                dest.append(nb); return
            if name == 'div' and 'two' in cls:
                for c in el.find_all(recursive=False): emit(c, dest)
                return
            if name == 'div' and ('card' in cls or 'legend' in cls):
                if 'legend' in cls:
                    lg = BeautifulSoup(recolor(str(el)), 'html.parser'); dest.append(lg); return
                for c in el.find_all(recursive=False): emit(c, dest)
                return
            if name == 'figure':
                fig_n += 1
                fg = BeautifulSoup(recolor(str(el)), 'html.parser').figure
                cap = fg.find('figcaption')
                if cap is None:
                    cap = new_tag(out, 'figcaption'); fg.append(cap)
                cap.insert(0, BeautifulSoup(f'<b>Figure {fig_n}:</b> ', 'html.parser'))
                dest.append(fg); return
            if name == 'table':
                tab_n += 1
                tb = BeautifulSoup(str(el), 'html.parser').table
                strip_attrs(tb)
                ths = tb.find_all('th')
                capt = text_of(ths[1]) if len(ths) >= 2 and len(text_of(ths[1])) > 12 else htitle
                cap = new_tag(out, 'caption')
                cap.append(BeautifulSoup(f'<b>Table {tab_n}:</b> {capt}.', 'html.parser'))
                tb.insert(0, cap)
                dest.append(tb); return
            if name == 'hr': return
            # default: paragraphs, lists, code... keep inline content
            cp = BeautifulSoup(str(el), 'html.parser')
            dest.append(cp)
            return

        for child in sec.children:
            emit(child, osec)
        add(osec)

    # ---- references ----
    add(build_refs(out, s, refs, footer_sel='.footer',
        lead='Every figure in this document is traceable. The companion sourcing record '
             '(<code>compose-track-journey/report.md</code>) maps each number to the report, evidence file, '
             'or merge request that produced it; the per-chapter sources below are reproduced from the document itself.'))
    return finish(out)

# =====================================================================
# DOCUMENT 2: chapters are *siblings* of their era headers in a flat wrapper
# =====================================================================
def build_k8s():
    s = soup_of(f'{SRC}/k8s-track-journey/journey.html')
    out = shell('The Kubernetes Track - Technical Report', 'The Kubernetes Track · Frappe Production Boilerplate · August 2026')
    body = out.body
    fig_n = tab_n = 0
    refs = []

    # ---- title page ----
    h1 = s.select_one('.hero h1')
    subel = h1.find('span', class_='sub')
    subtxt = text_of(subel); subel.extract()
    title = text_of(h1)
    kicker = text_of(s.select_one('.kicker'))
    tp = new_tag(out, 'div', 'titlepage')
    tp.append(new_tag(out, 'div', 'kicker', kicker))
    tp.append(new_tag(out, 'h1', None, title))
    tp.append(new_tag(out, 'p', 'sub', subtxt))
    tp.append(new_tag(out, 'p', 'date', 'Technical Report · August 2026'))
    env = new_tag(out, 'div', 'envbox')
    env.append(BeautifulSoup('<b>Test environment.</b> All measurements were taken on one 20-core / 8 GB host, serially, behind a memory watchdog that never tripped in any run reported here. Absolute throughput figures carry that ceiling; bottleneck attributions hold regardless.', 'html.parser'))
    tp.append(env)
    body.append(tp)

    # ---- abstract + headline results ----
    front = new_tag(out, 'div', 'front')
    front.append(new_tag(out, 'h2', None, 'Executive summary'))
    arc = s.select_one('.arc')
    ap = new_tag(out, 'p', 'abstract'); ap.append(BeautifulSoup(keep_inline_html(arc), 'html.parser'))
    front.append(ap)
    tab_n += 1
    tbl = BeautifulSoup('<table><caption><b>Table 1:</b> Headline results of the Kubernetes track, 2026-08-07 to 2026-08-11.</caption><tr><th class="left" style="width:22%">Result</th><th class="left">What it measures</th></tr></table>', 'html.parser')
    for k in s.select('.kpis .kpi'):
        v, l = text_of(k.select_one('.v')), keep_inline_html(k.select_one('.l'))
        tbl.table.append(BeautifulSoup(f'<tr><td class="left"><b>{v}</b></td><td class="left">{l}</td></tr>', 'html.parser').tr)
    front.append(tbl.table)
    body.append(front)

    # give chapters ids
    chs = s.select('div.ch')
    for i, ch in enumerate(chs):
        numt = text_of(ch.select_one('.ch-num'))
        ch['data-num'] = numt
        ch['id'] = f'ch-{numt}' if numt != '!' else 'limits'

    # ---- helpers ----
    def emit_figure(el, dest):
        nonlocal fig_n
        fig_n += 1
        fg = BeautifulSoup(recolor(str(el)), 'html.parser').figure
        ft = fg.find('p', class_='fig-t'); fs = fg.find('p', class_='fig-s')
        ftt = text_of(ft) if ft else ''; fst = text_of(fs) if fs else ''
        if ft: ft.extract()
        if fs: fs.extract()
        cap = fg.find('figcaption')
        if cap is None:
            cap = new_tag(out, 'figcaption'); fg.append(cap)
        cap.insert(0, BeautifulSoup(f'<b>Figure {fig_n}: {ftt}.</b> {fst} ', 'html.parser'))
        if fg.has_attr('class'): del fg['class']
        dest.append(fg)

    def emit_table(el, dest, fallback_caption):
        nonlocal tab_n
        tab_n += 1
        tb = BeautifulSoup(str(el), 'html.parser').table
        strip_attrs(tb)
        cap = tb.find('caption')
        if cap is None:
            cap = new_tag(out, 'caption'); tb.insert(0, cap)
            cap.append(BeautifulSoup(f'<b>Table {tab_n}:</b> {fallback_caption}.', 'html.parser'))
        else:
            old = text_of(cap); cap.clear()
            cap.append(BeautifulSoup(f'<b>Table {tab_n}:</b> {old}.', 'html.parser'))
        for cell in tb.find_all(['td', 'th']):
            c = cell.get('class', [])
            if 'n' in c: continue
            cell['class'] = (c if isinstance(c, list) else [c]) + ['left']
        dest.append(tb)

    def emit_chapter(ch, dest):
        nonlocal fig_n, tab_n
        numt = ch['data-num']
        num = int(numt) if numt.isdigit() else None
        osec = new_tag(out, 'section', None)
        htitle = text_of(ch.find('h3'))
        date = text_of(ch.select_one('.ch-date'))
        osec.append(new_tag(out, 'h2', 'sec', (f'{num}. ' if num else '') + htitle, id=ch['id']))
        if date: osec.append(new_tag(out, 'div', 'secmeta', date))
        sub_n = 0
        for el in ch.children:
            if isinstance(el, NavigableString): continue
            cls = el.get('class', [])
            if 'ch-head' in cls: continue
            if el.name == 'div' and 'qlp' in cls:
                for box in el.find_all('div', class_='box', recursive=False):
                    tlab = text_of(box.select_one('.t'))
                    sub_n += 1
                    pre = f'{num}.{sub_n} ' if num else ''
                    osec.append(new_tag(out, 'h3', 'subsec', pre + (tlab[:1].upper() + tlab[1:])))
                    for pp in box.find_all('p', recursive=False):
                        osec.append(BeautifulSoup(str(pp), 'html.parser').p)
                continue
            if el.name == 'div' and 'callout' in cls:
                tlab = el.find('div', class_='t')
                tl = text_of(tlab) if tlab else ''
                if tlab: tlab.extract()
                nb = new_tag(out, 'div', 'pnote')
                nb.append(BeautifulSoup(f'<span class="nt">{tl}.</span> ', 'html.parser'))
                for pp in el.find_all('p', recursive=False):
                    frag = BeautifulSoup(str(pp), 'html.parser').p
                    nb.append(frag)
                osec.append(nb); continue
            if el.name == 'div' and 'src' in cls:
                refs.append((f'ch. {num}' if num else 'closing', text_of(el)))
                sp = new_tag(out, 'p'); sp['style'] = 'font-size:9pt;font-style:italic'
                sp.string = text_of(el); osec.append(sp); continue
            if el.name == 'figure':
                emit_figure(el, osec); continue
            if el.name == 'table':
                emit_table(el, osec, htitle); continue
            osec.append(BeautifulSoup(str(el), 'html.parser'))
        dest.append(osec)

    # ---- ordered walk over div.wrap children ----
    # chapters are siblings after each era header, not children of it: a
    # per-era walk emits all era headings then all chapters and scrambles the
    # order, so walk the wrapper's direct children in document order instead
    wrap = s.select_one('div.wrap')
    items = wrap.find_all(recursive=False)

    # contents
    toc = new_tag(out, 'div', 'toc')
    toc.append(new_tag(out, 'h2', None, 'Contents'))
    ul = new_tag(out, 'ul')
    for el in items:
        cls = el.get('class', [])
        if el.name == 'section' and 'era' in cls:
            eran = text_of(el.select_one('.era-n')); erat = text_of(el.find('h2'))
            el['data-eid'] = f'era-{re.sub(r"[^a-zA-Z0-9]+","-",eran)}'
            li = new_tag(out, 'li'); li['class'] = 'part'
            li.append(new_tag(out, 'a', None, f'{eran} — {erat}', href=f"#{el['data-eid']}"))
            ul.append(li)
        elif el.name == 'div' and 'ch' in cls:
            numt = el['data-num']; t = text_of(el.find('h3'))
            li = new_tag(out, 'li'); li['class'] = 'sub'
            label = (f'{int(numt)}. ' if numt.isdigit() else '') + t
            li.append(new_tag(out, 'a', None, label, href=f"#{el['id']}"))
            ul.append(li)
    li = new_tag(out, 'li'); li['class'] = 'part'
    li.append(new_tag(out, 'a', None, 'References and sourcing', href='#refs')); ul.append(li)
    toc.append(ul); body.append(toc)

    # document body in source order
    for el in items:
        cls = el.get('class', [])
        if el.name == 'header': continue
        if el.name == 'div' and 'foot' in cls: continue
        if el.name == 'figure':
            emit_figure(el, body); continue
        if el.name == 'section' and 'era' in cls:
            eran = text_of(el.select_one('.era-n')); erat = text_of(el.find('h2'))
            ph = new_tag(out, 'div', 'parthead', id=el['data-eid'])
            ph.append(new_tag(out, 'div', 'partno', eran))
            ph.append(new_tag(out, 'h2', None, erat))
            sm = el.select_one('.era-sum')
            if sm:
                pt = new_tag(out, 'p', 'partsum'); pt.append(BeautifulSoup(keep_inline_html(sm), 'html.parser')); ph.append(pt)
            body.append(ph); continue
        if el.name == 'div' and 'ch' in cls:
            emit_chapter(el, body); continue
        if el.name == 'div' and 'grid2' in cls:
            for tier in el.find_all('div', class_='tier', recursive=False):
                h4 = text_of(tier.find('h4')); m = text_of(tier.find('div', class_='m'))
                wi = new_tag(out, 'p', 'wallitem')
                ps = ' '.join(keep_inline_html(pp) for pp in tier.find_all('p', recursive=False))
                wi.append(BeautifulSoup(f'<span class="wk">{h4}</span> ({m}). {ps}', 'html.parser'))
                body.append(wi)
            continue
        if el.name == 'div' and 'rule' in cls:
            nb = new_tag(out, 'div', 'pnote')
            nb.append(BeautifulSoup(keep_inline_html(el), 'html.parser'))
            body.append(nb); continue
        body.append(BeautifulSoup(str(el), 'html.parser'))

    add_refs = build_refs(out, s, refs, footer_sel='.foot',
        lead='Every figure in this document is traceable. The companion sourcing record '
             '(<code>k8s-track-journey/report.md</code>) maps each number to the report that produced it; '
             'the per-chapter sources below are reproduced from the document itself.')
    body.append(add_refs)
    return finish(out)

# =====================================================================
def build_refs(out, s, refs, footer_sel, lead):
    div = new_tag(out, 'div', 'refs', id='refs')
    div.append(new_tag(out, 'h2', None, 'References and sourcing'))
    lp = new_tag(out, 'p'); lp.append(BeautifulSoup(lead, 'html.parser')); div.append(lp)
    ol = new_tag(out, 'ol')
    for label, txt in refs:
        txt = re.sub(r'^Sources?:\s*', '', txt)
        li = new_tag(out, 'li', None, f'({label}) {txt}')
        ol.append(li)
    div.append(ol)
    foot = s.select_one(footer_sel)
    if foot:
        col = new_tag(out, 'div', 'colophon')
        col.append(new_tag(out, 'h2', None, 'Colophon'))
        for pp in foot.find_all('p'):
            fp = new_tag(out, 'p'); fp.append(BeautifulSoup(keep_inline_html(pp), 'html.parser')); col.append(fp)
        if not foot.find_all('p'):
            fp = new_tag(out, 'p'); fp.append(BeautifulSoup(keep_inline_html(foot), 'html.parser')); col.append(fp)
        div.append(col)
    return div

if __name__ == '__main__':
    ch = build_compose()
    open(f'{OUT}/compose-paper.html', 'w').write(ch)
    kh = build_k8s()
    open(f'{OUT}/k8s-paper.html', 'w').write(kh)
    # verification: leftover dark hexes in svg (recolor-completeness scan)
    for name in ('compose-paper', 'k8s-paper'):
        doc = open(f'{OUT}/{name}.html').read()
        dark = set()
        for m in re.finditer(r'#[0-9a-fA-F]{6}\b', doc):
            h = m.group(0).lower()
            r, g, b = int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16)
            if r + g + b < 240 and h not in ('#000000',):
                if h not in ('#1f4e79', '#2e6b34', '#9c6a1a', '#b3362f', '#6d4e87', '#111111', '#444444', '#555555', '#333333'):
                    dark.add(h)
        print(name, 'suspicious dark hexes:', sorted(dark) or 'none')
        print(name, 'figures:', doc.count('<figure'), 'tables:', doc.count('<table'), 'bytes:', len(doc))
