#!/usr/bin/env python3
"""Parse original.docx into a content model (content.json).

Model = everything a generator needs to re-emit the document body in
order: paragraphs (pPr + runs), tables (tblPr/grid/rows/cells), fields,
images, hyperlinks. Invisible elements (bookmarkStart/End, proofErr)
are deliberately dropped — they don't affect rendering or text.
"""
import json
import sys
import zipfile
from lxml import etree

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'


def raw(el):
    return None if el is None else etree.tostring(el, encoding='unicode')


def parse_run(r):
    """A run: rPr + ordered parts. Parts: ('t', text) or ('raw', xml)."""
    parts = []
    for ch in r:
        ln = etree.QName(ch).localname
        if ln == 't':
            parts.append(['t', ch.text or ''])
        elif ln == 'lastRenderedPageBreak':
            continue  # invisible rendering hint
        else:
            parts.append(['raw', raw(ch)])
    return {'rPr': raw(r.find(f'{{{W}}}rPr')), 'parts': parts}


def parse_p_children(p):
    """Ordered content of a paragraph (after pPr)."""
    out = []
    for ch in p:
        ln = etree.QName(ch).localname
        if ln == 'pPr':
            continue
        if ln == 'r':
            out.append(['run', parse_run(ch)])
        elif ln in ('hyperlink', 'smartTag', 'sdt'):
            out.append(['raw', raw(ch)])  # atomic component
        elif ln in ('bookmarkStart', 'bookmarkEnd', 'proofErr'):
            continue  # invisible
        else:
            out.append(['raw', raw(ch)])  # preserve anything unexpected
    return out


def parse_p(p):
    return {'type': 'p', 'pPr': raw(p.find(f'{{{W}}}pPr')),
            'content': parse_p_children(p)}


def parse_table(tbl):
    rows = []
    for tr in tbl.findall(f'{{{W}}}tr'):
        cells = []
        tblprex = tr.find(f'{{{W}}}tblPrEx')
        for tc in tr.findall(f'{{{W}}}tc'):
            items = []
            for ch in tc:
                ln = etree.QName(ch).localname
                if ln == 'tblPrEx':
                    continue
                if ln == 'tcPr':
                    continue
                if ln == 'p':
                    items.append(parse_p(ch))
                elif ln == 'tbl':
                    items.append(parse_table(ch))
                else:
                    items.append(['raw', raw(ch)])
            cells.append({'tcPr': raw(tc.find(f'{{{W}}}tcPr')), 'items': items})
        rows.append({'trPr': raw(tr.find(f'{{{W}}}trPr')),
                     'tblPrEx': raw(tblprex), 'cells': cells})
    return {'type': 'tbl',
            'tblPr': raw(tbl.find(f'{{{W}}}tblPr')),
            'tblGrid': raw(tbl.find(f'{{{W}}}tblGrid')),
            'rows': rows}


def parse_item(el):
    ln = etree.QName(el).localname
    if ln == 'p':
        return parse_p(el)
    if ln == 'tbl':
        return parse_table(el)
    raise ValueError(f'unexpected: {ln}')


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else 'original.docx'
    with zipfile.ZipFile(src) as z:
        doc = etree.fromstring(z.read('word/document.xml'))
    body = doc.find(f'{{{W}}}body')
    items = []
    body_sectpr = None
    for ch in body:
        ln = etree.QName(ch).localname
        if ln == 'sectPr':
            body_sectpr = raw(ch)
        else:
            items.append(parse_item(ch))
    model = {'items': items, 'body_sectPr': body_sectpr}
    with open('content.json', 'w', encoding='utf-8') as f:
        json.dump(model, f, ensure_ascii=False, separators=(',', ':'))

    # stats
    stats = {'p': 0, 'tbl': 0, 'rows': 0, 'cells': 0, 'runs': 0,
             't_parts': 0, 'raw_parts': 0, 'chars': 0}

    def visit(item):
        if isinstance(item, dict):
            if item.get('type') == 'p':
                stats['p'] += 1
                for c in item['content']:
                    if c[0] == 'run':
                        stats['runs'] += 1
                        for kind, val in c[1]['parts']:
                            if kind == 't':
                                stats['t_parts'] += 1
                                stats['chars'] += len(val)
                            else:
                                stats['raw_parts'] += 1
            elif item.get('type') == 'tbl':
                stats['tbl'] += 1
                for row in item['rows']:
                    stats['rows'] += 1
                    stats['cells'] += len(row['cells'])
                    for cell in row['cells']:
                        for it in cell['items']:
                            visit(it)
        elif isinstance(item, list):
            for it in item:
                visit(it)

    for it in items:
        visit(it)
    print(json.dumps(stats))
    print('wrote content.json')


if __name__ == '__main__':
    main()
