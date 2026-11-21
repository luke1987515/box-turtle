#!/bin/bash
# =============================================================================
# setup_fresh_dut.sh — one-shot bootstrap of a FRESH Ubuntu Server into a
# ready-to-run RVI test DUT (IOMeter under Wine + 24-disk fan sweep).
#
# What it does (run as root):
#   1. apt: wine64 xvfb ipmitool sdparm smartmontools git python3
#      python3-openpyxl file curl unzip bzip2
#   2. IOMeter 1.1.0 binaries into /opt/iometer:
#        default       : download the official SourceForge releases and
#                        verify their SHA256 (iometer.org download page)
#      --from-dut U@IP : scp them from an existing DUT instead (same-LAN
#                        shortcut; the source files are world-readable)
#   3. Clone box-turtle, install the RVI pipeline into /root/rvi
#   4. Auto-detect the data disks, write TEST_DISKS into rvi.conf,
#      regenerate all ICFs (24-worker + customer 1-worker) to match
#   5. BMC fan readback probe (warn-only; preflight enforces for real)
#   6. Run 00_preflight.sh (incl. the 60 s 24-disk batch-mode smoke)
#      unless --no-preflight
#
# Xvfb policy (deliberate, no systemd unit): the pipeline scripts start
# Xvfb :99 on demand (ensure_xvfb in 20_iometer_run.sh / run3_driver.py).
# After any reboot, investigate first, then just re-run the sweep script.
#
# Usage:
#   bash setup_fresh_dut.sh                       # download + preflight
#   bash setup_fresh_dut.sh --from-dut dqa@192.168.0.5
#   bash setup_fresh_dut.sh --no-preflight        # install only
#
# Provenance: designed & validated by Luke Chen; developed with AI assistance
# (Hermes Agent by Nous Research, self-hosted Qwen model family).
# =============================================================================
set -u

SF_URL_BASE="https://downloads.sourceforge.net/project/iometer/iometer-stable/1.1.0"
SF_WIN="iometer-1.1.0-win64.x86_64-bin.zip"
SF_WIN_SHA256="ba0265efe61ead451f34eba0dce022c9d83ddf7232934eb59252eda48c1509bf"
SF_LINUX="iometer-1.1.0-linux.x86_64-bin.tar.bz2"
SF_LINUX_SHA256="2249664266454be9350caa515f22b72032db6c5be87c66165f44696c0343b24c"
REPO_URL="https://github.com/luke1987515/box-turtle.git"

step() { echo; echo "===== $* ====="; }
die()  { echo; echo "FATAL: $*" >&2; exit 1; }

FROM_DUT=""
RUN_PREFLIGHT=1
while [ $# -gt 0 ]; do
    case "$1" in
        --from-dut)
            [ $# -ge 2 ] || die "--from-dut needs a user@host argument"
            FROM_DUT="$2"; shift 2 ;;
        --no-preflight) RUN_PREFLIGHT=0; shift ;;
        -h|--help)
            sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $1 (see --help)" ;;
    esac
done

# --- 1. Sanity ------------------------------------------------------------------
[ "$(id -u)" = 0 ] || die "run as root"
OS_LINE=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")
case "$OS_LINE" in
    *"24.04"*) echo "OS ok: $OS_LINE" ;;
    *) echo "WARN: expected Ubuntu 24.04, got: $OS_LINE — continuing (untested combo)" ;;
esac

# --- 2. apt packages -------------------------------------------------------------
step "Installing apt packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq wine64 xvfb ipmitool sdparm smartmontools git \
    python3 python3-openpyxl file curl unzip bzip2 || die "apt install failed"

# --- 3. IOMeter 1.1.0 binaries ----------------------------------------------------
step "IOMeter 1.1.0 binaries (/opt/iometer)"
mkdir -p /opt/iometer
need_win=0; need_linux=0
if ! { [ -f /opt/iometer/iometer.exe ] \
       && file /opt/iometer/iometer.exe | grep -q 'PE32+' \
       && file /opt/iometer/iometer.exe | grep -q 'x86-64'; }; then need_win=1; fi
if ! { [ -f /opt/iometer/dynamo ] \
       && file /opt/iometer/dynamo | grep -q 'ELF 64-bit'; }; then need_linux=1; fi

if [ "$need_win" = 0 ] && [ "$need_linux" = 0 ]; then
    echo "iometer.exe + dynamo already in place and verified — skipping fetch"
