// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Sample",
    platforms: [
        .macOS(.v10_15)
    ],
    dependencies: [
        .package(url: "https://github.com/dotnet/signalr-client-swift", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "Sample",
            dependencies: [.product(name: "SignalRClient", package: "signalr-client-swift")]
        )
    ]
)
