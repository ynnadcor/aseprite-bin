// SPDX-License-Identifier: MIT
import SwiftUI

/// Root: three tools.
///  - Dashboard: the G-meter, from the iPhone's own motion sensors.
///  - Car: read-only ENET session with the car (BMWLinkKit), including Test 2.
///  - HUD: navigation -> HUD frame preview with an Apple MapKit route source
///    (NavHUDKit). The HUD tab never talks to the car.
struct ContentView: View {
    enum Tab: Hashable { case dashboard, car, hud }

    @State private var tab: Tab = {
        switch ScreenshotMode.tab {
        case "car": return .car
        case "hud": return .hud
        default: return .dashboard
        }
    }()

    var body: some View {
        TabView(selection: $tab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "speedometer") }
                .tag(Tab.dashboard)
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
