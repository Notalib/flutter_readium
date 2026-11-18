// swift-tools-version: 5.9
// Follows https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors

import PackageDescription

let package = Package(
    name: "flutter_readium_lcp",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "flutter-readium-lcp", targets: ["flutter_readium_lcp"])
    ],
    dependencies: [
      .package(name: "FlutterFramework", path: "../FlutterFramework"),
      // Flutter rewrites this path to the symlinked plugin directory when it generates the app's package.
      .package(name: "flutter_readium", path: "../flutter_readium"),
      .package(url: "https://github.com/readium/swift-toolkit.git", .upToNextMinor(from: "3.11.1"))
    ],
    targets: [
        .target(
            name: "flutter_readium_lcp",
            dependencies: [
              .product(name: "FlutterFramework", package: "FlutterFramework"),
              .product(name: "flutter-readium", package: "flutter_readium"),
              .product(name: "ReadiumShared", package: "swift-toolkit"),
              .product(name: "ReadiumLCP", package: "swift-toolkit"),
            ]
        )
    ]
)
