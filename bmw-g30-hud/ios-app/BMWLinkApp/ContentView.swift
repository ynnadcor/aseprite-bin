// SPDX-License-Identifier: MIT
import SwiftUI

/// Root: two tools.
///  - Car: read-only ENET session with the car (BMWLinkKit), including Test 2.
///  - HUD: navigation -> HUD frame preview with an Apple MapKit route source
///    (NavHUDKit). The HUD tab never talks to the car.
struct ContentView: View {
    enum Tab: Hashable { case car, hud }

    @State private var tab: Tab = ScreenshotMode.tab == "hud" ? .hud : .car

    var body: some View {
        TabView(selection: $tab) {
            DiagnosticsView()
                .tabItem { Label("Car", systemImage: "car.fill") }
                .tag(Tab.car)
            HudPreviewScreen()
                .tabItem { Label("HUD", systemImage: "arrow.triangle.turn.up.right.diamond") }
                .tag(Tab.hud)
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
