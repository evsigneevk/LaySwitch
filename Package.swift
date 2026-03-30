// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LaySwitch",
    platforms: [.macOS(.v15)],
    targets: [
        // Business-logic library — everything except the @main entry point.
        // App/ is excluded: AppDelegate.swift uses @main (executable-only) and
        // Info.plist is a bundle resource, neither belongs in a library target.
        .target(
            name: "LaySwitch",
            path: "LaySwitch",
            exclude: ["App"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "LaySwitchTests",
            dependencies: ["LaySwitch"],
            path: "LaySwitchTests"
        ),
    ]
)
