// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EasyHiDPI",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "EasyHiDPICore"),
        .executableTarget(name: "EasyHiDPI", dependencies: ["EasyHiDPICore"]),
        .testTarget(name: "EasyHiDPICoreTests", dependencies: ["EasyHiDPICore"], resources: [.copy("Fixtures")])
    ]
)
