// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SignalRClient",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .library(name: "SignalRClient", targets: ["SignalRClient"])
    ],
    dependencies: [
        .package(url: "https://github.com/hirotakan/MessagePacker.git", .exact("0.4.7"))
    ],
    targets: [
        .target(
            name: "SignalRClient",
            dependencies: [
                .product(name: "MessagePacker", package: "MessagePacker")
            ]
        ),
        .testTarget(
            name: "SignalRClientTests", dependencies: ["SignalRClient"],
            swiftSettings: [
//                .enableExperimentalFeature("StrictConcurrency")
              ]
        ),
    ]
)
