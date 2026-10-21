// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Amberflow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Amberflow", targets: ["Amberflow"])],
    targets: [
        .executableTarget(name: "Amberflow", path: "Sources/Amberflow"),
        .testTarget(name: "AmberflowTests", dependencies: ["Amberflow"])
    ]
)
