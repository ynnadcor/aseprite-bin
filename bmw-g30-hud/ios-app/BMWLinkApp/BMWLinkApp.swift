// SPDX-License-Identifier: MIT
// SwiftUI entry point for the read-only diagnostics app (Module 5).
//
// This is an iOS App target source set. It depends on the BMWLinkKit Swift
// package (../BMWLinkKit). To build: create an iOS App in Xcode, add these files,
// and add BMWLinkKit as a local Swift Package dependency. See ios-app/README.md.
//
// The Diagnostics tab has a "Simulated car" mode (in-memory MockGateway), so
// the whole flow can be tried in the iOS Simulator with no car and no network.
// "My car (ENET)" talks to the real gateway over the USB-C Ethernet adapter.
import SwiftUI

@main
struct BMWLinkApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
