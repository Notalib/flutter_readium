// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Created by following https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors

import PackageDescription

let package = Package(
    name: "flutter_readium",
    platforms: [
        .iOS("15.0"),
        // macOS: not supported and not planned (swift-toolkit is iOS-only)
    ],
    products: [
        .library(name: "flutter-readium", targets: ["flutter_readium"])
    ],
    dependencies: [
      .package(url: "https://github.com/readium/swift-toolkit.git", .upToNextMinor(from: "3.9.0"))
    ],
    targets: [
        .target(
            name: "flutter_readium",
            dependencies: [
              .product(name: "ReadiumShared", package: "swift-toolkit"),
              .product(name: "ReadiumStreamer", package: "swift-toolkit"),
              .product(name: "ReadiumNavigator", package: "swift-toolkit"),
              .product(name: "ReadiumOPDS", package: "swift-toolkit"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
