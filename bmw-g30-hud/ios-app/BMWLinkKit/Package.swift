// swift-tools-version:5.9
// SPDX-License-Identifier: MIT
//
// BMWLinkKit - the read-only ENET/DoIP/UDS core for the iOS app (Module 1 & 2).
// Pure Swift + Foundation core (compiles on macOS and Linux Swift). The real
// Network.framework transport is compiled only where it is available.
//
// NOTE: This package has NOT been compiled in the cloud dev environment used to
// create it (no Swift toolchain there). It is standard SPM and is written to
// mirror, 1:1, the Python reference in ../../proto/bmwdiag, which *is* tested.
import PackageDescription

let package = Package(
    name: "BMWLinkKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "BMWLinkKit", targets: ["BMWLinkKit"]),
    ],
    targets: [
        .target(
            name: "BMWLinkKit",
            path: "Sources/BMWLinkKit"
        ),
        .testTarget(
            name: "BMWLinkKitTests",
            dependencies: ["BMWLinkKit"],
            path: "Tests/BMWLinkKitTests"
        ),
    ]
)
