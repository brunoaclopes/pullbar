// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pullbar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Pullbar",
            targets: ["Pullbar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Pullbar",
            path: "Sources/Pullbar"
        )
    ]
)
