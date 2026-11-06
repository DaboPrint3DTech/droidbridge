// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DroidBridge",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DroidBridge",
            path: "Sources/DroidBridge"
        )
    ]
)
