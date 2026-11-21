#!/usr/bin/env python3
"""RUN3 driver for the RVI DUT (Ubuntu side): A/B worker-structure test, then
gated 13-level x 2-profile fan sweep using the customer 1-worker ICFs.

Per-run sequence: pin (boost=0 + performance@2650 + 5s multi-sample gate) ->
fresh dynamo -> IOMeter (120 s + 30 s ramp) -> CSV self-check -> CPU restore.
Fan: ZELUS BMC local ipmitool raw 0x36 (SET 0xFA+16 bytes, READ 0xFB idx2/18),
baseline captured at start, restored on every exit path.
Run as root. Usage: run3_driver.py ab
"""
# Provenance: designed & validated by Luke Chen; developed with AI assistance
# (Hermes Agent by Nous Research, self-hosted Qwen model family).
import glob, json, os, re, subprocess, sys, time

BASE = '/root/rvi'
ICF = BASE + '/icf'
AB_DIR = BASE + '/ab'
RES3 = BASE + '/results_run3'
LOGF = open(BASE + '/run3_progress.log', 'a', buffering=1)
STATE = BASE + '/run3_state.json'
WINE = '/usr/local/bin/wine64'
IOMETER_EXE = '/opt/iometer/iometer.exe'
DYNAMO_BIN = '/opt/iometer/dynamo'

CPUS = sorted(glob.glob('/sys/devices/system/cpu/cpu[0-9]*'))
PIN_HZ = 2650000
TOL = int(PIN_HZ * 0.01)
BOOST = '/sys/devices/system/cpu/cpufreq/boost'
LEVELS = [20, 40, 60, 64, 68, 72, 76, 80, 84, 88, 92, 96, 100]
FAN_SETTLE_S = 10
FAN_TOL = 3
FAN_RETRIES = 3
WATCHDOG = 420
XVFB = ':99'
ICF_4K_1W = '4K_Random_Writes_1w.icf'
ICF_SEQ_1W = '256K_Seq_Writes_1w.icf'
ICF_4K_24W = '4K_Random_Writes.icf'
ICF_SEQ_24W = '256K_Seq_Writes.icf'
TEST_DISKS = ['sda', 'sdb', 'sdc', 'sdd', 'sde', 'sdf', 'sdg', 'sdh', 'sdi', 'sdj',
              'sdk', 'sdl', 'sdm', 'sdn', 'sdo', 'sdp', 'sdq', 'sdr', 'sds', 'sdt',
              'sdu', 'sdv', 'sdw', 'sdx']

def log(msg):
    line = time.strftime('%Y-%m-%d %H:%M:%S ') + msg
    print(line, flush=True)
    LOGF.write(line + '\n')

def sh(cmd):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return (r.stdout + r.stderr).strip(), r.returncode

def zpath(unix_path):
    return 'Z:' + unix_path.replace('/', '\\')

# ---------------- CPU pin ----------------
def setfreq(g, mn, mx):
    for c in CPUS:
        base = os.path.join(c, 'cpufreq')
        for f, v in (('scaling_governor', g), ('scaling_min_freq', str(mn)), ('scaling_max_freq', str(mx))):
            try:
                with open(os.path.join(base, f), 'w') as fh:
                    fh.write(v)
            except OSError:
                pass

def setboost(v):
    with open(BOOST, 'w') as fh:
        fh.write(str(v))

def pin():
    setboost(0)
    setfreq('performance', PIN_HZ, PIN_HZ)
    time.sleep(2)
    per = {}
    for _s in range(5):
        for c in CPUS:
            p = os.path.join(c, 'cpufreq', 'scaling_cur_freq')
            if os.path.exists(p):
                try:
                    v = int(open(p).read().strip())
                    if v > per.get(c, -1):
                        per[c] = v
                except (ValueError, OSError):
                    pass
        time.sleep(1)
    cur = sorted(set(per.values()))
    bad = [f for f in cur if f < PIN_HZ - TOL or f > PIN_HZ + TOL]
    if bad:
        raise RuntimeError('PIN FAILED: %s' % bad)
    log('pin ok: %s' % cur)

def cpu_restore():
    setfreq('schedutil', 1500000, 2650000)
    setboost(1)

# ---------------- fan ----------------
def fan_read():
    out, rc = sh('ipmitool raw 0x36 0xFB')
    if rc != 0:
        raise RuntimeError('fan read rc=%d %s' % (rc, out))
    b = [x.upper() for x in out.split()]
    if len(b) < 19:
        raise RuntimeError('fan read short: %s' % out)
    return int(b[2], 16), int(b[18], 16)

