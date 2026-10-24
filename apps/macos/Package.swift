// swift-tools-version: 6.0
import PackageDescription

// MoostCore（ロジック層）は Foundation のみに依存するため、macOS / Windows の
// 両方でビルド・テストできる（Windows は Swift for Windows のツールチェーン）。
// MoostApp（AppKit / SwiftUI のトレイ UI）は macOS 専用なので、
// Windows では MoostCore とそのテストだけをターゲットに含める。
//
// Windows での制約:
// - `import SQLite3` は macOS SDK のモジュール。Windows では Hermes 読み取りを
//   スタブ化する（HermesSessionReader 内の `#if canImport(SQLite3)`）。
// - CoreGraphics（Kitty のウィンドウ探索）も macOS 専用
//   （Launch.swift 内の `#if canImport(CoreGraphics)`）。
#if os(Windows)
let targets: [Target] = [
    .target(name: "MoostCore"),
    .testTarget(name: "MoostCoreTests", dependencies: ["MoostCore"],
                resources: [.copy("../spec/testdata")]),
]
#else
let targets: [Target] = [
    // Logic layer. No UI dependency. spec/ fixtures are the CI gate.
    .target(name: "MoostCore"),
    // Tray UI comes in the 2nd increment (AppKit added there).
    .executableTarget(name: "MoostApp", dependencies: ["MoostCore"]),
    .testTarget(name: "MoostCoreTests", dependencies: ["MoostCore"],
                resources: [.copy("../spec/testdata")]),
    // AppModel の状態遷移フロー（ストア注入で実ファイルを使わずに検証）
    .testTarget(name: "MoostAppTests", dependencies: ["MoostApp"]),
]
#endif

let package = Package(
    name: "Moost",
    platforms: [.macOS(.v14)],
    targets: targets
)
