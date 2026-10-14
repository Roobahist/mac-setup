#!/usr/bin/env python3
"""Guard against replacing the original expanded native sidebar with custom rows.

This is a static structural check, not a visual screenshot assertion. Actual
expanded/collapsed geometry still needs a manual macOS UI check.
"""

from pathlib import Path

source = (Path(__file__).resolve().parents[1]
          / "Sources/MacSetup/ControlCenter.swift").read_text(encoding="utf-8")
start = source.index("    private var sidebar: some View {")
end = source.index("    private func selectDestination(", start)
sidebar = source[start:end]

expected = {
    "native sidebar List": "List(selection: $destination)",
    "native sidebar style": ".listStyle(.sidebar)",
    "transparent native sidebar list": ".scrollContentBackground(.hidden)",
    "original expanded header": "VStack(alignment: .leading, spacing: 10)",
    "original expanded toggle geometry": ".frame(width: 30, height: 30)",
    "original expanded branding": 'Text("Your Mac, your way")',
    "matching sidebar icon labels": "Label(item.title, systemImage: item.symbol)",
    "collapsed label-only change": ".labelStyle(.iconOnly)",
    "one section title hidden without removing its space": ".opacity(compactSidebar ? 0 : 1)",
}

for description, text in expected.items():
    assert text in sidebar, f"Sidebar lost {description}"
assert sidebar.count("List(selection: $destination)") == 1, (
    "Both modes must use the same native List")
assert "sidebarRowContent" not in sidebar, (
    "Do not replace expanded native sidebar rows with custom controls")
assert "compactRow(" not in sidebar, (
    "Do not create a second, differently sized sidebar for collapsed mode")
assert "if compactSidebar {\n                ScrollView" not in sidebar, (
    "Collapsed mode should hide titles, not replace the native List")
print("Expanded sidebar remains native; collapse only hides titles.")
