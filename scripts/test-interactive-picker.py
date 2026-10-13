#!/usr/bin/env python3
"""Exercise the real raw-terminal picker without applying setup changes."""
from __future__ import annotations

import fcntl
import os
from pathlib import Path
import pty
import re
import select
import struct
import subprocess
import sys
import termios
import time

if len(sys.argv) != 2:
    raise SystemExit("Usage: python3 scripts/test-interactive-picker.py /path/to/mac-setup")

executable = Path(sys.argv[1])
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
env = dict(os.environ, TERM="xterm-256color")
process = subprocess.Popen(
    [str(executable)],
    stdin=slave,
    stdout=slave,
    stderr=slave,
    env=env,
    start_new_session=True,
)
os.close(slave)
captured = bytearray()

def read_until(predicate, timeout=8.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate(bytes(captured)):
            return
        available, _, _ = select.select([master], [], [], min(0.10, max(0.0, deadline - time.monotonic())))
        if available:
            chunk = os.read(master, 65536)
            if not chunk:
                break
            captured.extend(chunk)
    raise AssertionError("Interactive picker did not reach the expected screen in time")

def active_screen(data: bytes) -> bytes:
    return data.rsplit(b"\x1b[H\x1b[2J", 1)[-1]

try:
    read_until(lambda b: b"MAC SETUP" in b and b"Homebrew" in b)
    start = time.monotonic()
    os.write(master, b"\x1b[B")  # CSI cursor down
    read_until(
        lambda b: bool(re.search(
            rb"\x1b\[1;46;30m[^\r\n]*Link public dotfiles", active_screen(b)
        )), timeout=4.0
    )
    assert time.monotonic() - start < 4.0, "Cursor movement is blocked by status checks"

    os.write(master, b"\x1bOA")  # SS3 cursor up
    read_until(
        lambda b: bool(re.search(
            rb"\x1b\[1;46;30m[^\r\n]*Homebrew", active_screen(b)
        )), timeout=4.0
    )

    os.write(master, b"\r")
    read_until(lambda b: b"REVIEW SELECTION" in active_screen(b))
    os.write(master, b"\x1b")  # Escape returns to selection, not setup
    read_until(lambda b: b"REVIEW SELECTION" not in active_screen(b)
               and b"Select features" in active_screen(b))
    os.write(master, b"q")
    try:
        exit_code = process.wait(timeout=5)
    except subprocess.TimeoutExpired as exc:
        screen = active_screen(bytes(captured)).decode("utf-8", "replace")
        raise AssertionError("Q did not exit the interactive picker; last screen: " + repr(screen[-700:])) from exc
    assert exit_code == 0, f"Picker exited with {exit_code}"
    print("Interactive terminal smoke test passed (CSI, SS3, review and cancel)")
finally:
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=2)
    os.close(master)
