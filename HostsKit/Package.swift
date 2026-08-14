// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HostsKit",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "HostsKit", targets: ["HostsKit"]),
    ],
    targets: [
        .target(name: "HostsKit", resources: [.process("Localizable.xcstrings")]),
        .testTarget(name: "HostsKitTests", dependencies: ["HostsKit"]),
    ]
)
