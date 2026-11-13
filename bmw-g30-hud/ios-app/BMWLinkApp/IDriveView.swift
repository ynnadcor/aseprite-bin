// SPDX-License-Identifier: MIT
// iDrive tab: a catalog of known, reversible G30 / NBT EVO coding changes you
// make in BimmerCode. BMW Link reads your coding but never writes it, so this
// is a guide, not a control panel. Themes and extra apps need a head-unit
// unlock and aren't here (see docs/idrive-customization.md).
import SwiftUI
import BMWLinkKit

struct IDriveView: View {
    @ObservedObject var vm: DiagnosticsViewModel
    private let catalog = IDriveCatalog.shared
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    introCard
                    ForEach(catalog.usedCategories, id: \.self) { category in
                        categoryCard(category)
                    }
                    deepModCard
                    Text("These are known changes for a G30 with NBT EVO. Which ones your car supports depends on its equipment and software — BimmerCode shows the ones that apply. All are reversible. BMW Link reads your coding; it never writes it.")
                        .font(.caption)
                        .foregroundColor(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 70)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("iDrive")
            .navigationDestination(for: String.self) { id in
                if let t = catalog.tweak(id) { IDriveTweakDetail(tweak: t, scan: vm.codeScan) }
            }
            .onAppear(perform: runScreenshotDemo)
        }
    }

    private var introCard: some View {
        Card {
            HStack {
                StatusPill(text: "Customize iDrive", systemImage: "slider.horizontal.3", color: Theme.accent)
                Spacer()
                StatusPill(text: "You apply in BimmerCode", systemImage: "hand.tap", color: Theme.secondary)
            }
            Text("Your car has iDrive features switched off from the factory. BimmerCode turns them on. Pick a change below for exactly what it does and where to find it — then make it in BimmerCode. Everything here is reversible.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            headUnitHint
        }
    }

    @ViewBuilder
    private var headUnitHint: some View {
        if let scan = vm.codeScan {
            let hu = scan.modules.first { $0.address == 0x63 && $0.answered } != nil
            Label(hu ? "Your head unit answered the last scan, so these apply to your car."
                     : "Your head unit didn't answer the last scan. Run a scan on the Codes tab to confirm it's reachable.",
                  systemImage: hu ? "checkmark.seal" : "exclamationmark.circle")
                .font(.caption)
                .foregroundColor(hu ? Theme.good : Theme.warn)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Label("Tip: run a scan on the Codes tab first and the app will confirm your car has each module these changes touch.",
                  systemImage: "lightbulb")
                .font(.caption)
                .foregroundColor(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func categoryCard(_ category: String) -> some View {
        Card(title: category, systemImage: icon(category)) {
            ForEach(catalog.tweaks(in: category)) { t in
                NavigationLink(value: t.id) { TweakRow(tweak: t) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var deepModCard: some View {
        Card(title: "Change the look, or add apps?", systemImage: "paintbrush") {
            Text("Reskinning iDrive or adding native apps to it is a different road: it needs the head unit unlocked, which can brick it. That isn't coding and isn't in this list. Ask in chat and I'll lay out the real path, risks and recovery — honestly.")
                .font(.callout)
                .foregroundColor(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Want gauges on the iDrive screen? Turn on Sport displays under Displays & HUD — that's BMW's own, no unlock needed.")
                .font(.caption)
                .foregroundColor(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func icon(_ category: String) -> String {
        switch category {
        case "Apple CarPlay": return "apple.logo"
        case "Displays & HUD": return "gauge.with.dots.needle.33percent"
        case "Media & video": return "play.rectangle"
        case "Navigation": return "map"
        case "Phone & voice": return "phone"
        case "Comfort": return "sparkles"
        case "Startup & appearance": return "paintpalette"
        case "Menus": return "square.grid.2x2"
        default: return "slider.horizontal.3"
        }
    }

    private func runScreenshotDemo() {
        guard ScreenshotMode.tab == "idrive" else { return }
        if let id = ScreenshotMode.value("-screenshotTweak"), catalog.tweak(id) != nil,
           path.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { path = [id] }
        }
    }
}

/// Risk dot + green/amber colour for a tweak.
private func riskColor(_ risk: IDriveTweak.Risk) -> Color { risk == .green ? Theme.good : Theme.warn }

struct TweakRow: View {
    let tweak: IDriveTweak

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(riskColor(tweak.risk)).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(tweak.title).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                Text(tweak.what)
                    .font(.caption)
                    .foregroundColor(Theme.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundColor(Theme.secondary)
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct IDriveTweakDetail: View {
    let tweak: IDriveTweak
    let scan: CodeScan?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                Card(title: "What it does", systemImage: "info.circle") {
                    Text(tweak.what).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Text(tweak.why).font(.callout).foregroundColor(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Card(title: "How to do it", systemImage: "wrench.and.screwdriver") {
                    Label(tweak.how, systemImage: "arrow.right.circle")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("You make this change in BimmerCode. BMW Link reads your coding but doesn't change it.")
                        .font(.caption).foregroundColor(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let needs = tweak.needs {
                    Card(title: "Your car needs", systemImage: "checklist") {
                        Text(needs).font(.callout).fixedSize(horizontal: false, vertical: true)
                        moduleLine
                    }
                } else {
                    Card { moduleLine }
                }
                if let caveat = tweak.caveat {
                    Card(title: "Worth knowing", systemImage: "exclamationmark.triangle") {
                        Text(caveat).font(.callout).foregroundColor(Theme.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Card(title: "How to undo it", systemImage: "arrow.uturn.backward") {
                    Text(tweak.undo).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(tweak.category)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(tweak.title).font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                StatusPill(text: tweak.risk == .green ? "Reversible" : "Reversible · caveat",
                           systemImage: tweak.risk == .green ? "checkmark.shield" : "exclamationmark.shield",
                           color: riskColor(tweak.risk))
            }
            Label(tweak.module, systemImage: "cpu").font(.subheadline).foregroundColor(Theme.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(riskColor(tweak.risk).opacity(0.4)))
    }

    @ViewBuilder
    private var moduleLine: some View {
        let answered = tweak.moduleAnswered(in: scan)
        HStack(spacing: 8) {
            Image(systemName: answered == true ? "checkmark.seal.fill"
                                               : answered == false ? "questionmark.circle" : "cpu")
                .foregroundColor(answered == true ? Theme.good : Theme.secondary)
            Text(answered == true ? "Your car answered for the \(tweak.module) in the last scan."
                 : answered == false ? "The \(tweak.module) didn't answer the last scan — re-scan to confirm."
                 : "Lives in the \(tweak.module). Scan on the Codes tab to confirm your car has it.")
                .font(.caption).foregroundColor(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
