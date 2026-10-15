import AppKit
import SwiftUI

struct SetupChoice<Value: Hashable>: Equatable {
    let value: Value
    let title: String
    var group: String? = nil
}

/// A native popup tracks its entire bounds, including padding and the disclosure.
/// SwiftUI's borderless Menu only tracks its intrinsic text on macOS.
struct SetupDropdown<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [SetupChoice<Value>]
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        NativePopup(title: title, selection: $selection, choices: choices)
            .frame(height: SetupDesign.controlHeight)
            .workspaceControl()
            .overlay {
                HStack(spacing: 5) {
                    Text(choices.first { $0.value == selection }?.title ?? "Choose…")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    WorkspaceDisclosure(direction: "down")
                }
                .foregroundStyle(enabled ? Color.primary : Color.secondary)
                .padding(.horizontal, 8)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}

private struct NativePopup<Value: Hashable>: NSViewRepresentable {
    let title: String
    @Binding var selection: Value
    let choices: [SetupChoice<Value>]
    @Environment(\.isEnabled) private var enabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PopupButton {
        let button = PopupButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.menu?.autoenablesItems = false
        button.isTransparent = true
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        button.focusRingType = .exterior
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        return button
    }

    func updateNSView(_ button: PopupButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.choices != choices {
            coordinator.choices = choices
            button.removeAllItems()
            var previousGroup: String?
            for (index, choice) in choices.enumerated() {
                if choice.group != previousGroup, let group = choice.group {
                    if index > 0 { button.menu?.addItem(.separator()) }
                    let heading = NSMenuItem(title: group, action: nil, keyEquivalent: "")
                    heading.isEnabled = false
                    heading.tag = -1
                    button.menu?.addItem(heading)
                }
                let item = NSMenuItem(title: choice.title, action: nil, keyEquivalent: "")
                item.tag = index
                button.menu?.addItem(item)
                previousGroup = choice.group
            }
        }
        if let index = choices.firstIndex(where: { $0.value == selection }) {
            button.selectItem(withTag: index)
        } else { button.select(nil) }
        button.isEnabled = enabled
        button.setAccessibilityLabel(title)
    }

    final class Coordinator: NSObject {
        var parent: NativePopup
        var choices: [SetupChoice<Value>] = []
        init(_ parent: NativePopup) { self.parent = parent }
        @objc func changed(_ sender: NSPopUpButton) {
            guard let item = sender.selectedItem, choices.indices.contains(item.tag) else { return }
            parent.selection = choices[item.tag].value
        }
    }
}

private final class PopupButton: NSPopUpButton {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: SetupDesign.controlHeight)
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }
}
