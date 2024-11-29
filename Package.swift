// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SignalRClient",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .library(name: "SignalRClient", targets: ["SignalRClient"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "SignalRClient"
        ),
        .testTarget(name: "SignalRClientTests", dependencies: ["SignalRClient"]),
    ]
)
