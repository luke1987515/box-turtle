#!/usr/bin/env python3
"""sweep_hosts.py -- find live hosts on a subnet via the kernel's own ping path.

Usage: sweep_hosts.py [CIDR] [workers]

Unlike the raw-ARP sweep (arp_sweep.py, which needs CAP_NET_RAW and does not
work on many Wi-Fi runners because the driver silently drops injected
AF_PACKET frames), this uses the kernel's normal ICMP path (the ping binary)
plus the kernel neigh cache for the MACs. It sees every ICMP-answering host
(DUT-class machines). ICMP-deaf hosts (AIC BMCs) are out of scope here --
use bmc_sweep.py for those.

Prints one "ip mac" line per live host (mac empty until the kernel has
resolved it). The sweep's own IP is excluded.
Exit: 0 = sweep ran (zero or more responders) | non-zero = failed.
"""
import ipaddress
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor


def default_cidr():
    try:
        with open("/proc/net/route") as f:
            lines = f.read().splitlines()[1:]
        for line in lines:
            parts = line.split()
            if parts[1] == "00000000" and parts[2] != "00000000":
                out = subprocess.run(
                    ["ip", "-4", "-o", "addr", "show", parts[0]],
                    capture_output=True, text=True, timeout=5)
                for tok in out.stdout.split():
                    if "/" in tok and tok[0].isdigit():
                        ip = tok.split("/")[0]
                        return "%s.0/24" % ip.rsplit(".", 1)[0]
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    sys.exit("sweep_hosts: cannot derive a scan range (pass a CIDR)")


def local_ips():
    ips = set()
    try:
        out = subprocess.run(["ip", "-4", "-o", "addr", "show"],
                             capture_output=True, text=True, timeout=5).stdout
        for line in out.splitlines():
            parts = line.split()
            for i, tok in enumerate(parts):
                if tok == "inet" and i + 1 < len(parts):
                    ips.add(parts[i + 1].split("/")[0])
    except (OSError, subprocess.SubprocessError):
        pass
    return ips


def ping_one(ip):
    try:
        r = subprocess.run(["ping", "-c1", "-W1", ip],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=4)
        return r.returncode == 0
    except Exception:
        return False


def neigh_mac(ip):
    try:
        out = subprocess.run(["ip", "neigh", "show", ip],
                             capture_output=True, text=True, timeout=5).stdout
        toks = out.split()
        if "lladdr" in toks:
            return toks[toks.index("lladdr") + 1].lower()
    except (OSError, subprocess.SubprocessError, IndexError):
        pass
    return ""


def main():
    cidr = sys.argv[1] if len(sys.argv) > 1 else default_cidr()
    workers = int(sys.argv[2]) if len(sys.argv) > 2 else 64
    try:
        net = ipaddress.ip_network(cidr, strict=False)
    except ValueError:
        sys.exit("sweep_hosts: bad CIDR %r" % cidr)
    if net.num_addresses > 2048:
        sys.exit("sweep_hosts: /%d is too big" % net.prefixlen)
    mine = local_ips()
    hosts = [str(h) for h in net.hosts() if str(h) not in mine]
    with ThreadPoolExecutor(max_workers=workers) as ex:
        results = list(ex.map(ping_one, hosts))
    for ip, alive in zip(hosts, results):
        if alive:
            print(ip, neigh_mac(ip))


if __name__ == "__main__":
    main()
