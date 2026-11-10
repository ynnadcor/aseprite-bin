// SPDX-License-Identifier: MIT
import SwiftUI
import NavHUDKit

/// Preview what the factory HUD/cluster would show for a route: either the
/// built-in demo route or a real route from Apple's MapKit routing, played as a
/// simulated drive. Meant for a parked phone or a passenger - not for watching
/// while driving - and it never sends anything to the car.
struct HudPreviewScreen: View {
    @StateObject private var model = HudPreviewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HudView(frame: model.currentFrame)
                        .listRowInsets(EdgeInsets())
                    Picker("Display", selection: $model.sink) {
                        ForEach(HudPreviewModel.Sink.allCases) { sink in
                            Text(sink.rawValue).tag(sink)
                        }
                    }
                    .pickerStyle(.segmented)
                    playbackControls
                } header: {
                    Text(model.routeTitle.isEmpty ? "Preview" : model.routeTitle)
                } footer: {
                    Text("Simulation only. Nothing is sent to the car.")
                }

                Section("Route source") {
                    Button("Load demo route") { model.loadDemo() }
                    TextField("From (address or place)", text: $model.fromQuery)
                        .textInputAutocapitalization(.words)
                    TextField("To", text: $model.toQuery)
                        .textInputAutocapitalization(.words)
                    Button(model.isRouting ? "Planning…" : "Plan with Apple Maps") {
                        model.planAppleRoute()
                    }
                    .disabled(model.isRouting || model.fromQuery.isEmpty || model.toQuery.isEmpty)
                    if !model.status.isEmpty {
                        Text(model.status).font(.caption).foregroundColor(.secondary)
                    }
                }

                if let event = model.currentEvent {
                    Section("Current nav event") {
                        Text(summary(event))
                            .font(.system(.footnote, design: .monospaced))
                    }
                }

                if !model.stepSummaries.isEmpty {
                    Section("Route steps → maneuvers") {
                        ForEach(Array(model.stepSummaries.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("HUD Preview")
            .onAppear {
                if model.frames.isEmpty { model.loadDemo() }
            }
            .onDisappear { model.stop() }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 28) {
            Button { model.stepBack() } label: {
                Image(systemName: "backward.frame.fill")
            }
            .disabled(!model.canStepBack)
            Button { model.isPlaying ? model.stop() : model.play() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
            }
            Button { model.stepForward() } label: {
                Image(systemName: "forward.frame.fill")
            }
            .disabled(!model.canStepForward)
            Spacer()
            Text(model.frames.isEmpty ? "–" : "\(model.index + 1) / \(model.frames.count)")
                .font(.footnote.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .font(.title3)
        .buttonStyle(.borderless)
    }

    private func summary(_ e: NavEvent) -> String {
        var lines = ["#\(e.eventId) \(e.kind.rawValue)",
                     "maneuver: \(e.maneuver.rawValue)",
                     "to maneuver: \(Int(e.distanceToManeuverM.rounded())) m"]
        if !e.roadName.isEmpty { lines.append("road: \(e.roadName)") }
        if let r = e.roundaboutExit { lines.append("roundabout exit: \(r)") }
        if !e.exitNumber.isEmpty { lines.append("exit: \(e.exitNumber)") }
        if let rem = e.distanceRemainingM { lines.append("remaining: \(Int(rem.rounded())) m") }
        return lines.joined(separator: "\n")
    }
}

struct HudPreviewScreen_Previews: PreviewProvider {
    static var previews: some View { HudPreviewScreen() }
}
