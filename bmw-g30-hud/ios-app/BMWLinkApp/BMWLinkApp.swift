// SPDX-License-Identifier: MIT
// SwiftUI entry point for the read-only diagnostics app (Module 5).
//
// This is an iOS App target source set. It depends on the BMWLinkKit Swift
// package (../BMWLinkKit). To build: create an iOS App in Xcode, add these files,
// and add BMWLinkKit as a local Swift Package dependency. See ios-app/README.md.
//
// By default the app talks to the in-memory MockEnetServer, so it runs fully in
// the iOS Simulator with no car and no network. Switch to the real ENET
// transport (device + USB-C Ethernet + ENET cable) only when validating on-car.
import SwiftUI

@main
struct BMWLinkApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