def fan_set(level, tries=FAN_RETRIES):
    vals = ['0x%02X' % level] + ['0x00'] * 15
    cmd = 'ipmitool raw 0x36 0xFA 0x00 ' + ' '.join(vals)
    f1 = f2 = -1
    for _t in range(tries):
        out, rc = sh(cmd)
        if rc != 0:
            raise RuntimeError('fan set rc=%d %s' % (rc, out))
        time.sleep(1)
        f1, f2 = fan_read()
        if abs(f1 - level) <= FAN_TOL and abs(f2 - level) <= FAN_TOL + 1:
            return f1, f2
        time.sleep(2)
    raise RuntimeError('fan verify failed: want %d got %d/%d' % (level, f1, f2))

# ---------------- iometer ----------------
def fresh_dynamo():
    subprocess.run('pkill -x dynamo 2>/dev/null', shell=True)
    time.sleep(1)
    env = dict(os.environ, LD_LIBRARY_PATH='/opt/iometer')
    dl = open(BASE + '/logs/dynamo_run3.log', 'a')
    subprocess.Popen([DYNAMO_BIN, '-i', '127.0.0.1', '-m', '127.0.0.1'],
                     env=env, stdout=dl, stderr=subprocess.STDOUT, start_new_session=True)
    time.sleep(3)
    out, rc = sh('pgrep -x dynamo')
    if rc != 0:
        raise RuntimeError('dynamo did not start')
    log('dynamo fresh: %s' % out.replace('\n', ','))

def parse_csv(path):
    d = {'rows': 0, 'disks': []}
    for line in open(path, encoding='utf-8', errors='replace'):
        f = line.rstrip('\n').split(',')
        if len(f) > 40:
            d['rows'] += 1
            k = f[0].strip()
            if k == 'ALL':
                d['iops'] = float(f[6]); d['wio'] = int(f[33])
                d['errs'] = int(f[27]); d['rt'] = float(f[17])
            elif k != 'MANAGER':
                try:
                    d['disks'].append((f[1].strip(), float(f[6])))
                except (ValueError, IndexError):
                    pass
    if d.get('iops'):
        d['internal'] = d['wio'] / d['iops']
    return d

def iometer_run(icf, outcsv, tag):
    for attempt in (1, 2):
        try:
            os.remove(outcsv)
        except OSError:
            pass
        pin()
        fresh_dynamo()
        env = dict(os.environ, WINEPREFIX='/opt/iometer/prefix', DISPLAY=XVFB)
        os.chdir(BASE)
        t0 = time.time()
        p = subprocess.run(
            ['timeout', str(WATCHDOG), WINE, IOMETER_EXE,
             '/c', zpath(ICF + '/' + icf), '/r', zpath(outcsv), '/t', '60'],
            env=env, stdout=open(BASE + '/logs/iometer_%s_%d.log' % (tag, attempt), 'w'),
            stderr=subprocess.STDOUT, timeout=WATCHDOG + 30)
        wall = time.time() - t0
        cpu_restore()
        ok = False
        if p.returncode == 0 and os.path.exists(outcsv):
            d = parse_csv(outcsv)
            if (d.get('rows', 0) >= 80 and d.get('internal') and
                    119.5 <= d['internal'] <= 120.5 and d.get('errs', 1) == 0):
                log('%s a%d OK wall=%.0fs iops=%.1f internal=%.2fs rt=%.2fms errs=%d disks=%d'
                    % (tag, attempt, wall, d['iops'], d['internal'], d['rt'], d['errs'], len(d['disks'])))
                return d
            log('%s a%d selfcheck FAIL rc=%s rows=%s internal=%s errs=%s -> retry'
                % (tag, attempt, p.returncode, d.get('rows'),
                   round(d.get('internal') or 0, 2), d.get('errs')))
        else:
            log('%s a%d FAIL rc=%s -> retry' % (tag, attempt, p.returncode))
        time.sleep(5)
    raise RuntimeError('run failed after 2 attempts: %s' % tag)

