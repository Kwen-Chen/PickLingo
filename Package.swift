// swift-tools-version: 5.9
import PackageDescription

// A lightweight harness for regression tests; Xcode remains the app build entry point.
let package = Package(
    name: "PickLingo",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PickLingoCore", targets: ["PickLingoCore"])],
    targets: [
        .target(
            name: "PickLingoCore",
            path: "PickLingo",
            exclude: ["App/SelectTranslateApp.swift", "Info.plist", "SelectTranslate.entitlements", "Resources"]
        ),
        .testTarget(name: "PickLingoTests", dependencies: ["PickLingoCore"], path: "Tests/PickLingoTests")
    ]
)
