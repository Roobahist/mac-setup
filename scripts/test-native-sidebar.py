#!/usr/bin/env python3
"""Structural invariants for one compact/expanded macOS navigation rail.

The collapsed sidebar must have real compact geometry, with identical icon
centerlines and contained hover/selection backgrounds. This is a source
guard, not a screenshot or a macOS accessibility test.
"""

from pathlib import Path

source = (Path(__file__).resolve().parents[1]
          / "Sources/MacSetup/ControlCenter.swift").read_text(encoding="utf-8")
start = source.index("    private var sidebar: some View {")
end = source.index("    private func selectDestination(", start)
sidebar = source[start:end]
body = source[source.index("    var body: some View {"):start]

# A collapsed rail is not an expanded List cut off at 70 points.
assert ".frame(width: compactSidebar ? 72 : 248, alignment: .leading)" in body
assert ".clipped()" not in body
assert "List(selection: $destination)" not in sidebar
assert ".listStyle(.sidebar)" not in sidebar

# Shared navigation component and identical row geometry at both widths.
assert "ForEach(customization) { item in" in sidebar
assert sidebar.count("sidebarNavigationRow(item)") == 1
assert "sidebarNavigationRow(.guidedSetup)" in sidebar
assert "sidebarNavigationRow(.updates)" in sidebar
assert "private func sidebarNavigationRow(_ item: ControlDestination)" in sidebar
assert 'Image(systemName: item.symbol)' in sidebar
assert '.frame(width: 40, height: 40)' in sidebar
assert '.padding(.leading, 8)' in sidebar
assert '.padding(.horizontal, 8)' in sidebar
assert 'if !compactSidebar {' in sidebar
assert "Text(item.title)" in sidebar

# Hover and selected states never escape the bounds of a row.
assert "RoundedRectangle(cornerRadius: 10)" in sidebar
assert ".fill(selected ? Color.accentColor.opacity(0.15)" in sidebar
assert "hoveredSidebarItem == item" in sidebar
assert ".contentShape(RoundedRectangle(cornerRadius: 10))" in sidebar
assert ".onHover { hovering in" in sidebar
assert ".help(item.title)" in sidebar
assert ".accessibilityLabel(item.title)" in sidebar

# Toggle/search and navigation images have the same icon centerline.
assert 'Image(systemName: "sidebar.left")' in sidebar
assert 'Image(systemName: "magnifyingglass")' in sidebar
assert ".padding(.leading, 16)" in sidebar
assert ".frame(width: 40, height: 40)" in sidebar

print("Sidebar uses a real compact rail and bounded shared navigation rows.")
