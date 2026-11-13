// SPDX-License-Identifier: MIT
// Gauges tab: a live performance dashboard laid out like the "M Vitals" screen
// from the reference video, as sub-tabs: Engine, Thermals, Fuel & ignition,
// Chassis (with a live G-meter from the phone's motion sensors). The engine
// data is polled read-only from the car over ENET; the G-meter needs no car.
// Read-only: it only reads values, it changes nothing.
import SwiftUI
import BMWLinkKit

struct GaugesView: View {
    @ObservedObject var vm: DiagnosticsViewModel
    @StateObject private var motion = MotionGauge()
    @State private var sub: SubTab = .engine

    enum SubTab: String, CaseIterable, Identifiable {
        case engine = "Engine", thermals = "Thermals", fuel = "Fuel", chassis = "Chassis"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    Picker("View", selection: $sub) {
                        ForEach(SubTab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch sub {
                    case .engine:
                        boostCard
                        engineCard
                    case .thermals:
                        tempsCard
                    case .fuel:
                        fuelCard
                    case .chassis:
                        chassisCard
                    }
                    Text("Read-only: the app only reads these values, it changes nothing. Engine data updates as fast as the car answers; the G-meter uses the phone's own motion sensors. Don't stare at gauges while driving — glance, like any instrument.")
                        .font(.caption)
                        .foregroundColor(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 70)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Gauges")
            .onAppear(perform: startup)
            .onDisappear { vm.stopGauges(); motion.stop() }
        }
    }

    private func startup() {
        motion.start(simulate: ScreenshotMode.isOn)
        guard ScreenshotMode.tab == "gauges" else { return }
        vm.mode = .practice
        vm.startGauges()
        if let s = ScreenshotMode.value("-screenshotSub"),
           let t = SubTab.allCases.first(where: { $0.rawValue.lowercased() == s.lowercased() }) {
            sub = t
        }
    }

    private var live: LiveSample? { vm.live }

    // MARK: header

