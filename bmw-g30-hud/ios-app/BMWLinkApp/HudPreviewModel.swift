// SPDX-License-Identifier: MIT
import Foundation
import MapKit
import NavHUDKit

/// Holds a simulated drive (NavEvents), its translated HUD frames, playback
/// state, and Apple MapKit route planning. Nothing here talks to the car.
@MainActor
final class HudPreviewModel: ObservableObject {

    enum Sink: String, CaseIterable, Identifiable {
        case hud = "HUD"
        case kombi = "Cluster"
        var id: String { rawValue }
        var profile: HudProfile { self == .hud ? .g30HUD : .g30KOMBI }
    }

    @Published var sink: Sink = .hud {
        didSet { retranslate() }
    }
    @Published private(set) var events: [NavEvent] = []
    @Published private(set) var frames: [HudFrame] = []
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isRouting = false
    @Published private(set) var routeTitle = ""
    @Published private(set) var stepSummaries: [String] = []
    @Published var status = ""
    @Published var fromQuery = ""
    @Published var toQuery = ""

    private var playTask: Task<Void, Never>?

    var currentFrame: HudFrame? { frames.indices.contains(index) ? frames[index] : nil }
    var currentEvent: NavEvent? { events.indices.contains(index) ? events[index] : nil }
    var canStepBack: Bool { index > 0 }
    var canStepForward: Bool { index + 1 < frames.count }

    // MARK: sources

    func loadDemo() {
        load(DemoRoute.guidance(), title: "Demo route (synthetic, no network)")
        status = ""
    }

    func planAppleRoute() {
        guard !isRouting else { return }
        let from = fromQuery
        let to = toQuery
        isRouting = true
        status = "Searching Apple Maps…"
        Task { [weak self] in
            do {
                guard let start = try await MapKitRouteSource.search(from).first else {
                    throw PlanError.notFound(from)
                }
                let near = start.placemark.coordinate
                guard let end = try await MapKitRouteSource.search(to, near: near).first else {
                    throw PlanError.notFound(to)
                }
                self?.status = "Requesting a driving route…"
                let route = try await MapKitRouteSource.route(from: start, to: end)
                let name = end.name ?? to
                let guidance = MapKitRouteSource.guidance(for: route, destinationName: name)
                let miles = route.distance / 1609.344
                self?.load(guidance, title: "\(start.name ?? from) → \(name) · "
                           + String(format: "%.1f mi", miles))
                self?.status = "Apple Maps route with \(route.steps.count) steps, played as a "
                    + "simulated drive (no GPS). Nothing is sent to the car."
            } catch {
                self?.status = "Route failed: \(error.localizedDescription)"
            }
            self?.isRouting = false
        }
    }

    enum PlanError: Error, LocalizedError {
        case notFound(String)
        var errorDescription: String? {
            switch self {
            case .notFound(let q): return "No Apple Maps result for “\(q)”."
            }
        }
    }

    private func load(_ guidance: RouteGuidance, title: String) {
        stop()
        events = guidance.simulateDrive()
        stepSummaries = zip(guidance.steps, guidance.maneuvers).map { step, m in
            "\(m.maneuver.rawValue) (\(m.basis.rawValue)): \(step.instruction)"
        }
        routeTitle = title
        index = 0
        retranslate()
    }

    private func retranslate() {
        let translator = Translator(profile: sink.profile)
        frames = events.map(translator.translate)
        if index >= frames.count { index = max(0, frames.count - 1) }
    }

    // MARK: playback

    func play() {
        guard !frames.isEmpty, !isPlaying else { return }
        if !canStepForward { index = 0 }
        isPlaying = true
        playTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.canStepForward {
                    self.index += 1
                } else {
                    self.stop()
                    return
                }
            }
        }
    }

    func stop() {
        playTask?.cancel()
        playTask = nil
        isPlaying = false
    }

    func stepForward() {
        stop()
        if canStepForward { index += 1 }
    }

    func stepBack() {
        stop()
        if canStepBack { index -= 1 }
    }
}
