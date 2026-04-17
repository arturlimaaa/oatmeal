// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Oatmeal",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "OatmealCore",
            targets: ["OatmealCore"]
        ),
        .library(
            name: "OatmealEdge",
            targets: ["OatmealEdge"]
        ),
        .library(
            name: "OatmealUI",
            targets: ["OatmealUI"]
        )
    ],
    targets: [
        .target(
            name: "OatmealCore"
        ),
        .target(
            name: "OatmealEdge",
            dependencies: ["OatmealCore"]
        ),
        .target(
            name: "OatmealUI",
            dependencies: ["OatmealCore", "OatmealEdge"],
            path: "Sources/OatmealApp"
        ),
        .testTarget(
            name: "OatmealCoreTests",
            dependencies: ["OatmealCore"]
        ),
        .testTarget(
            name: "OatmealEdgeTests",
            dependencies: ["OatmealCore", "OatmealEdge"]
        ),
        .testTarget(
            name: "OatmealUITests",
            dependencies: ["OatmealUI", "OatmealCore", "OatmealEdge"]
        )
    ]
)