    private var headerCard: some View {
        Card {
            HStack {
                if vm.liveRunning {
                    StatusPill(text: vm.liveHz.map { String(format: "Live · %.0f/s", $0) } ?? "Live",
                               systemImage: "dot.radiowaves.left.and.right", color: Theme.good)
                } else {
                    StatusPill(text: "Stopped", systemImage: "pause.circle", color: Theme.secondary)
                }
                Spacer()
                StatusPill(text: "Read-only", systemImage: "lock.shield", color: Theme.good)
            }
            Picker("Connect to", selection: $vm.mode) {
                ForEach(DiagnosticsViewModel.Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(vm.liveRunning)
            if vm.liveRunning {
                Button("Stop", role: .cancel) { vm.stopGauges() }
                    .buttonStyle(FilledButtonStyle(color: Theme.bad, prominent: false))
            } else {
                Button { vm.startGauges() } label: { Label("Start live gauges", systemImage: "play.fill") }
                    .buttonStyle(FilledButtonStyle())
                    .disabled(!vm.canRunGauges)
            }
            Text(vm.mode == .car
                 ? "Reads live values from the engine computer, over and over. Engine idling (parked, in P) or on a drive with a passenger holding the phone."
                 : "A simulated pull so you can see the dashboard move with no car connected.")
                .font(.caption).foregroundColor(Theme.secondary)
            if vm.mode == .car && vm.selected == nil {
                Label("Find the car first on the Car tab (steps 1–2).", systemImage: "arrow.left.circle")
                    .font(.caption).foregroundColor(Theme.warn)
            }
            if let m = vm.liveMessage {
                Text(m).font(.caption).foregroundColor(Theme.warn).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Engine

    private var boostCard: some View {
        Card(title: "Boost", systemImage: "wind") {
            ArcGauge(value: live?.boostPsi ?? 0, range: 0...20, unit: "psi",
                     color: Theme.boostColor(live?.boostPsi ?? 0), peak: vm.peakBoostPsi)
                .frame(height: 190)
            HStack {
                Text(boostDetail).font(.caption).foregroundColor(Theme.secondary)
                Spacer()
                Button { vm.resetPeak() } label: { Label("Reset peak", systemImage: "arrow.counterclockwise") }
                    .font(.caption.weight(.semibold))
                    .disabled(vm.peakBoostPsi == 0)
            }
        }
    }

    private var boostDetail: String {
        guard let s = live, let m = s.manifoldKpa, let b = s.baroKpa else {
            return "Derived from manifold minus outside air pressure."
        }
        return "Manifold \(m) kPa · outside \(b) kPa · peak \(String(format: "%.1f", vm.peakBoostPsi)) psi"
    }

    private var engineCard: some View {
        Card(title: "Engine", systemImage: "speedometer") {
            MiniBar(label: "RPM", value: live?.rpm, range: 0...6500, unit: "",
                    text: live?.rpm.map { String(format: "%.0f", $0) } ?? "—", color: Theme.accent)
            MiniBar(label: "Load", value: live?.loadPct, range: 0...100, unit: "%",
                    text: live?.loadPct.map { String(format: "%.0f%%", $0) } ?? "—", color: Theme.good)
            HStack(spacing: 10) {
                ValueTile(label: "Speed", value: live?.speedKph, unit: "km/h", color: .primary)
                ValueTile(label: "Load", value: live?.loadPct.map { Int($0) }, unit: "%", color: .primary)
                ValueTile(label: "RPM", value: live?.rpm.map { Int($0) }, unit: "", color: .primary)
            }
        }
    }

    // MARK: Thermals

    private var tempsCard: some View {
        Card(title: "Temperatures", systemImage: "thermometer") {
            HStack(spacing: 10) {
                ValueTile(label: "Coolant", value: live?.coolantC, unit: "°C",
                          color: Theme.tempColor(live?.coolantC, warnAt: 105, hotAt: 115))
                ValueTile(label: "Oil", value: live?.oilC, unit: "°C",
                          color: Theme.tempColor(live?.oilC, warnAt: 125, hotAt: 140))
                ValueTile(label: "Intake air", value: live?.intakeAirC, unit: "°C",
                          color: Theme.tempColor(live?.intakeAirC, warnAt: 50, hotAt: 65))
            }
            HStack(spacing: 10) {
                ValueTile(label: "Gearbox", value: nil, unit: "°C", color: .primary, placeholder: "needs capture")
                ValueTile(label: "Ambient", value: nil, unit: "°C", color: .primary, placeholder: "needs capture")
            }
            Text(live?.oilC == nil && vm.liveRunning && vm.mode == .car
                 ? "Oil, gearbox and ambient didn't come back as standard OBD values on this connection; we'll confirm their BMW identifiers from your car's log."
                 : "Gearbox and ambient are BMW-specific values we capture from your car.")
                .font(.caption2).foregroundColor(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Fuel & ignition (BMW-specific, captured later)

    private var fuelCard: some View {
        Card(title: "Fuel & ignition", systemImage: "fuelpump",
             footer: vm.mode == .practice
                ? "In practice mode these are simulated. On your car they're BMW-specific values we capture first (not standard OBD)."
                : "These are BMW-specific values, not standard OBD. Once we capture the right identifiers from your car, they fill in here.") {
            HStack(spacing: 10) {
                ValueTile(label: "Rail fuel", value: live?.railFuelBar.map { Int($0) }, unit: "bar",
                          color: .primary, placeholder: "needs capture")
                ValueTile(label: "Charge req.", value: live?.chargeRequestedPct.map { Int($0) }, unit: "%",
                          color: .primary, placeholder: "needs capture")
                ValueTile(label: "Charge act.", value: live?.chargeActualPct.map { Int($0) }, unit: "%",
                          color: Theme.good, placeholder: "needs capture")
            }
        }
    }

    // MARK: Chassis (G-meter + tyres)

    private var chassisCard: some View {
        VStack(spacing: 14) {
            Card(title: "G-force", systemImage: "scope") {
                GMeterView(tracker: motion.tracker).frame(height: 240)
                HStack {
                    Text(String(format: "%.2f g now · %.2f g peak",
                                motion.tracker.current.total, motion.tracker.peakTotal))
                        .font(.caption).foregroundColor(Theme.secondary)
                    Spacer()
                    Button { motion.recenter() } label: { Label("Re-center", systemImage: "scope") }
                        .font(.caption.weight(.semibold))
                    Button { motion.resetPeaks() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                        .font(.caption.weight(.semibold))
                }
                Text(motion.usingSensors
                     ? "Reading your phone's motion. Mount the phone, then tap Re-center so it knows which way is forward."
                     : "Simulated motion here. On your phone this reads real g-force from its sensors — no car needed.")
                    .font(.caption2).foregroundColor(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Card(title: "Tyres", systemImage: "car.fill",
                 footer: "Tyre pressures and temperatures are BMW-specific values we capture from your car (TPMS).") {
                HStack(spacing: 10) {
                    ValueTile(label: "Front L", value: nil, unit: "bar", color: .primary, placeholder: "needs capture")
                    ValueTile(label: "Front R", value: nil, unit: "bar", color: .primary, placeholder: "needs capture")
                }
                HStack(spacing: 10) {
                    ValueTile(label: "Rear L", value: nil, unit: "bar", color: .primary, placeholder: "needs capture")
                    ValueTile(label: "Rear R", value: nil, unit: "bar", color: .primary, placeholder: "needs capture")
                }
            }
        }
    }
}

// MARK: - gauge components

/// A 270° arc gauge with a big value and an optional peak marker.
struct ArcGauge: View {
    let value: Double
    let range: ClosedRange<Double>
    let unit: String
    var color: Color = Theme.accent
    var peak: Double? = nil

    private func fraction(_ v: Double) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        return span <= 0 ? 0 : CGFloat(min(1, max(0, (v - range.lowerBound) / span)))
    }

    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.08), style: .init(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle().trim(from: 0, to: 0.75 * fraction(value))
                .stroke(color, style: .init(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(135))
            if let peak, peak > range.lowerBound {
                Circle().trim(from: max(0, 0.75 * fraction(peak) - 0.004), to: min(0.75, 0.75 * fraction(peak) + 0.004))
                    .stroke(Theme.warn, style: .init(lineWidth: 20, lineCap: .butt))
                    .rotationEffect(.degrees(135))
            }
            VStack(spacing: 2) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(color)
                Text(unit).font(.caption).foregroundColor(Theme.secondary)
            }
        }
        .padding(8)
    }
}

/// A labelled value tile; shows an em dash (or a placeholder note) when nil.
struct ValueTile: View {
    let label: String
    let value: Int?
    let unit: String
    var color: Color = .primary
    var placeholder: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundColor(Theme.secondary).lineLimit(1)
            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(value)").font(.system(.title2, design: .rounded).weight(.semibold))
                        .monospacedDigit().foregroundColor(color)
                    if !unit.isEmpty { Text(unit).font(.caption2).foregroundColor(Theme.secondary) }
                }
            } else {
                Text(placeholder ?? "—").font(placeholder == nil ? .title2 : .caption2)
                    .foregroundColor(Theme.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A horizontal bar for a 0..max value with a label and text readout.
struct MiniBar: View {
    let label: String
    let value: Double?
    let range: ClosedRange<Double>
    let unit: String
    let text: String
    var color: Color = Theme.accent

    private var fraction: CGFloat {
        guard let v = value else { return 0 }
        let span = range.upperBound - range.lowerBound
        return span <= 0 ? 0 : CGFloat(min(1, max(0, (v - range.lowerBound) / span)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundColor(Theme.secondary)
                Spacer()
                Text(text).font(.system(.callout, design: .rounded).weight(.semibold)).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(color).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 10)
        }
    }
}

/// A scatter-style G-meter: rings at 0.5/1.0/1.5 g, a dot for the current force,
/// a short trail, and a ring at the peak. Forward (accel) is up, braking down.
struct GMeterView: View {
    let tracker: GForceTracker
    private let maxG: Double = 1.5

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let r = side / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                ForEach([0.5, 1.0, 1.5], id: \.self) { g in
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                        .frame(width: side * CGFloat(g / maxG), height: side * CGFloat(g / maxG))
                }
                Path { p in
                    p.move(to: CGPoint(x: center.x - r, y: center.y))
                    p.addLine(to: CGPoint(x: center.x + r, y: center.y))
                    p.move(to: CGPoint(x: center.x, y: center.y - r))
                    p.addLine(to: CGPoint(x: center.x, y: center.y + r))
                }
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                if tracker.peakTotal > 0.05 {
                    Circle().stroke(Theme.warn.opacity(0.5), lineWidth: 1)
                        .frame(width: CGFloat(min(1, tracker.peakTotal / maxG)) * side,
                               height: CGFloat(min(1, tracker.peakTotal / maxG)) * side)
                }
                ForEach(Array(tracker.trail.enumerated()), id: \.offset) { _, s in
                    Circle().fill(Theme.accent.opacity(0.18)).frame(width: 4, height: 4)
                        .position(point(s, center: center, r: r))
                }
                Circle().fill(Theme.accent).frame(width: 16, height: 16)
                    .position(point(tracker.current, center: center, r: r))
                VStack {
                    Text("ACCEL").font(.caption2).foregroundColor(Theme.secondary)
                    Spacer()
                    Text("BRAKE").font(.caption2).foregroundColor(Theme.secondary)
                }
                .frame(height: side)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func point(_ s: GForceTracker.Sample, center: CGPoint, r: CGFloat) -> CGPoint {
        let x = center.x + CGFloat(max(-1, min(1, s.lateral / maxG))) * r
        // longitudinal > 0 is braking (pushed forward) -> move toward BRAKE (down).
        let y = center.y + CGFloat(max(-1, min(1, s.longitudinal / maxG))) * r
        return CGPoint(x: x, y: y)
    }
}
