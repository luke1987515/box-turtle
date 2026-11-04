#!/usr/bin/env python3
"""bmc_sweep.py -- find BMCs on a subnet by their web-UI TCP port.

Usage: bmc_sweep.py [CIDR] [port] [workers]

AIC BMCs block ICMP (a ping sweep is blind to them) and do not answer a bare
UDP-623 probe, but their web UI listens on TCP 443. A plain TCP connect
needs no raw sockets -- unlike the raw-ARP sweep this also works on Wi-Fi
runners where AF_PACKET injection is silently dropped. The caller must still
VERIFY a hit (bmc_power_probe / ipmi_try): other boxes may serve 443.

Prints one candidate IP per line.
Exit: 0 = sweep ran (zero or more candidates) | non-zero = failed.
"""
import ipaddress
import socket
import sys
from concurrent.futures import ThreadPoolExecutor


def default_cidr():
    try:
        with open("/proc/net/route") as f:
            lines = f.read().splitlines()[1:]
        for line in lines:
            parts = line.split()
            if parts[1] == "00000000" and parts[2] != "00000000":
                import subprocess
                out = subprocess.run(
                    ["ip", "-4", "-o", "addr", "show", parts[0]],
                    capture_output=True, text=True, timeout=5)
                for tok in out.stdout.split():
                    if "/" in tok and tok[0].isdigit():
                        ip = tok.split("/")[0]
                        return "%s.0/24" % ip.rsplit(".", 1)[0]
    except (OSError, ValueError):
        pass
    sys.exit("bmc_sweep: cannot derive a scan range (pass a CIDR)")


def probe(ip, port, to=1.5):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(to)
    try:
        s.connect((ip, port))
        return True
    except OSError:
        return False
    finally:
        s.close()


def main():
    cidr = sys.argv[1] if len(sys.argv) > 1 else default_cidr()
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 443
    workers = int(sys.argv[3]) if len(sys.argv) > 3 else 64
    try:
        net = ipaddress.ip_network(cidr, strict=False)
    except ValueError:
        sys.exit("bmc_sweep: bad CIDR %r" % cidr)
    if net.num_addresses > 2048:
        sys.exit("bmc_sweep: /%d is too big" % net.prefixlen)
    hosts = [str(h) for h in net.hosts()]
    with ThreadPoolExecutor(max_workers=workers) as ex:
        results = list(ex.map(lambda h: probe(h, port), hosts))
    for ip, ok in zip(hosts, results):
        if ok:
            print(ip)


if __name__ == "__main__":
    main()
