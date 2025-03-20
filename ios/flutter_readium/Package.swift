// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Created by following https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors

import PackageDescription

let package = Package(
    // TODO: Update your plugin name.
    name: "flutter_readium",
    platforms: [
        .iOS("13.4"),
        .macOS("10.15")
    ],
    products: [
        .library(name: "flutter-readium", targets: ["flutter_readium"])
    ],
    dependencies: [
      .package(url: "https://github.com/readium/swift-toolkit.git", .upToNextMinor(from: "3.1.0")),
      .package(url: "https://github.com/mxcl/PromiseKit", .upToNextMinor(from: "6.8.0"))
    ],
    targets: [
        .target(
            name: "flutter_readium",
            dependencies: [
              .product(name: "ReadiumShared", package: "swift-toolkit"),
              .product(name: "ReadiumStreamer", package: "swift-toolkit"),
              .product(name: "ReadiumNavigator", package: "swift-toolkit"),
              .product(name: "ReadiumOPDS", package: "swift-toolkit"),
              .product(name: "ReadiumAdapterGCDWebServer", package: "swift-toolkit"),
              .product(name: "PromiseKit", package: "PromiseKit"),
            ],
            resources: [
                // TODO: If your plugin requires a privacy manifest
                // (e.g. if it uses any required reason APIs), update the PrivacyInfo.xcprivacy file
                // to describe your plugin's privacy impact, and then uncomment this line.
                // For more information, see:
                // https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
                .process("PrivacyInfo.xcprivacy"),

                // TODO: If you have other resources that need to be bundled with your plugin, refer to
                // the following instructions to add them:
                // https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
            ]
        )
    ]
)
