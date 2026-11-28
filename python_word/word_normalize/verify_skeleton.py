#!/usr/bin/env python3
"""Verify the skeleton docx: opens, structure, TOC field integrity, cluster coverage."""
import sys
import zipfile
from collections import Counter

import xml.etree.ElementTree as ET
from lxml import etree as LET

sys.path.insert(0, "/home/dqa/word_norm")
ORIG = "/home/dqa/word_norm/cd261127a9_original.docx"
SKEL = "/home/dqa/word_norm/cd261127a9_skeleton.docx"
W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
A = "http://schemas.openxmlformats.org/drawingml/2006/main"


def q(t):
    return f"{{{W}}}{t}"


def para_sig(p):
    ppr = p.find(q("pPr"))
    d = {}
    if ppr is not None:
        ps_ = ppr.find(q("pStyle"))
        d["st"] = ps_.get(q("val")) if ps_ is not None else "-"
        jc = ppr.find(q("jc"))
        d["jc"] = jc.get(q("val")) if jc is not None else "-"
        ind = ppr.find(q("ind"))
        if ind is not None:
            d["ind"] = ",".join(f"{k.split('}')[1]}={v}" for k, v in sorted(ind.attrib.items()))
    runs = p.findall(q("r"))
    if runs:
        rpr = runs[0].find(q("rPr"))
        r = {}
        if rpr is not None:
            f_ = rpr.find(q("rFonts"))
            if f_ is not None:
                r["f"] = (f_.get(q("ascii")) or "", f_.get(q("eastAsia")) or "")
            sz = rpr.find(q("sz"))
            r["sz"] = sz.get(q("val")) if sz is not None else "-"
            r["b"] = "1" if rpr.find(q("b")) is not None else "0"
            c = rpr.find(q("color"))
            r["c"] = c.get(q("val")) if c is not None else "-"
        d["r"] = tuple(sorted(r.items()))
    return tuple(sorted(d.items()))


def analyze(f, label):
    print(f"\n{'=' * 18} {label} {'=' * 18}")
    from docx import Document
    d = Document(f)
    print(f"python-docx opens OK: {len(d.sections)} sections, {len(d.tables)} tables")
    z = zipfile.ZipFile(f)
    doc = LET.fromstring(z.read("word/document.xml"))
    body = doc.find(q("body"))
    tbls = [ch for ch in body if ch.tag == q("tbl")]
    ps = sum(1 for _ in doc.iter(q("p")))
    blips = doc.findall(f".//{{{A}}}blip")
    instrs = [t.text for t in doc.iter(q("instrText")) if t.text]
    print(f"tables: {len(tbls)}, rows: {[len(t.findall(q('tr'))) for t in tbls]}")
    print(f"paragraphs total: {ps}, images in body: {len(blips)}")
    print(f"fields: {Counter(i.strip().split()[0].upper() for i in instrs)}")
    return doc


doc_o = analyze(ORIG, "ORIGINAL")
doc_s = analyze(SKEL, "SKELETON")

# TOC field integrity in skeleton
cell = None
for tr in doc_s.iter(q("tr")):
    for p in tr.iter(q("p")):
        for it in p.iter(q("instrText")):
            if it.text and it.text.strip().upper().startswith("TOC"):
                for a in p.iterancestors():
                    if a.tag == q("tc"):
                        cell = a
                        break
                break
assert cell is not None, "TOC field not found in skeleton"
flds = [f.get(q("fldCharType")) for f in cell.iter(q("fldChar"))]
depth, ok = 0, True
for ft in flds:
    if ft == "begin":
        depth += 1
    elif ft == "end":
        depth -= 1
    if depth < 0:
        ok = False
print(f"\nTOC cell field chars: {flds}")
print(f"balanced: {depth == 0 and ok}")
print("TOC cell texts:", [t.text for t in cell.iter(q("t"))][:6])

# cluster coverage
co = Counter(para_sig(p) for p in doc_o.iter(q("p")))
cs = Counter(para_sig(p) for p in doc_s.iter(q("p")))
lost = {k: v for k, v in co.items() if k not in cs}
new = {k: v for k, v in cs.items() if k not in co}
print(f"\nclusters: original {len(co)}, skeleton {len(cs)}, lost {len(lost)}, new {len(new)}")
for k, v in sorted(lost.items(), key=lambda kv: -kv[1]):
    print(f"  LOST x{v:4}  {str(k)[:110]}")
for k, v in sorted(new.items(), key=lambda kv: -kv[1]):
    print(f"  NEW  x{v:4}  {str(k)[:110]}")