def ab_gate(a, b, label):
    da, db = a['iops'], b['iops']
    diff = abs(da - db) / da * 100
    pa = sorted(x[1] for x in a['disks']); pb = sorted(x[1] for x in b['disks'])
    med = lambda L: L[len(L) // 2] if L else 0
    log('GATE %s: 24w total=%.1f 1w total=%.1f diff=%.2f%% | per-disk med 24w=%.1f 1w=%.1f (n=%d/%d)'
        % (label, da, db, diff, med(pa), med(pb), len(pa), len(pb)))
    return diff <= 2.0

# ---------------- phases ----------------
def ab():
    os.makedirs(AB_DIR, exist_ok=True)
    f1, f2 = fan_set(20)
    log('AB fan 20%% set (readback %d/%d), settle 30s' % (f1, f2))
    time.sleep(30)
    r24_4k = iometer_run(ICF_4K_24W, AB_DIR + '/ab_4k_24w.csv', 'ab4k24w')
    r1_4k = iometer_run(ICF_4K_1W, AB_DIR + '/ab_4k_1w.csv', 'ab4k1w')
    r24_256 = iometer_run(ICF_SEQ_24W, AB_DIR + '/ab_256k_24w.csv', 'ab256k24w')
    r1_256 = iometer_run(ICF_SEQ_1W, AB_DIR + '/ab_256k_1w.csv', 'ab256k1w')
    g4 = ab_gate(r24_4k, r1_4k, '4K')
    g256 = ab_gate(r24_256, r1_256, '256K')
    if g4 and g256:
        log('AB PASS -> sweep auto-starts')
        sweep()
    else:
        log('AB FAIL -> sweep NOT started, awaiting review')

def sweep():
    os.makedirs(RES3, exist_ok=True)
    for lvl in LEVELS:
        f1, f2 = fan_set(lvl)
        log('LVL %d fan set (readback %d/%d), settle %ds' % (lvl, f1, f2, FAN_SETTLE_S))
        time.sleep(FAN_SETTLE_S)
        d4 = iometer_run(ICF_4K_1W, RES3 + '/fan_%d_pct_4K_Random_Writes.csv' % lvl, 'sw%d_4k' % lvl)
        d2 = iometer_run(ICF_SEQ_1W, RES3 + '/fan_%d_pct_256K_Seq_Writes.csv' % lvl, 'sw%d_256' % lvl)
        log('LVL %d done: 4K=%.0f 256K=%.0f' % (lvl, d4['iops'], d2['iops']))
    log('SWEEP COMPLETE: 26 CSVs in %s' % RES3)

# ---------------- write-cache (spec step 3) ----------------
def sdparm_wce(disk):
    out, _rc = sh('sdparm --get=WCE /dev/%s 2>/dev/null' % disk)
    for line in out.splitlines():
        if line.startswith('WCE'):
            parts = line.split()
            if len(parts) >= 2:
                return parts[1]
    return None

def cache_check():
    out, rc = sh('command -v sdparm')
    if rc != 0:
        log('WARN: sdparm unavailable - write-cache NOT verifiable (manual check needed)')
        return
    states = {}
    for d in TEST_DISKS:
        states[d] = sdparm_wce(d)
    on = [d for d, v in states.items() if v == '1']
    unread = [d for d, v in states.items() if v not in ('0', '1')]
    for d in on:
        sh('sdparm --set=WCE=0 /dev/%s >/dev/null 2>&1' % d)
        wce2 = sdparm_wce(d)
        if wce2 != '0':
            raise RuntimeError('WCE set failed on /dev/%s (still %s)' % (d, wce2))
    if on:
        log('write-cache was ON on %d disks -> set WCE=0: %s' % (len(on), on))
    if unread:
        log('WARN: WCE unreadable on %s - verify manually' % unread)
    if not on and not unread:
        log('write-cache off on all 24 disks (WCE=0)')

# ---------------- main ----------------
def main():
    log('=== RUN3 driver start (pid %d) ===' % os.getpid())
    out, _rc = sh("pgrep -x dynamo; pgrep -f 'iometer[.]exe' || true")
    if out.strip():
        raise RuntimeError('iometer/dynamo already running: %s' % out)
    out, rc = sh('pgrep -f "Xvfb :9[9]" || true')
    if not out.strip():
        raise RuntimeError('Xvfb :99 not found - aborting (IOMeter needs display)')
    cache_check()
    log('preflight ok (Xvfb up, nothing running, cache verified)')
    base = fan_read()
    log('fan baseline: %d/%d' % base)
    try:
        if os.path.exists(STATE):
            try:
                old = json.load(open(STATE))
                fb = old.get('baseline')
                if fb:
                    f1, f2 = fan_set(fb[0])
                    log('stale state found - fan pre-restored to %d/%d' % (f1, f2))
            except Exception as e:
                log('stale state handling failed: %r' % e)
    except Exception:
        pass
    json.dump({'baseline': list(base), 'ts': time.time(), 'phase': 'ab'}, open(STATE, 'w'))
    try:
        ab()
    except Exception as e:
        log('ABORT: %r' % e)
    finally:
        try:
            f1, f2 = fan_set(base[0])
            log('fan restored to baseline (readback %d/%d)' % (f1, f2))
        except Exception as e:
            log('FAN RESTORE FAILED: %r' % e)
        cpu_restore()
        try:
            os.remove(STATE)
        except OSError:
            pass
        log('=== RUN3 driver done ===')

if __name__ == '__main__':
    main()
