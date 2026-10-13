// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacSetup",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "mac-setup", targets: ["MacSetup"])],
    targets: [
        .target(name: "MacSetupCore", resources: [.copy("Resources/Profile")]),
        .executableTarget(name: "MacSetup", dependencies: ["MacSetupCore"]),
        .testTarget(name: "MacSetupCoreTests", dependencies: ["MacSetupCore"])
    ]
)
