// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProxyBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ProxyBar", targets: ["ProxyBar"]),
        .library(name: "ProxyBarCore", targets: ["ProxyBarCore"])
    ],
    targets: [
        .target(name: "ProxyBarCore"),
        .executableTarget(
            name: "ProxyBar",
            dependencies: ["ProxyBarCore"]
        ),
        .executableTarget(
            name: "ProxyBarCoreTests",
            dependencies: ["ProxyBarCore"],
            path: "Tests/ProxyBarCoreTests"
        ),
        .executableTarget(
            name: "IconGenerator",
            path: "Tools/IconGenerator"
        )
    ]
)
