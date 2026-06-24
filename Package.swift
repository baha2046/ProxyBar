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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.3")
    ],
    targets: [
        .target(name: "ProxyBarCore"),
        .executableTarget(
            name: "ProxyBar",
            dependencies: [
                "ProxyBarCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@loader_path/../Frameworks"
                ])
            ]
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
