// SPDX-License-Identifier: MIT
import SwiftUI

/// Root: two independent tools.
///  - Diagnostics: read-only ENET session with the car (BMWLinkKit).
///  - HUD: navigation -> HUD frame preview, with an Apple MapKit route source
///    (NavHUDKit). The HUD tab never talks to the car.
struct ContentView: View {
    var body: some View {
        TabView {
            DiagnosticsView()
                .tabItem { Label("Diagnostics", systemImage: "wrench.and.screwdriver") }
            HudPreviewScreen()
                .tabItem { Label("HUD", systemImage: "arrow.triangle.turn.up.right.diamond") }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
