#!/usr/bin/env python3
"""ssh_cmd.py -- non-interactive ssh with password via pexpect (runner has no sshpass).

The remote command is passed as ONE ssh argv element (no local shell), so the
server executes it without a pty. That matters twice:
  * Windows OpenSSH: lines sent into an interactive cmd.exe session are NOT
    executed (verified 2026-10-28); a non-interactive command string is.
  * No local shell => `$?` inside the command reaches the remote shell intact.

Usage: ssh_cmd.py USER PASS HOST COMMAND MARKER TIMEOUT
Stdout: full transcript up to and including the marker.
Exit: 0 marker seen | 1 EOF (marker not seen -- auth failures land here)
      | 2 timeout waiting for marker | 3 spawn error
"""
import pexpect
import sys


def main():
    if len(sys.argv) != 7:
        print(__doc__)
        sys.exit(3)
    user, pw, host, command, marker, timeout = sys.argv[1:7]
    timeout = float(timeout)
    argv = ["ssh",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=8",
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "PreferredAuthentications=password",
            "-o", "PubkeyAuthentication=no",
            user + "@" + host,
            command]
    try:
        c = pexpect.spawn(argv[0], argv[1:], encoding="utf-8", timeout=timeout)
    except Exception as e:
        sys.stdout.write("SSH SPAWN ERROR: %s\n" % e)
        sys.exit(3)
    i = c.expect(["assword:", pexpect.EOF, pexpect.TIMEOUT])
    if i == 2:
        sys.stdout.write((c.before or "") + "\n")
        sys.exit(2)
    if i == 1:
        # EOF before the password prompt: host unreachable / ssh died
        sys.stdout.write((c.before or "") + "\n")
        sys.exit(1)
    c.sendline(pw)
    if marker == "-":
        # fire-and-forget: the command may kill its own session (e.g. the
        # shutdown command); EOF or a quiet timeout both count as "sent".
        i = c.expect([pexpect.EOF, pexpect.TIMEOUT])
        sys.stdout.write((c.before or "") + "\n")
        sys.exit(0)
    i = c.expect([marker, pexpect.EOF, pexpect.TIMEOUT])
    if i == 0:
        # c.after holds the matched marker text -- include it
        sys.stdout.write((c.before or "") + (c.after or "") + "\n")
        sys.exit(0)
    if i == 1:
        sys.stdout.write((c.before or "") + "\n")
        sys.exit(1)
    sys.stdout.write((c.before or "") + "\n")
    sys.exit(2)


if __name__ == "__main__":
    main()
