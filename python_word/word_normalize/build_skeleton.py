#!/usr/bin/env python3
"""Build the A9 skeleton docx from cd261127a9_original.docx.

Goal: keep the full formatting vocabulary (all cluster types, table shapes,
styles, sections, header/footer, cover) but cut content to 1-3 representative
rows per table; clear the TOC cached results (keep the field); keep 1 of 3
DUT images.

Output: cd261127a9_skeleton.docx
"""
import copy
import os
import sys
import zipfile

from lxml import etree

SRC = "cd261127a9_original.docx"
DST = "cd261127a9_skeleton.docx"

W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
A = "http://schemas.openxmlformats.org/drawingml/2006/main"

NS = {"w": W, "r": R, "a": A}


def q(tag):
    return f"{{{W}}}{tag}"


def para_sig(p):
    """Formatting signature of a paragraph (coarse, for cluster coverage)."""
    ppr = p.find(q("pPr"))
    d = {}
    if ppr is not None:
        ps = ppr.find(q("pStyle"))
        d["st"] = ps.get(q("val")) if ps is not None else "-"
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
            f = rpr.find(q("rFonts"))
            if f is not None:
                r["f"] = (f.get(q("ascii")) or "", f.get(q("eastAsia")) or "")
            sz = rpr.find(q("sz"))
            r["sz"] = sz.get(q("val")) if sz is not None else "-"
            r["b"] = "1" if rpr.find(q("b")) is not None else "0"
            c = rpr.find(q("color"))
            r["c"] = c.get(q("val")) if c is not None else "-"
        d["r"] = tuple(sorted(r.items()))
    return tuple(sorted(d.items()))


def row_sig(tr):
    return frozenset(para_sig(p) for p in tr.iter(q("p")))


def has_blue(tr):
    for c in tr.iter(q("color")):
        if c.get(q("val")) in ("0000FF", "blue"):
            return True
    return False


def row_text(tr):
    return "".join(t.text or "" for t in tr.iter(q("t")))


def keep_rows(tbl, keep_idx=(), cap=8):
    """Keep rows: row0, explicit keep_idx, first H2 row, first blue row,
    then greedy cluster coverage up to `cap` total kept rows."""
    rows = tbl.findall(q("tr"))
    keep = {0}
    for i in keep_idx:
        keep.add(i)
    # first H2 row
    for i, tr in enumerate(rows):
        if any(p.find(f"{q('pPr')}/{q('pStyle')}") is not None and
               p.find(f"{q('pPr')}/{q('pStyle')}").get(q("val")) == "2"
               for p in tr.iter(q("p"))):
            keep.add(i)
            break
    # first blue row
    for i, tr in enumerate(rows):
        if has_blue(tr):
            keep.add(i)
            break
    # greedy cluster coverage
    covered = set()
    for i in sorted(keep):
        covered |= row_sig(rows[i])
    for i, tr in enumerate(rows):
        if i in keep or len(keep) >= cap:
            continue
        s = row_sig(tr)
        if s - covered:
            keep.add(i)
            covered |= s
    for i, tr in enumerate(rows):
        if i not in keep:
            tbl.remove(tr)
    return sorted(keep)


