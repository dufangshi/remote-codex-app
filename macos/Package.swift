// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RemoteCodexMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "RemoteCodexMac", targets: ["RemoteCodexMac"])],
    targets: [
        .target(name: "RemoteCodexCore"),
        .executableTarget(name: "RemoteCodexMac", dependencies: ["RemoteCodexCore"]),
        .testTarget(name: "RemoteCodexCoreTests", dependencies: ["RemoteCodexCore"]),
    ]
)
