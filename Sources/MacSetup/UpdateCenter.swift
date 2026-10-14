import AppKit
import SwiftUI
import MacSetupCore

struct UpdateCenter: View {
    @LocalViewState private var release: MacSetupRelease?
    @LocalViewState private var message = ""
    @LocalViewState private var checking = false
    @LocalViewState private var installing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Updates").font(.system(size: 27, weight: .semibold))
                Text("Get new controls and improvements from verified GitHub releases.")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 14) {
                    Label("Installed version: \(MacSetupVersion.installed)", systemImage: "desktopcomputer")
                        .font(.headline)
                    if let release {
                        Text("Latest release: \(release.tag)")
                        Text(MacSetupVersion.isNewer(release.version, than: MacSetupVersion.installed)
                             ? "An update is available." : "This version is up to date.")
                            .foregroundStyle(.secondary)
                        if MacSetupVersion.isNewer(release.version, than: MacSetupVersion.installed) {
                            Button("Install verified update") { install(release) }
                                .buttonStyle(.borderedProminent).disabled(installing)
                        }
                    }
                    HStack {
                        Button(checking ? "Checking..." : "Check for updates") { check() }
                            .disabled(checking || installing)
                        if checking || installing { ProgressView().controlSize(.small) }
                    }
                    if !message.isEmpty {
                        Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                Text("Updates are installed into versioned directories. Restart Mac Setup to use newly installed features. Previous installation versions remain available for recovery.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(28).frame(maxWidth: 850, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .onAppear(perform: check)
    }

    private func check() {
        guard !checking else { return }
        checking = true
        message = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try ReleaseUpdater().latestRelease() }
            DispatchQueue.main.async {
                checking = false
                switch result {
                case .success(let found): release = found
                case .failure(let error): message = "Could not check GitHub releases: \(error)"
                }
            }
        }
    }

    private func install(_ release: MacSetupRelease) {
        installing = true
        message = "Downloading and verifying \(release.tag)..."
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try ReleaseUpdater().install(release) }
            DispatchQueue.main.async {
                installing = false
                switch result {
                case .success: message = "Update installed. Quit and reopen Mac Setup to use the new version."
                case .failure(let error): message = "Update failed without switching to the new version: \(error)"
                }
            }
        }
    }
}
