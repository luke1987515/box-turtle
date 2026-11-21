#!/usr/bin/env python3
"""Convert the 24-worker RVI ICFs to the customer 1-worker / 24-target form.
Originals are NOT modified; new files: *_1w.icf.
Run as root (reads/writes /root/rvi/icf).
"""
# Provenance: designed & validated by Luke Chen; developed with AI assistance
# (Hermes Agent by Nous Research, self-hosted Qwen model family).
import os, re, sys

ICF = '/root/rvi/icf'
JOBS = (('4K_Random_Writes.icf', '4K_Random_Writes_1w.icf'),
        ('256K_Seq_Writes.icf', '256K_Seq_Writes_1w.icf'))

def conv(src, dst):
    raw = open(src, 'rb').read()
    nl = '\r\n' if b'\r\n' in raw[:4000] else '\n'
    text = raw.decode('utf-8', errors='replace')
    mstart = text.index("'MANAGER LIST")
    head = text[:mstart]
    wmatch = re.search(r"'Worker\r?\n", text[mstart:])
    mgr_header = text[mstart:mstart + wmatch.start()]

    first = re.search(r"'Worker\r?\n\tWorker 1(.*?)\r?\n'End worker", text, re.S)
    if not first:
        raise SystemExit('FATAL: no Worker 1 block in %s' % src)
    first = first.group(0)

    tnames = re.findall(r"'Target\r?\n\t(\S+)\r?\n'Target type", text)
    if len(tnames) != 24:
        raise SystemExit('FATAL: expected 24 targets in %s, got %d: %s' % (src, len(tnames), tnames))

    tgt = ''.join(("'Target" + nl + "\t" + t + nl +
                   "'Target type" + nl + "\tDISK" + nl +
                   "'End target" + nl) for t in tnames)

    newfirst, n = re.subn(r"'Target assignments.*?'End target assignments",
                          "'Target assignments" + nl + tgt + "'End target assignments",
                          first, count=1, flags=re.S)
    if n != 1:
        raise SystemExit('FATAL: target section not replaced in %s' % src)

    tail = text[text.rindex("'END manager list"):]
    out = head + mgr_header + newfirst + nl + "'End manager" + nl + tail
    open(dst, 'w', newline='').write(out)

    # verify
    chk = open(dst, 'rb').read().decode('utf-8', errors='replace')
    nw = len(re.findall(r"'Worker\r?\n", chk))
    nt = len(re.findall(r"'Target\r?\n\t(\S+)\r?\n'Target type", chk))
    spec = re.search(r"'Assigned access specs\r?\n(\S[^\n]*)\r?\n'End assigned access specs", chk)
    print('OK %s -> %s  workers=%d targets=%d spec=%r head_same=%s'
          % (src, dst, nw, nt, spec.group(1) if spec else None,
             chk[:mstart] == head))
    if nw != 1 or nt != 24:
        raise SystemExit('FATAL: verification failed for %s' % dst)

for s, d in JOBS:
    conv(os.path.join(ICF, s), os.path.join(ICF, d))
print('MAKE_1W_DONE')
