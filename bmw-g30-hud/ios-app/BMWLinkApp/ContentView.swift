// SPDX-License-Identifier: MIT
import SwiftUI

/// Root: five tools. The first four share one read-only connection to the car.
///  - Gauges: a live performance dashboard (boost, temps, load, RPM) polled over
///    ENET (BMWLinkKit). The on-the-phone version of the video's "M Vitals" screen.
///  - iDrive: a guide to reversible iDrive coding changes you make in BimmerCode.
///  - Codes: scan every module for fault codes and explain them.
///  - Car: find the car on the ENET cable, identify it, Test 2.
///  - HUD: navigation -> HUD frame preview (NavHUDKit). Never talks to the car.
struct ContentView: View {
    enum Tab: Hashable { case gauges, idrive, codes, car, hud }

    @StateObject private var car = DiagnosticsViewModel()
    @State private var tab: Tab = {
        switch ScreenshotMode.tab {
        case "gauges": return .gauges
        case "idrive": return .idrive
        case "car": return .car
        case "hud": return .hud
        default: return .codes
        }
    }()

    var body: some View {
        TabView(selection: $tab) {
            GaugesView(vm: car)
                .tabItem { Label("Gauges", systemImage: "gauge") }
                .tag(Tab.gauges)
            IDriveView(vm: car)
                .tabItem { Label("iDrive", systemImage: "slider.horizontal.3") }
                .tag(Tab.idrive)
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
