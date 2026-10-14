#!/usr/bin/env python3
"""Regression guard: expanded sidebar remains native and compact uses real icons.

The user chose the native expanded sidebar but the dedicated compact rail.
Do not collapse by clipping the expanded List to 70 points again.
This is a structural check; screenshots remain necessary for visual QA.
"""

from pathlib import Path

source = (Path(__file__).resolve().parents[1]
          / "Sources/MacSetup/ControlCenter.swift").read_text(encoding="utf-8")
start = source.index("    private var sidebar: some View {")
end = source.index("    private func selectDestination(", start)
sidebar = source[start:end]
assert "VStack(alignment: .leading, spacing: 10)" in sidebar
assert ".frame(width: 30, height: 30)" in sidebar
assert 'Text("Your Mac, your way")' in sidebar

# Two distinct layouts: icon-only ScrollView, original expanded native List.
compact_start = sidebar.index("            if compactSidebar {\n"
                             "                // This is an actual icon rail")
expanded_start = sidebar.index("            } else {\n"
                              "                List(selection: $destination)", compact_start)
compact, expanded = sidebar[compact_start:expanded_start], sidebar[expanded_start:]
assert "ScrollView {" in compact
assert "compactRow(item)" in compact
assert "compactRow(.updates)" in compact
assert 'Image(systemName: ControlDestination.guidedSetup.symbol)' in compact
assert 'Text("Customize")' not in compact
assert ".frame(width: 50, height: 43)" in compact

assert "List(selection: $destination)" in expanded
assert ".listStyle(.sidebar)" in expanded
assert ".scrollContentBackground(.hidden)" in expanded
assert 'Text("Customize")' in expanded
assert 'Text("Mac Setup")' in expanded
assert "sidebarLabel(item).tag(item)" in expanded

# Compact icons must use the same accent blue as the expanded native List.
helper = sidebar[sidebar.index("    private func compactRow("):]
assert "Color.primary.opacity(0.16)" in helper
assert ".foregroundStyle(Color.accentColor)" in helper
assert '.foregroundStyle(Color.accentColor)\n                        .help("Guided Setup")' in compact
assert "Text(item.title)" not in helper
assert "Image(systemName: item.symbol)" in helper
assert "Button { selectDestination(item) }" in helper
assert ".frame(width: compactSidebar ? 70 : 248)" in source
print("Expanded List preserved and true icon-only compact rail verified.")
