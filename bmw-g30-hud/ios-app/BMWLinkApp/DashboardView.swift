// SPDX-License-Identifier: MIT
// Dashboard: the G-meter, from the iPhone's own motion sensors.
import SwiftUI
import BMWLinkKit

struct DashboardView: View {
    @StateObject private var model = GMeterModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    meterCard
                    peaksCard
                    controlsCard
                    Text("Glance only when it's safe: mount the phone and don't handle it while driving.")
                        .font(.caption)
                        .foregroundColor(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Dashboard")
            .onAppear { model.start() }
            .onDisappear { model.stop() }
        }
    }

    private var meterCard: some View {
        Card(title: "G-meter", systemImage: "scope") {
            HStack {
                StatusPill(text: model.practice ? "Practice" : (model.calibrated ? "Live" : "Not calibrated"),
                           systemImage: model.practice ? "play.circle" : "waveform.path.ecg",
                           color: model.practice ? Theme.warn : (model.calibrated ? Theme.good : Theme.secondary))
                Spacer()
                Text(String(format: "%.2f g", model.tracker.current.total))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            GMeterDial(tracker: model.tracker)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
            HStack {
                readout(model.tracker.current.lateral >= 0 ? "Left turn" : "Right turn",
                        abs(model.tracker.current.lateral))
                Divider().frame(height: 34)
                readout(model.tracker.current.longitudinal >= 0 ? "Braking" : "Accelerating",
                        abs(model.tracker.current.longitudinal))
            }
            if !model.status.isEmpty {
                Text(model.status).font(.caption).foregroundColor(Theme.secondary)
            }
        }
    }

    private func readout(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundColor(Theme.secondary)
            Text(String(format: "%.2f g", value))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var peaksCard: some View {
        Card(title: "Peaks", systemImage: "chart.line.uptrend.xyaxis") {
            Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    peak("Braking", model.tracker.peakBraking)
                    peak("Accelerating", model.tracker.peakAccelerating)
                }
                GridRow {
                    peak("Left turn", model.tracker.peakLeftTurn)
                    peak("Right turn", model.tracker.peakRightTurn)
                }
                GridRow {
                    peak("Most combined", model.tracker.peakTotal)
                    Color.clear.frame(height: 1)
                }
            }
        }
    }

    private func peak(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundColor(Theme.secondary)
            Text(String(format: "%.2f g", value))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controlsCard: some View {
        Card(title: "Setup", systemImage: "slider.horizontal.3",
             footer: "Mount the phone upright facing you (or flat, top edge forward). Tap Calibrate while parked. "
                + "The dot shows the force you feel: it moves up when you brake and right when you turn left.") {
            HStack(spacing: 10) {
                Button("Calibrate") { model.calibrate() }
                    .buttonStyle(FilledButtonStyle())
                    .disabled(model.practice)
                Button("Reset peaks") { model.resetPeaks() }
                    .buttonStyle(FilledButtonStyle(prominent: false))
            }
            Toggle("Practice data", isOn: Binding(get: { model.practice }, set: { model.setPractice($0) }))
                .disabled(!model.sensorsAvailable)
            Toggle("Phone faces the windshield", isOn: $model.flipped)
        }
    }
}

/// Rings every 0.25 g up to 1.25 g, a fading trail and the current dot.
struct GMeterDial: View {
    let tracker: GForceTracker
    var fullScale = 1.25

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = side / 2 - 18
            func point(_ s: GForceTracker.Sample) -> CGPoint {
                let k = radius / fullScale
                // Up = braking (pushed forward); right = turning left (pushed right).
                return CGPoint(x: center.x + CGFloat(max(-fullScale, min(fullScale, s.lateral))) * k,
                               y: center.y - CGFloat(max(-fullScale, min(fullScale, s.longitudinal))) * k)
            }

            for i in 1...5 {
                let r = radius * CGFloat(i) / 5
                let ring = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                context.stroke(ring, with: .color(.white.opacity(i == 4 ? 0.28 : 0.12)), lineWidth: i == 4 ? 1.5 : 1)
            }
            var cross = Path()
            cross.move(to: CGPoint(x: center.x - radius, y: center.y))
            cross.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            cross.move(to: CGPoint(x: center.x, y: center.y - radius))
            cross.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            context.stroke(cross, with: .color(.white.opacity(0.12)), lineWidth: 1)

            if tracker.peakTotal > 0.02 {
                let r = radius * CGFloat(min(tracker.peakTotal, fullScale) / fullScale)
                let peak = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                context.stroke(peak, with: .color(Theme.warn.opacity(0.55)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }

            let trail = tracker.trail
            if trail.count > 1 {
                for i in 1..<trail.count {
                    var seg = Path()
                    seg.move(to: point(trail[i - 1]))
                    seg.addLine(to: point(trail[i]))
                    let alpha = Double(i) / Double(trail.count)
                    context.stroke(seg, with: .color(Theme.accent.opacity(alpha * 0.8)), lineWidth: 3)
                }
            }

            let p = point(tracker.current)
            let glow = Path(ellipseIn: CGRect(x: p.x - 16, y: p.y - 16, width: 32, height: 32))
            context.fill(glow, with: .color(Theme.accent.opacity(0.25)))
            let dot = Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18))
            context.fill(dot, with: .color(.white))

            func label(_ text: String, _ at: CGPoint) {
                context.draw(Text(text).font(.caption2.weight(.semibold)).foregroundColor(Theme.secondary), at: at)
            }
            label("BRAKE", CGPoint(x: center.x, y: center.y - radius - 9))
            label("ACCEL", CGPoint(x: center.x, y: center.y + radius + 9))
            label("1.0 g", CGPoint(x: center.x + radius * 0.8 + 16, y: center.y - 8))
        }
    }
}
