// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SteamGameLauncher",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SteamGameLauncher", targets: ["SteamGameLauncher"])],
    targets: [
        .executableTarget(name: "SteamGameLauncher", resources: [.process("Resources")]),
        .testTarget(name: "SteamGameLauncherTests", dependencies: ["SteamGameLauncher"])
    ]
)
