// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CloudYield",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "CloudYield",
            targets: ["CloudYield"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CloudYield",
            path: "Sources"
        )
    ]
)
