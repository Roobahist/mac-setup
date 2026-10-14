#!/usr/bin/env python3
"""Sidebar invariant: one native sidebar of fixed internal size.

The collapsed state is a narrow viewport onto the *same* native List. Never
switch to a second icon renderer or resize the underlying list. That would
change selection, hover, tint, insets and the location of each icon.
Visual alignment still needs manual screenshot verification on macOS.
"""

from pathlib import Path

source = (Path(__file__).resolve().parents[1]
          / "Sources/MacSetup/ControlCenter.swift").read_text(encoding="utf-8")
start = source.index("    private var sidebar: some View {")
end = source.index("    private func selectDestination(", start)
sidebar = source[start:end]

assert "sidebar\n                .frame(width: 248, alignment: .leading)" in source
assert ".frame(width: compactSidebar ? 70 : 248, alignment: .leading)" in source
assert ".clipped()" in source

# One set of controls for both expanded and collapsed states.
assert sidebar.count("List(selection: $destination)") == 1
assert "ForEach(customization)" in sidebar
assert 'Label(item.title, systemImage: item.symbol).tag(item)' in sidebar
assert ".listStyle(.sidebar)" in sidebar
assert ".scrollContentBackground(.hidden)" in sidebar
assert "compactRow" not in sidebar
assert "if compactSidebar {\n                ScrollView" not in sidebar
assert ".labelStyle(.iconOnly)" not in sidebar

# User-defined selected/hover behavior is the macOS native List, not a
# replacement button. It receives the same 248-point geometry in both states.
assert 'Image(systemName: "sidebar.left")' in sidebar
assert ".frame(width: 30, height: 30)" in sidebar
assert ".padding(.horizontal, 14)" in sidebar
assert 'Text("Customize")' in sidebar
assert 'Text("Mac Setup")' in sidebar
assert ".opacity(compactSidebar ? 0 : 1)" in sidebar
assert 'Text("Your Mac, your way")' in sidebar

print("One fixed-width native sidebar; collapse only clips the viewport.")
