// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Sample",
    platforms: [
        .macOS(.v10_15)
    ],
    dependencies: [
        .package(name: "signalr-client-swift", path: "../")
    ],
    targets: [
        .executableTarget(
            name: "Sample",
            dependencies: [.product(name: "SignalRClient", package: "signalr-client-swift")]
        )
    ]
)
