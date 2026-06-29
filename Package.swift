// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoSlouch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NoSlouch", targets: ["NoSlouch"])
    ],
    targets: [
        .executableTarget(
            name: "NoSlouch",
            path: "Sources/NoSlouch"
        ),
        .testTarget(
            name: "NoSlouchTests",
            dependencies: ["NoSlouch"],
            path: "Tests/NoSlouchTests"
        )
    ]
)
