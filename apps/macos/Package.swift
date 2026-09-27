// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Moost",
    platforms: [.macOS(.v14)],
    targets: [
        // Logic layer. No UI dependency. spec/ fixtures are the CI gate.
        .target(name: "MoostCore"),
        // Tray UI comes in the 2nd increment (AppKit added there).
        .executableTarget(name: "MoostApp", dependencies: ["MoostCore"]),
        .testTarget(name: "MoostCoreTests", dependencies: ["MoostCore"], resources: [.copy("../spec/testdata")]),
    ]
)
