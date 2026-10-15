// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacSetup",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "mac-setup", targets: ["MacSetup"]),
               .executable(name: "mac-setup-display", targets: ["MacSetupDisplay"]),
               .executable(name: "mac-setup-wallpaper-watcher", targets: ["MacSetupWatcher"])],
    targets: [
        .target(name: "MacSetupCore", resources: [.copy("Resources/Profile"), .copy("Resources/ReferenceProfile.json"), .copy("Resources/MacSetup.icns")]),
        .executableTarget(name: "MacSetup", dependencies: ["MacSetupCore"]),
        .executableTarget(name: "MacSetupDisplay", dependencies: ["MacSetupCore"]),
        .executableTarget(name: "MacSetupWatcher", dependencies: ["MacSetupCore"]),
        .testTarget(name: "MacSetupCoreTests", dependencies: ["MacSetupCore"])
    ]
)
