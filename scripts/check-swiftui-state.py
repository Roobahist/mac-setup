#!/usr/bin/env python3
"""Keep the app compilable with standalone Command Line Tools on new SDKs."""

import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
sources = root / "Sources" / "MacSetup"
compat = sources / "SwiftUICompatibility.swift"
alias = "typealias LocalViewState<Value> = SwiftUI.State<Value>"

if alias not in compat.read_text(encoding="utf-8"):
    raise SystemExit("Missing LocalViewState property-wrapper compatibility alias")

offenders = []
for path in sorted(sources.glob("*.swift")):
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if re.match(r"\\s*@State\\b", line):
            offenders.append(f"{path.relative_to(root)}:{line_number}")

if offenders:
    raise SystemExit(
        "Direct @State uses an Xcode-only macro on some SDKs; "
        "use @LocalViewState instead:\n" + "\n".join(offenders)
    )
print("SwiftUI state is compatible with standalone Command Line Tools.")
