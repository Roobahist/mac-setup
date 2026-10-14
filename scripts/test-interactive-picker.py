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
import unicodedata

if len(sys.argv) != 2:
    raise SystemExit("Usage: python3 scripts/test-interactive-picker.py /path/to/mac-setup")

executable = Path(sys.argv[1])
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 36, 132, 0, 0))
env = dict(os.environ, TERM="xterm-256color")
env.pop("NO_COLOR", None)  # This test asserts ANSI highlighting regardless of the caller.
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


def rendered_terminal_rows(data: bytes, private_use_width: int) -> list[str]:
    """Reconstruct cursor movements under different Nerd Font fallback widths.

    This small emulator only implements the escape codes used by the picker.
    It checks column positions rather than assuming a private-use glyph is
    always one terminal cell wide.
    """
    output = data.decode("utf-8", "replace")
    rows: list[str] = []
    row: dict[int, str] = {}
    column = 0
    saved_column = 0
    index = 0

    def finish_row() -> None:
        rows.append("".join(row.get(position, " ") for position in range(max(row, default=-1) + 1)))

    while index < len(output):
        char = output[index]
        if char == "\x1b":
            if index + 1 < len(output) and output[index + 1] in ("7", "8"):
                if output[index + 1] == "7":
                    saved_column = column
                else:
                    column = saved_column
                index += 2
                continue
            if index + 1 < len(output) and output[index + 1] == "[":
                end = index + 2
                while end < len(output) and not ("@" <= output[end] <= "~"):
                    end += 1
                if end == len(output):
                    break
                code = output[end]
                params = output[index + 2:end]
                if code == "G":
                    column = max(0, int(params or "1") - 1)
                elif code == "H":
                    column = 0
                index = end + 1
                continue
        if char == "\r":
            column = 0
        elif char == "\n":
            finish_row()
            row = {}
            column = 0
        elif char >= " ":
            scalar = ord(char)
            private_use = 0xE000 <= scalar <= 0xF8FF or 0xF0000 <= scalar <= 0x10FFFD
            width = (private_use_width if private_use else
                     0 if unicodedata.combining(char) else
                     2 if unicodedata.east_asian_width(char) in ("F", "W") else 1)
            if width:
                row[column] = char
                for offset in range(1, width):
                    row[column + offset] = " "
                column += width
        index += 1
    return rows


def verify_glyph_columns(data: bytes) -> None:
    # Terminal fallback boxes may consume two cells even when wcwidth reports
    # one. The ASCII columns after the glyph must not move in either case.
    for fallback_width in (1, 2):
        rows = rendered_terminal_rows(data, private_use_width=fallback_width)
        header = next(line for line in rows if "SHORTCUT" in line and "GLYPH" in line)
        glyph_col = header.index("GLYPH")
        id_col = header.index("ID", glyph_col + len("GLYPH"))
        apps_col = header.index("APPS", id_col + len("ID"))
        for shortcut, glyph, workspace_id, count in (
            ("Alt+" + chr(96), "robot", "chatgpt", "2"),
            ("Alt+1", "1", "1", "0"),
            ("Alt+9", "music", "music", "1"),
            ("Alt+0", "chat", "messages", "3"),
            ("Alt+-", "notes", "notes", "1"),
            ("Alt+=", "clock", "timer", "1"),
        ):
            line = next((line for line in rows if shortcut in line and line.index(shortcut) < glyph_col), None)
            assert line is not None, f"Missing workspace {shortcut} with fallback width {fallback_width}"
            assert line[glyph_col:].startswith(glyph), (
                f"{shortcut} glyph name moved for fallback width {fallback_width}: {line!r}"
            )
            assert line[id_col:].startswith(workspace_id), (
                f"{shortcut} ID moved for fallback width {fallback_width}: {line!r}"
            )
            assert line[apps_col:].startswith(count), (
                f"{shortcut} app count moved for fallback width {fallback_width}: {line!r}"
            )

