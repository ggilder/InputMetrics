// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "InputMetrics",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "6.29.3"),
    ],
    targets: [
        .executableTarget(
            name: "InputMetrics",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: "InputMetrics/InputMetrics",
            exclude: [
                "Info.plist",
                "InputMetrics.entitlements",
                "Localizable.xcstrings",
                "Media.xcassets",
                "PrivacyInfo.xcprivacy",
            ]
        ),
        .testTarget(
            name: "InputMetricsTests",
            dependencies: ["InputMetrics"],
            path: "InputMetricsTests"
        ),
    ]
)
