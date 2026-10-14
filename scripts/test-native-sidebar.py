#!/usr/bin/env python3
"""Sidebar invariant: one native sidebar of fixed internal size.

The collapsed state is a narrow viewport onto the *same* native List, and
its label titles must be hidden without changing native icon/layout geometry.
Never use a second renderer, resize the list, or clip visible text in half.
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
assert 'sidebarNavigationLabel(item).tag(item)' in sidebar
assert "sidebarNavigationLabel(.guidedSetup)" in sidebar
assert "sidebarNavigationLabel(.updates)" in sidebar

# A single native Label keeps the icon spacing and row selection identical.
# Only its title becomes visually transparent, so no half-cut labels leak
# through the clipped viewport.
assert 'Label {' in source
assert 'Text(item.title)' in source
assert '.opacity(compactSidebar ? 0 : 1)' in source
assert 'Image(systemName: item.symbol)' in source
assert '.accessibilityLabel(item.title)' in source
assert ".labelStyle(.iconOnly)" not in sidebar
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
