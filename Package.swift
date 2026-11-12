// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "cleanmac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "cleanmac", targets: ["cleanmac"])
    ],
    targets: [
        .executableTarget(
            name: "cleanmac",
            path: "Sources/cleanmac"
        )
    ]
)
