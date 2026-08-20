// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "OpenWidgetKit",
    platforms: [
        .macOS(.v15)
    ],
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
                .target(
                    name: "OpenWidgetWindowsRuntime",
                    condition: .when(platforms: [.windows])
                ),
                .product(name: "OpenFoundation", package: "OpenFoundation")
            ]
        ),
        .target(
            name: "OpenWidgetAdaptiveCards",
            dependencies: [
                "OpenWidgetRuntime",
                .product(name: "OpenFoundation", package: "OpenFoundation")
            ]
        ),
        .target(
            name: "COpenWidgetWindowsBridge",
            path: "Sources/COpenWidgetWindowsBridge",
            publicHeadersPath: "include"
        ),
        .target(
            name: "OpenWidgetWindowsRuntime",
            dependencies: [
                "COpenWidgetWindowsBridge",
                "OpenWidgetAdaptiveCards",
                "OpenWidgetRuntime",
                .product(name: "OpenFoundation", package: "OpenFoundation")
            ]
        ),
        .executableTarget(
            name: "openwidget-packager",
            dependencies: [
                "OpenWidgetWindowsRuntime",
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
        .executableTarget(
            name: "OpenWidgetWindowsProviderFixture",
            dependencies: ["WidgetKit"],
            path: "Fixtures/WindowsProvider"
        ),
        .testTarget(
            name: "OpenWidgetRuntimeTests",
            dependencies: [
                "OpenWidgetRuntime",
                .product(name: "OpenFoundation", package: "OpenFoundation")
            ]
        ),
        .testTarget(
            name: "SwiftUITests",
            dependencies: ["SwiftUI", "OpenWidgetRuntime"]
        ),
        .testTarget(
            name: "WidgetKitTests",
            dependencies: ["WidgetKit", "OpenWidgetRuntime"]
        ),
        .testTarget(
            name: "OpenWidgetAdaptiveCardsTests",
            dependencies: [
                "OpenWidgetAdaptiveCards",
                "OpenWidgetRuntime",
                "SwiftUI",
                .product(name: "OpenFoundation", package: "OpenFoundation")
            ]
        ),
        .testTarget(
            name: "OpenWidgetWindowsRuntimeTests",
            dependencies: [
                "OpenWidgetWindowsRuntime",
                "OpenWidgetRuntime",
                "OpenWidgetAdaptiveCards",
                .product(name: "OpenFoundation", package: "OpenFoundation")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
