// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CellarKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CellarKit", targets: ["CellarKit"]),
    ],
    targets: [
        .target(name: "CellarKit"),
        .testTarget(
            name: "CellarKitTests",
            dependencies: ["CellarKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
