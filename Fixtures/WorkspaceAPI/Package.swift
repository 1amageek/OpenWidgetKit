// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "OpenWidgetKitWorkspaceAPIFixture",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(name: "OpenWidgetKit", path: "../.."),
        .package(name: "OpenCoreGraphics", path: "../../../OpenCoreGraphics")
    ],
    targets: [
        .target(
            name: "OpenWidgetKitWorkspaceAPIFixture",
            dependencies: [
                .product(name: "WidgetKit", package: "OpenWidgetKit"),
                .product(name: "OpenCoreGraphics", package: "OpenCoreGraphics")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
