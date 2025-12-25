// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StillMusicWhenBack",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "StillMusicWhenBack",
            targets: ["StillMusicWhenBack"]
        )
    ],
    targets: [
        .executableTarget(
            name: "StillMusicWhenBack",
            path: "Sources"
        )
    ]
)
