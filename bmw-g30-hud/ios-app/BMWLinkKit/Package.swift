// swift-tools-version:5.9
// SPDX-License-Identifier: MIT
//
// Two libraries for the iOS app:
//  - BMWLinkKit: read-only ENET/DoIP/UDS diagnostics (Modules 1 & 2).
//  - NavHUDKit:  navigation events -> BMW HUD/KOMBI frames, plus an Apple
//                MapKit route source (Modules 3 & 4).
// Both are pure Swift + Foundation at their core, so they build and test on
// Linux as well as Apple platforms. Network.framework and MapKit pieces are
// compiled only where those frameworks exist.
import PackageDescription

let package = Package(
    name: "BMWLinkKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "BMWLinkKit", targets: ["BMWLinkKit"]),
        .library(name: "NavHUDKit", targets: ["NavHUDKit"]),
    ],
    targets: [
        .target(
            name: "BMWLinkKit",
            path: "Sources/BMWLinkKit"
        ),
        .target(
            name: "NavHUDKit",
            path: "Sources/NavHUDKit"
        ),
        .testTarget(
            name: "BMWLinkKitTests",
            dependencies: ["BMWLinkKit"],
            path: "Tests/BMWLinkKitTests"
        ),
        .testTarget(
            name: "NavHUDKitTests",
            dependencies: ["NavHUDKit"],
            path: "Tests/NavHUDKitTests"
        ),
    ]
)
