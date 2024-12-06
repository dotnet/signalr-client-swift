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
        .package(
            url: "https://github.com/inaka/EventSource.git", .branch("master")
        )
    ],
    targets: [
        .target(
            name: "SignalRClient",
            dependencies: [
                .product(name: "EventSource", package: "EventSource")
            ]
        ),
        .testTarget(
            name: "SignalRClientTests", dependencies: ["SignalRClient"]),
    ]
)