def main():
    zin = zipfile.ZipFile(SRC)
    doc = etree.fromstring(zin.read("word/document.xml"))
    body = doc.find(q("body"))
    tops = list(body)
    tbls = [ch for ch in tops if ch.tag == q("tbl")]
    assert len(tbls) == 10, f"expected 10 tables, got {len(tbls)}"

    # ---- TBL3 (mega table, 104 rows): explicit keep list ----
    t3 = tbls[3]
    rows3 = t3.findall(q("tr"))
    # find a blue row among 1.1 config rows (45..92) for cluster coverage
    blue_idx = next((i for i in range(45, 93) if has_blue(rows3[i])), None)
    explicit3 = [0, 1, 2, 7, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23,
                 27, 28, 29, 43, 45, 46, 47, 48, 93, 94, 95, 98, 99, 100]
    if blue_idx is not None:
        explicit3.append(blue_idx)
    keep3 = set([0]) | set(explicit3)
    for i, tr in enumerate(rows3):
        if i not in keep3:
            t3.remove(tr)

    # ---- TOC surgery on TBL3 row 17 (now still index: find row containing TOC instr) ----
    for tr in t3.iter(q("tr")):
        for p in tr.iter(q("p")):
            for it in p.iter(q("instrText")):
                if it.text and it.text.strip().upper().startswith("TOC"):
                    toc_p = p
                    break
            else:
                continue
            break
        else:
            continue
        break
    # find the cell containing toc_p
    cell = None
    for anc in toc_p.iterancestors():
        if anc.tag == q("tc"):
            cell = anc
            break
    paras = cell.findall(q("p"))
    toc_pos = paras.index(toc_p)
    # toc_p: keep pPr + children up to and including the run carrying the first
    # fldChar:separate; delete ALL later children (runs AND w:hyperlink wrappers —
    # TOC \h nests the first entry's PAGEREF field inside a hyperlink element)
    children = list(toc_p)
    cut = None
    for i, ch in enumerate(children):
        if ch.tag == q("r") and any(
            f.get(q("fldCharType")) == "separate" for f in ch.findall(q("fldChar"))
        ):
            cut = i
            break
    assert cut is not None, "TOC fldChar separate not found in toc paragraph"
    for ch in children[cut + 1:]:
        toc_p.remove(ch)
    # delete cached toc entry paragraphs (between toc_p and the FINAL fldChar:end
    # para — the TOC field close; intermediate paras carry their own PAGEREF ends)
    final_end = None
    for p in paras[toc_pos + 1:]:
        if any(f.get(q("fldCharType")) == "end" for f in p.iter(q("fldChar"))):
            final_end = p
    assert final_end is not None, "final TOC fldChar end not found"
    for p in paras[toc_pos + 1: paras.index(final_end)]:
        cell.remove(p)

    # ---- TBL4 (11 rows), TBL5 (6 rows): keep 0-3 ----
    keep_rows(tbls[4], keep_idx=[1, 2, 3], cap=4)
    keep_rows(tbls[5], keep_idx=[1, 2, 3], cap=4)

    # ---- TBL6: DUT images row: drop 2 of 3 drawings (keep rId12) ----
    t6cell = tbls[6].find(f"{q('tr')}/{q('tc')}")
    for drawing in list(t6cell.iter(q("drawing"))):
        blips = drawing.findall(f".//{{{A}}}blip")
        if any(b.get(f"{{{R}}}embed") in ("rId13", "rId14") for b in blips):
            parent = drawing.getparent()
            # remove the enclosing w:r if the drawing is the only meaningful content
            parent.remove(drawing)

    # ---- chapter tables TBL7/8/9: row0 + first H2 + first blue + greedy ----
    keep_rows(tbls[7], cap=8)
    keep_rows(tbls[8], cap=8)
    keep_rows(tbls[9], cap=8)

    # ---- rels: drop rId13/rId14 ----
    rels = etree.fromstring(zin.read("word/_rels/document.xml.rels"))
    for rel in list(rels):
        if rel.get("Id") in ("rId13", "rId14"):
            rels.remove(rel)

    # ---- write new zip ----
    new_doc = etree.tostring(doc, xml_declaration=True, encoding="UTF-8", standalone=True)
    new_rels = etree.tostring(rels, xml_declaration=True, encoding="UTF-8", standalone=True)
    drop_media = {"word/media/image4.png", "word/media/image5.jpeg"}

    with zipfile.ZipFile(DST, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            if item.filename in drop_media:
                continue
            data = zin.read(item.filename)
            if item.filename == "word/document.xml":
                data = new_doc
            elif item.filename == "word/_rels/document.xml.rels":
                data = new_rels
            zout.writestr(item, data)
    print(f"wrote {DST} ({os.path.getsize(DST)} bytes, src {os.path.getsize(SRC)})")


if __name__ == "__main__":
    main()
