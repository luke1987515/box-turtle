#!/usr/bin/env python3
"""Compare original.docx vs rebuilt.docx: text, structure, parts.

Usage: compare.py [original.docx] [rebuilt.docx]
"""
import sys
import zipfile
from lxml import etree

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'


def all_texts(path):
    z = zipfile.ZipFile(path)
    out = []
    for part in sorted(z.namelist()):
        if part.endswith('.xml') and (
            'document' in part or 'header' in part or 'footer' in part
            or 'footnote' in part or 'endnote' in part):
            root = etree.fromstring(z.read(part))
            for t in root.iter(f'{{{W}}}t'):
                out.append((part, t.text or ''))
    return out


def struct(path):
    z = zipfile.ZipFile(path)
    root = etree.fromstring(z.read('word/document.xml'))
    c = lambda tag: len(list(root.iter(f'{{{W}}}{tag}')))
    return {
        'p': c('p'), 'tbl': c('tbl'), 'tr': c('tr'), 'tc': c('tc'),
        'gridSpan': len(list(root.iter(f'{{{W}}}gridSpan'))),
        'vMerge': len(list(root.iter(f'{{{W}}}vMerge'))),
        'drawing': c('drawing'), 'hyperlink': c('hyperlink'),
        'sectPr': c('sectPr'), 'fldChar': c('fldChar'),
        'br': c('br'), 'tab': c('tab'),
    }


def parts(path):
    z = zipfile.ZipFile(path)
    return {i.filename: z.read(i.filename) for i in z.infolist()}


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else 'original.docx'
    out = sys.argv[2] if len(sys.argv) > 2 else 'rebuilt.docx'

    orig_texts = all_texts(src)
    new_texts = all_texts(out)
    print('== TEXT ==')
    print('text nodes orig:', len(orig_texts), 'rebuilt:', len(new_texts))
    same = orig_texts == new_texts
    print('ALL TEXT IDENTICAL (incl. order):', same)
    if not same:
        for i, (a, b) in enumerate(zip(orig_texts, new_texts)):
            if a != b:
                print(f'first diff at node {i}: {a!r} vs {b!r}')
                break

    print('== STRUCTURE (document.xml) ==')
    so, sn = struct(src), struct(out)
    for k in so:
        mark = 'OK ' if so[k] == sn[k] else 'DIFF'
        print(f'{mark} {k}: orig={so[k]} rebuilt={sn[k]}')

    print('== ZIP PARTS ==')
    po, pn = parts(src), parts(out)
    for name in sorted(set(po) | set(pn)):
        if name not in po:
            print('NEW  ', name)
        elif name not in pn:
            print('MISS ', name)
        elif po[name] == pn[name]:
            print('same ', name)
        else:
            print('DIFF ', name, f'({len(po[name])} -> {len(pn[name])} bytes)')

    import docx
    d = docx.Document(out)
    print('== python-docx ==')
    print('opened OK: paragraphs=', len(d.paragraphs),
          'tables=', len(d.tables))


if __name__ == '__main__':
    main()
