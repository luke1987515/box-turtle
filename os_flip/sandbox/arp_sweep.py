#!/usr/bin/env python3
"""arp_sweep.py -- L2 ARP sweep of one subnet; prints one "ip mac" line per responder.

Usage: arp_sweep.py [CIDR] [listen_seconds]

The CIDR defaults to the /24 of the default-route interface. The sweep sends
one ARP who-has per address and then listens for replies. Because it works at
layer 2 it also sees hosts that answer ARP but never answer ICMP (BMCs -- e.g.
AIC boards block ICMP) which a ping sweep would miss entirely. A responder
whose who-has was lost to a busy interface is missed by that sweep only; the
caller re-sweeps on a cadence, so this is self-correcting.

Needs CAP_NET_RAW (run as root). Linux only (AF_PACKET).
Exit: 0 = sweep ran (zero or more responders) | non-zero = sweep failed
(stderr carries the reason).
"""
import fcntl
import os
import socket
import struct
import sys
import time

ETH_P_ARP = 0x0806
SIOCGIFADDR = 0x8915


def default_iface():
    try:
        with open("/proc/net/route") as f:
            lines = f.read().splitlines()[1:]
        for line in lines:
            parts = line.split()
            if parts[1] == "00000000" and parts[2] != "00000000":
                return parts[0]
    except OSError:
        pass
    for ifc in sorted(os.listdir("/sys/class/net")):
        if ifc != "lo":
            return ifc
    sys.exit("arp_sweep: no network interface found")


def iface_hwaddr(ifc):
    with open("/sys/class/net/%s/address" % ifc) as f:
        return bytes.fromhex(f.read().strip().replace(":", ""))


def iface_ip(ifc):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        return socket.inet_ntoa(fcntl.ioctl(  # type: ignore[attr-defined]
            s.fileno(), SIOCGIFADDR, struct.pack("256s", ifc.encode()[:15]))[20:24])
    except OSError:
        return None
    finally:
        s.close()


def main():
    cidr = sys.argv[1] if len(sys.argv) > 1 else None
    listen_s = float(sys.argv[2]) if len(sys.argv) > 2 else 4.0
    ifc = default_iface()
    mac = iface_hwaddr(ifc)
    srcip = iface_ip(ifc)
    if not cidr:
        if srcip is None:
            sys.exit("arp_sweep: interface %s has no IPv4 address (pass a CIDR)" % ifc)
        cidr = "%s.0/24" % srcip.rsplit(".", 1)[0]
    try:
        net, bits = cidr.split("/")
        bits = int(bits)
    except ValueError:
        sys.exit("arp_sweep: bad CIDR %r" % cidr)
    if not 8 <= bits <= 30:
        sys.exit("arp_sweep: unsupported prefix /%d (8..30)" % bits)
    netn = struct.unpack(">I", socket.inet_aton(net))[0]
    size = 1 << (32 - bits)
    if size > 2048:
        sys.exit("arp_sweep: /%d is too big (%d hosts)" % (bits, size))
    base = netn & ((0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF)
    srcip_bin = socket.inet_aton(srcip) if srcip else b"\x00\x00\x00\x00"

    sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW,  # type: ignore[attr-defined]
                         socket.htons(ETH_P_ARP))
    sock.bind((ifc, 0))
    sock.settimeout(0.2)

    def frame(target_ip_bin):
        arp = struct.pack("!HHBBH", 1, ETH_P_ARP, 6, 4, 1)
        arp += mac + srcip_bin + b"\x00" * 6 + target_ip_bin
        return b"\xff" * 6 + struct.pack("!H", ETH_P_ARP) + arp

    for i in range(size):
        if i in (0, size - 1):
            continue  # network + broadcast addresses
        ip_bin = struct.pack(">I", base + i)
        if ip_bin == srcip_bin:
            continue
        try:
            sock.send(frame(ip_bin))  # send(): sendto(("", 0)) hits ENODEV on some kernels/wifi ifaces
        except OSError as e:
            sys.exit("arp_sweep: send failed on %s: %s" % (ifc, e))

    seen = {}
    deadline = time.time() + listen_s
    while time.time() < deadline:
        try:
            data, _ = sock.recvfrom(65535)
        except socket.timeout:
            continue
        except OSError:
            break
        if len(data) < 14 + 28:
            continue
        if data[12:14] != struct.pack("!H", ETH_P_ARP):
            continue
        opcode = struct.unpack("!H", data[20:22])[0]
        if opcode != 2:  # replies only
            continue
        sip = data[28:32]
        smac = data[22:28]
        if sip == b"\x00" * 4 or smac == b"\x00" * 6:
            continue
        seen[sip] = smac
    sock.close()

    for ip_bin in sorted(seen):
        smac = seen[ip_bin]
        print(socket.inet_ntoa(ip_bin),
              ":".join("%02x" % b for b in smac))


if __name__ == "__main__":
    main()