else
    if [ -n "$FROM_DUT" ]; then
        echo "Fetching binaries from existing DUT: $FROM_DUT (scp may ask for a password)"
        [ "$need_win" = 1 ] && scp "$FROM_DUT:/opt/iometer/iometer.exe" /opt/iometer/iometer.exe \
            || die "scp iometer.exe from $FROM_DUT failed"
        [ "$need_linux" = 1 ] && scp "$FROM_DUT:/opt/iometer/dynamo" /opt/iometer/dynamo \
            || die "scp dynamo from $FROM_DUT failed"
        scp "$FROM_DUT:/opt/iometer/libaio.so.1" /opt/iometer/libaio.so.1 2>/dev/null \
            || echo "(source has no bundled libaio.so.1 — system libaio will be used)"
    else
        echo "Downloading official IOMeter 1.1.0 from SourceForge (SHA256-verified)"
        TMPD=$(mktemp -d)
        if [ "$need_win" = 1 ]; then
            curl -fL --retry 3 -o "$TMPD/$SF_WIN" "$SF_URL_BASE/$SF_WIN" || die "download failed: $SF_WIN"
            echo "$SF_WIN_SHA256  $TMPD/$SF_WIN" | sha256sum -c - >/dev/null \
                || die "SHA256 MISMATCH: $SF_WIN (file on SourceForge changed?)"
            unzip -q -o "$TMPD/$SF_WIN" -d "$TMPD/win" || die "unzip failed"
            exe=$(find "$TMPD/win" -iname 'iometer.exe' -type f | head -1)
            [ -n "$exe" ] || die "Iometer.exe not found inside $SF_WIN"
            cp "$exe" /opt/iometer/iometer.exe
        fi
        if [ "$need_linux" = 1 ]; then
            curl -fL --retry 3 -o "$TMPD/$SF_LINUX" "$SF_URL_BASE/$SF_LINUX" || die "download failed: $SF_LINUX"
            echo "$SF_LINUX_SHA256  $TMPD/$SF_LINUX" | sha256sum -c - >/dev/null \
                || die "SHA256 MISMATCH: $SF_LINUX (file on SourceForge changed?)"
            tar xjf "$TMPD/$SF_LINUX" -C "$TMPD" || die "tar extract failed"
            dyn=$(find "$TMPD" -name dynamo -type f | head -1)
            [ -n "$dyn" ] || die "dynamo not found inside $SF_LINUX"
            cp "$dyn" /opt/iometer/dynamo
        fi
        rm -rf "$TMPD"
    fi
    chmod +x /opt/iometer/dynamo
    file /opt/iometer/iometer.exe | grep -q 'PE32+.*x86-64' \
        || die "iometer.exe failed verification: $(file /opt/iometer/iometer.exe)"
    file /opt/iometer/dynamo | grep -q 'ELF 64-bit' \
        || die "dynamo failed verification: $(file /opt/iometer/dynamo)"
    echo "verified: $(file /opt/iometer/iometer.exe)"
    echo "verified: $(file /opt/iometer/dynamo)"
fi
missing=$(LD_LIBRARY_PATH=/opt/iometer ldd /opt/iometer/dynamo 2>/dev/null | awk '/not found/ {print $1}')
if [ -n "$missing" ]; then
    echo "dynamo needs missing libs: $missing — installing system libaio"
    apt-get install -y -qq libaio1t64 2>/dev/null \
        || apt-get install -y -qq libaio1 2>/dev/null \
        || die "cannot install libaio (dynamo needs: $missing)"
    LD_LIBRARY_PATH=/opt/iometer ldd /opt/iometer/dynamo | grep -q 'not found' \
        && die "dynamo still has unresolvable libs after libaio install"
fi
echo "dynamo link check: ok"

# --- 4. Pipeline into /root/rvi ----------------------------------------------------
step "Installing RVI pipeline into /root/rvi (from box-turtle)"
if [ -e /root/rvi ] && [ -n "$(ls -A /root/rvi 2>/dev/null)" ]; then
    die "/root/rvi exists and is not empty — refusing to clobber existing work"
fi
mkdir -p /root/rvi
TMPD=$(mktemp -d)
git clone -q --depth 1 "$REPO_URL" "$TMPD/box-turtle" || die "git clone failed (no internet?)"
[ -d "$TMPD/box-turtle/RVI_fan_sweep_iometer" ] || die "repo layout unexpected (RVI_fan_sweep_iometer missing)"
cp -a "$TMPD/box-turtle/RVI_fan_sweep_iometer/." /root/rvi/
rm -rf "$TMPD"
echo "pipeline installed: $(ls /root/rvi | tr '\n' ' ')"

