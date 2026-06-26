// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HostsKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "HostsKit", targets: ["HostsKit"]),
    ],
    targets: [
        .target(name: "HostsKit"),
        .testTarget(name: "HostsKitTests", dependencies: ["HostsKit"]),
    ]
)
