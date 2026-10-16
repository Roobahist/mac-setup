import SwiftUI

/// Contextual instructions for the real settings pages. Guided setup does not
/// duplicate editors, maintain a separate installer flow, or apply anything.
struct GuidedTourStep: Identifiable {
    let destination: ControlDestination
    let title: String
    let explanation: String
    let nextAction: String

    var id: ControlDestination { destination }

    static let steps: [Self] = [
        .init(destination: .apps, title: "Choose your features",
              explanation: "Choose a ready-made preset such as Repair, Minimal, Productivity, Developer, or Complete. You can also select an entire category, all optional features, or individual items. Dependencies are included automatically.",
              nextAction: "Use Review & apply selected features to inspect the batch before anything installs. You can skip this step without installing."),
        .init(destination: .shortcuts, title: "Make your keyboard your own",
              explanation: "Inspect AeroSpace, Karabiner, and Raycast shortcuts in the existing shortcut editor. Change hotkeys, enabled actions, and application launch actions.",
              nextAction: "Choose Review & apply shortcuts to save and update the real shortcut profiles. Until then, changes are drafts."),
        .init(destination: .workspaces, title: "Arrange workspaces",
              explanation: "Name workspaces, choose glyphs, assign apps, reorder cards and choose switch and move keys.",
              nextAction: "Workspace edits are drafts until you review and apply them."),
        .init(destination: .workspaceBar, title: "Customize the workspace bar",
              explanation: "Adjust SketchyBar colors, blur and spacing. Manual accent and automatic wallpaper colors have their own explicit controls.",
              nextAction: "Review and apply bar appearance to save the visual draft. Changing wallpaper automation takes effect when you enable or disable it."),
        .init(destination: .appearance, title: "Customize appearance",
              explanation: "Choose the native macOS accent color independently from SketchyBar's bar colors.",
              nextAction: "Apply the accent only when you want to update macOS native controls."),
        .init(destination: .dock, title: "Tune the Dock",
              explanation: "Control automatic hiding, reveal delay, animation speed, icon size, and recently used applications.",
              nextAction: "Each preference is applied individually. System default and Undo are available."),
        .init(destination: .finder, title: "Set up Finder",
              explanation: "Show filename extensions, hidden files, the path bar, and status information. These settings affect Finder, not your project files.",
              nextAction: "Adjust individual controls and keep your existing Finder preferences when you are happy."),
        .init(destination: .updates, title: "Keep Mac Setup up to date",
              explanation: "New customization options arrive through versioned GitHub releases. You can review available updates and install them from this section.",
              nextAction: "You are finished. Future customization is available directly from the sidebar.")
    ]
}

struct GuidedTourBanner: View {
    let step: GuidedTourStep
    let index: Int
    let total: Int
    let canGoBack: Bool
    let canAdvance: Bool
    let hasUnappliedEdits: Bool
    let onBack: () -> Void
    let onSkip: () -> Void
    let onNext: () -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Label("Guided setup", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text("Step \(index + 1) of \(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(index + 1), total: Double(total))
                .tint(.accentColor)
                .accessibilityLabel("Guided setup progress")
            Text(step.title)
                .font(.title3.weight(.semibold))
            Text(step.explanation)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text(step.nextAction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if hasUnappliedEdits {
                Label("Unapplied edits. Review & apply below before Next. Skip leaves the draft unsaved.",
                      systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button("End guide", action: onExit).buttonStyle(.borderless)
                Spacer()
                if canGoBack {
                    Button("Back", action: onBack).disabled(!canAdvance)
                }
                if index < total - 1 {
                    Button(hasUnappliedEdits ? "Skip without applying" : "Skip step", action: onSkip)
                        .buttonStyle(.borderless)
                        .disabled(!canAdvance)
                }
                Button(index == total - 1 ? "Finish" : "Next", action: onNext)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance || hasUnappliedEdits)
            }
        }
        .padding(18)
        .frame(maxWidth: SetupDesign.pageWidth, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1))
    }
}
