// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tokenomics",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Tokenomics",
            path: "Tokenomics",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