# --- 5. Disk detection + ICF regeneration --------------------------------------------
step "Detecting data disks"
detect_data_disks() {
    local name sectors mounted
    for name in $(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk" {print $1}'); do
        case "$name" in nvme*|loop*|ram*|zram*) continue ;; esac
        sectors=$(awk '{print $1}' "/sys/block/$name/size" 2>/dev/null) || sectors=0
        [ "${sectors:-0}" -eq 0 ] 2>/dev/null && continue
        mounted=$(lsblk -npo MOUNTPOINT "/dev/$name" 2>/dev/null | head -1)
        [ -n "$mounted" ] && continue
        printf '%s\n' "$name"
    done | sort
}
DISKS=$(detect_data_disks)
DISK_COUNT=$(echo "$DISKS" | grep -c . || true)
echo "candidate data disks ($DISK_COUNT): $(echo $DISKS | tr '\n' ' ')"
EXPECTED=$(awk -F= '/^EXPECTED_DRIVES=/ {gsub(/[ \t]/, "", $2); print $2}' /root/rvi/rvi.conf)
if [ "$DISK_COUNT" -ne "$EXPECTED" ]; then
    die "detected $DISK_COUNT data disks, expected $EXPECTED (EXPECTED_DRIVES in rvi.conf).
Check 'lsblk' — if the set is different, set TEST_DISKS and EXPECTED_DRIVES in
/root/rvi/rvi.conf manually, then re-run this script."
fi
DISK_LIST=$(echo "$DISKS" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
sed -i "s|^TEST_DISKS=.*|TEST_DISKS=\"$DISK_LIST\"|" /root/rvi/rvi.conf
echo "rvi.conf now: $(grep '^TEST_DISKS=' /root/rvi/rvi.conf)"
python3 /root/rvi/make_icf.py /root/rvi/icf \
    --template /root/rvi/icf/ref_minimal.icf --disks $DISK_LIST --manager-ip 127.0.0.1 \
    || die "make_icf.py failed (ICF regeneration)"
python3 /root/rvi/make_1w.py || die "make_1w.py failed (1-worker ICF conversion)"
echo "ICFs regenerated for: $DISK_LIST"

# --- 6. BMC fan probe (warn-only) ------------------------------------------------------
step "BMC fan readback probe"
FAN=$(ipmitool raw 0x36 0xFB 2>&1)
if [ $? -eq 0 ] && [ "$(echo $FAN | wc -w)" -ge 19 ]; then
    echo "fan readback ok: $(echo $FAN | tr ' ' '\n' | sed -n '3p;19p' | paste -sd'/' ) (0-based idx 2/18)"
else
    echo "WARN: fan readback (0x36 0xFB) failed or short — 00_preflight will hard-FAIL on"
    echo "      fan checks. Verify this BMC speaks the ZELUS 0x36 protocol (SET = 0xFA + 16 bytes)."
fi

# --- 7. Preflight ------------------------------------------------------------------------
if [ "$RUN_PREFLIGHT" = 1 ]; then
    step "Running 00_preflight.sh (incl. 60 s 24-disk batch-mode smoke)"
    cd /root/rvi && bash 00_preflight.sh
    rc=$?
    [ "$rc" = 0 ] || die "preflight FAILED (rc=$rc) — fix the FAILs above, then re-run 00_preflight.sh"
fi

# --- 8. Done ---------------------------------------------------------------------------------
step "SETUP COMPLETE — RVI DUT ready"
cat <<'EOF'
Next steps (all as root):

  # classic fan sweep (24-worker ICFs)
  cd /root/rvi
  nohup bash 10_fan_sweep.sh >> logs/sweep_nohup.log 2>&1 &

  # pinned sweep with the customer 1-worker ICFs (RUN3 mode)
  nohup python3 run3_driver.py >> logs/run3_nohup.log 2>&1 &
  tail -f run3_progress.log

  # cross-stack report (runs on this box; python3-openpyxl is installed)
  python3 rvi_compare.py OUT.xlsx "Stack label" /path/to/csv_dir ...

Xvfb :99 is started on demand by the pipeline scripts (no systemd unit by
design). After a reboot: investigate first, then just re-run the sweep script.
EOF
