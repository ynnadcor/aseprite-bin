// SPDX-License-Identifier: MIT
import SwiftUI

/// Root: four tools. The first three share one read-only connection to the car.
///  - iDrive: a guide to reversible iDrive coding changes you make in BimmerCode
///    (IDriveCatalog). Reads your coding on the Codes tab; never writes it.
///  - Codes: scan every module for fault codes and explain them (BMWLinkKit).
///  - Car: find the car on the ENET cable, identify it, Test 2.
///  - HUD: navigation -> HUD frame preview with an Apple MapKit route source
///    (NavHUDKit). The HUD tab never talks to the car.
struct ContentView: View {
    enum Tab: Hashable { case idrive, codes, car, hud }

    @StateObject private var car = DiagnosticsViewModel()
    @State private var tab: Tab = {
        switch ScreenshotMode.tab {
        case "codes": return .codes
        case "car": return .car
        case "hud": return .hud
        case "idrive": return .idrive
        default: return .codes
        }
    }()

    var body: some View {
        TabView(selection: $tab) {
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
