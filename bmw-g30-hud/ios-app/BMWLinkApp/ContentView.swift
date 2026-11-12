// SPDX-License-Identifier: MIT
import SwiftUI

/// Root: three tools sharing one read-only connection to the car.
///  - Codes: scan every module for fault codes and explain them (BMWLinkKit).
///  - Car: find the car on the ENET cable, identify it, Test 2.
///  - HUD: navigation -> HUD frame preview with an Apple MapKit route source
///    (NavHUDKit). The HUD tab never talks to the car.
struct ContentView: View {
    enum Tab: Hashable { case codes, car, hud }

    @StateObject private var car = DiagnosticsViewModel()
    @State private var tab: Tab = {
        switch ScreenshotMode.tab {
        case "car": return .car
        case "hud": return .hud
        default: return .codes
        }
    }()

    var body: some View {
        TabView(selection: $tab) {
            CodesView(vm: car)
                .tabItem { Label("Codes", systemImage: "stethoscope") }
                .tag(Tab.codes)
            DiagnosticsView(vm: car)
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
