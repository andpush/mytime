// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyTime",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MyTime", targets: ["MyTime"])
    ],
    targets: [
        .executableTarget(
            name: "MyTime",
            path: "Sources/MyTime"
        ),
        .testTarget(
            name: "MyTimeTests",
            dependencies: ["MyTime"],
            path: "Tests/MyTimeTests"
        )
    ]
)
