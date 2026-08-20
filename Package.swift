// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "OpenWidgetKit",
    products: [
        .library(
            name: "SwiftUI",
            targets: ["SwiftUI"]
        ),
        .library(
            name: "WidgetKit",
            targets: ["WidgetKit"]
        )
    ],
    dependencies: [
        .package(path: "../OpenFoundation")
    ],
    targets: [
        .target(
            name: "OpenWidgetRuntime",
            dependencies: [
                .product(name: "OpenFoundation", package: "OpenFoundation")
            ]
        ),
        .target(
            name: "SwiftUI",
            dependencies: [
                "OpenWidgetRuntime",
                .product(name: "OpenFoundation", package: "OpenFoundation")
            ]
        ),
        .target(
            name: "WidgetKit",
            dependencies: [
                "SwiftUI",
                "OpenWidgetRuntime",
                .product(name: "OpenFoundation", package: "OpenFoundation")
            ]
        ),
        .target(
            name: "OpenWidgetKitAPIFixture",
            dependencies: ["SwiftUI", "WidgetKit"],
            path: "Fixtures/SharedAPI"
        ),
        .executableTarget(
            name: "OpenWidgetKitBehaviorFixture",
            dependencies: ["WidgetKit"],
            path: "Fixtures/BehaviorAPI"
        ),
        .testTarget(
            name: "OpenWidgetRuntimeTests",
            dependencies: [
                "OpenWidgetRuntime",
                .product(name: "OpenFoundation", package: "OpenFoundation")
            ]
        ),
        .testTarget(
            name: "WidgetKitTests",
            dependencies: ["WidgetKit", "OpenWidgetRuntime"]
        )
    ],
    swiftLanguageModes: [.v6]
)
