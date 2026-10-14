import Foundation

public struct MacSetupRelease {
    public let version: String
    public let tag: String
    public let archive: URL
    public let checksum: URL
}

public enum MacSetupVersion {
    public static let current = "0.5.0"
    public static var installed: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? current
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.hasPrefix("v") ? String(candidate.dropFirst()) : candidate
        let right = current.hasPrefix("v") ? String(current.dropFirst()) : current
        return left.compare(right, options: .numeric) == .orderedDescending
    }
}

/// Updates only from tagged GitHub releases. Never executes source from main.
/// Every downloaded archive must match the SHA-256 published with that release.
public final class ReleaseUpdater {
    private let fetch: (URL) throws -> Data
    private let runner: CommandRunning
    private let paths: Paths
    private let releasesURL: URL

    public init(paths: Paths = Paths(), runner: CommandRunning = ProcessRunner(timeout: 240),
                releasesURL: URL = URL(string: "https://api.github.com/repos/Roobahist/mac-setup/releases/latest")!,
                fetch: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) }) {
        self.paths = paths
        self.runner = runner
        self.releasesURL = releasesURL
        self.fetch = fetch
    }

    private struct APIRelease: Decodable {
        let tag_name: String
        let assets: [APIAsset]
    }

    private struct APIAsset: Decodable {
        let name: String
        let browser_download_url: URL
    }

    public func latestRelease() throws -> MacSetupRelease {
        let metadata = try JSONDecoder().decode(APIRelease.self, from: fetch(releasesURL))
        let arch = try runner.checked("/usr/bin/uname", ["-m"]).text
        guard ["arm64", "x86_64"].contains(arch) else {
            throw SetupError("No release is available for this Mac architecture: \(arch).")
        }
        let base = "mac-setup-\(metadata.tag_name)-macos-\(arch).tar.gz"
        guard let archive = metadata.assets.first(where: { $0.name == base }),
              let checksum = metadata.assets.first(where: { $0.name == base + ".sha256" }) else {
            throw SetupError("Release \(metadata.tag_name) does not include a complete \(arch) package.")
        }
        for url in [archive.browser_download_url, checksum.browser_download_url] {
            guard url.scheme == "https", url.host == "github.com" else {
                throw SetupError("The release contains an unexpected download host.")
            }
        }
        return MacSetupRelease(version: String(metadata.tag_name.drop(while: { $0 == "v" })),
                               tag: metadata.tag_name,
                               archive: archive.browser_download_url,
                               checksum: checksum.browser_download_url)
    }

    /// The managed installer uses a versioned directory and switches the
    /// 'current' symlink only after a complete installation.
    public func install(_ release: MacSetupRelease) throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-setup-update-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let archive = folder.appendingPathComponent("release.tar.gz")
        try fetch(release.archive).write(to: archive, options: .atomic)
        let expectedData = try fetch(release.checksum)
        guard let expectedText = String(data: expectedData, encoding: .utf8),
              let expected = expectedText.split(whereSeparator: { $0.isWhitespace }).first.map(String.init),
              expected.count == 64,
              expected.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) else {
            throw SetupError("The release checksum file is invalid.")
        }
        let actual = try runner.checked("/usr/bin/shasum", ["-a", "256", archive.path])
            .text.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        guard actual.lowercased() == expected.lowercased() else {
            throw SetupError("Update download failed SHA-256 verification. Nothing was installed.")
        }

        try runner.checked("/usr/bin/tar", ["-xzf", archive.path, "-C", folder.path])
        let architecture = try runner.checked("/usr/bin/uname", ["-m"]).text
        let package = folder.appendingPathComponent("mac-setup-\(release.tag)-macos-\(architecture)")
        let script = package.appendingPathComponent("install.sh")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: package.appendingPathComponent("Mac Setup.app").path) else {
            throw SetupError("The release archive is missing its app or installer.")
        }
        // The repository installer refuses root and preserves previous versions.
        try runner.checked("/bin/bash", [script.path])
    }
}