try:
    read_until(lambda b: b"MAC SETUP" in b and b"Homebrew" in b)
    read_until(lambda b: b"Inventory checked" in active_screen(b), timeout=120.0)
    initial = re.search(rb"(\d+)/(\d+) selected", active_screen(bytes(captured)))
    assert initial, "Initial selection count is missing"
    selected, total = map(int, initial.groups())
    os.write(master, b"u")
    read_until(lambda b: bool(re.search(rb"Homebrew[^\r\n]*UPDATE", active_screen(b))))
    assert f"{selected}/{total} selected".encode() in active_screen(bytes(captured))
    os.write(master, b"u")
    read_until(lambda b: not re.search(rb"Homebrew[^\r\n]*UPDATE", active_screen(b)))
    os.write(master, b" ")  # CI has Homebrew installed: unchecking it must keep children selected.
    expected = f"{selected - 1}/{total} selected".encode()
    read_until(lambda b: expected in active_screen(b) and b"Profile: Custom" in active_screen(b))
    os.write(master, b" ")
    read_until(lambda b: f"{selected}/{total} selected".encode() in active_screen(b))
    start = time.monotonic()
    os.write(master, b"\x1b[B")  # CSI cursor down
    read_until(
        lambda b: bool(re.search(
            rb"\x1b\[1;38;5;231;48;5;24m[^\r\n]*Interface and terminal fonts", active_screen(b)
        )), timeout=4.0
    )
    assert "[x] ├── Interface and terminal fonts".encode() in active_screen(bytes(captured))
    read_until(lambda b: "│   └──".encode() in active_screen(b))
    read_until(lambda b: b"Inventory checked" in active_screen(b))
    plain = re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]", b"", active_screen(bytes(captured)))
    checkbox_columns = [line.index("[x]") for line in plain.decode("utf-8", "replace").splitlines() if "[x]" in line]
    assert checkbox_columns and len(set(checkbox_columns)) == 1, "Child checkboxes moved out of the shared column"
    assert re.search(rb"\r?\n +" + "│".encode() + rb"\r?\n", plain), "Child group spacer is missing"
    assert b"[parents:" not in active_screen(bytes(captured))
    assert time.monotonic() - start < 4.0, "Cursor movement is blocked by status checks"

    os.write(master, b"\x1bOA")  # SS3 cursor up
    read_until(
        lambda b: bool(re.search(
            rb"\x1b\[1;38;5;231;48;5;24m[^\r\n]*Homebrew", active_screen(b)
        )), timeout=4.0
    )

    # Enter the workspace editor from the main setup checklist.
    os.write(master, b"w")
    read_until(lambda b: b"WORKSPACE EDITOR" in active_screen(b)
               and b"APP RULES" in active_screen(b)
               and b"G Glyph" in active_screen(b), timeout=15.0)
    workspace_screen = active_screen(bytes(captured))
    assert b"MAC SETUP" in workspace_screen and b"2 Workspaces" in workspace_screen
    assert b"WORKSPACE ORDER" in workspace_screen
    assert b"SELECTED WORKSPACE" in workspace_screen, "Wide view should show inspector"
    assert b"SHORTCUT" in workspace_screen and b"GLYPH" in workspace_screen
    assert b"ICON" in workspace_screen, "Glyph preview column should always be present"
    assert "󰚩".encode() in workspace_screen, "Expected actual Hack Nerd Font icon preview"
    assert b"Pomodoro" in workspace_screen, "Tomito workspace must be in default layout"
    assert b"APP RULES" in workspace_screen
    assert b"robot" in workspace_screen, "Glyph name must be readable without Nerd Font"
    verify_glyph_columns(workspace_screen)
    assert b"\x1b[1;38;5;231;48;5;24m" in workspace_screen, "Selection has no highlight"
    os.write(master, b"g")
    read_until(lambda b: b"Type to filter glyph" in active_screen(b))
    os.write(master, b"clock")
    read_until(lambda b: b"Search: clock" in active_screen(b))
    os.write(master, b"\r")
    read_until(lambda b: b"G Glyph" in active_screen(b)
               and b"UNSAVED CHANGES" in active_screen(b))
    os.write(master, b"p")
    read_until(lambda b: b"Type to filter installed apps" in active_screen(b), timeout=15.0)
    os.write(master, b"zzzzzzz")
    read_until(lambda b: b"No matching applications" in active_screen(b))
    os.write(master, b"\x1b")
    read_until(lambda b: b"installed apps found" in active_screen(b)
               and b"Search: " in active_screen(b))
    os.write(master, b"\x1b")
    read_until(lambda b: b"G Glyph" in active_screen(b))
    os.write(master, b"\x1b")
    read_until(lambda b: b"DISCARD YOUR CHANGES?" in active_screen(b))
    os.write(master, b"n")
    read_until(lambda b: b"WORKSPACE ORDER" in active_screen(b))
    os.write(master, b"q")
    read_until(lambda b: b"DISCARD YOUR CHANGES?" in active_screen(b))
    os.write(master, b"y")
    read_until(lambda b: b"MAC SETUP" in active_screen(b)
               and b"WORKSPACE EDITOR" not in active_screen(b))

    # Continue from feature selection automatically enters the same workspace
    # step if AeroSpace is selected. Keeping defaults makes no file changes.
    os.write(master, b"\r")
    read_until(lambda b: b"WORKSPACE EDITOR" in active_screen(b)
               and b"Keep layout" in active_screen(b)
               and b"2 Workspaces" in active_screen(b))
    os.write(master, b"k")
    read_until(lambda b: b"REVIEW SELECTION" in active_screen(b)
               and b"3 Review" in active_screen(b))
    os.write(master, b"\x1b")  # Escape returns to selection, not setup
    read_until(lambda b: b"REVIEW SELECTION" not in active_screen(b)
               and b"Select features" in active_screen(b))
    # Having kept settings once should not reopen the workspace step.
    os.write(master, b"\r")
    read_until(lambda b: b"REVIEW SELECTION" in active_screen(b))
    os.write(master, b"\x1b")
    read_until(lambda b: b"Select features" in active_screen(b))
    os.write(master, b"q")
    # Continue draining the pseudo-terminal while the picker exits; otherwise a
    # final screen write can fill the PTY buffer and block the child process.
    read_until(lambda b: b"No tasks selected." in b, timeout=8.0)
    try:
        exit_code = process.wait(timeout=5)
    except subprocess.TimeoutExpired as exc:
        screen = active_screen(bytes(captured)).decode("utf-8", "replace")
        raise AssertionError("Q did not exit the interactive picker; last screen: " + repr(screen[-700:])) from exc
    assert exit_code == 0, f"Picker exited with {exit_code}"
    print("Interactive terminal smoke test passed (CSI, SS3, workspace editor, review and cancel)")
finally:
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=2)
    os.close(master)
