// SPDX-License-Identifier: MIT
// What a set of codes points to together. Each rule is general workshop
// knowledge (shared causes, what to fix first, what happens if ignored),
// worded as "often" or "usually": guidance, not a diagnosis.
import Foundation

public struct CodeFinding: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let checkFirst: [String]
    /// What it can lead to if ignored.
    public let leadsTo: String?
    public let severity: Severity
    /// `FoundCode.id` of every code involved.
    public let codeIDs: [String]
    public let codes: [String]
}

public enum CodePatterns {
    public static func analyze(_ found: [FoundCode]) -> [CodeFinding] {
        let faults = found.filter(\.isFault)
        let sae = faults.filter(\.isSAE)
        var out: [CodeFinding] = []

        func matching(_ test: (String) -> Bool) -> [FoundCode] { sae.filter { test($0.code) } }
        func codes(_ list: [String]) -> [FoundCode] { matching { list.contains($0) } }
        func add(_ id: String, _ title: String, _ severity: Severity, _ involved: [FoundCode],
                 _ detail: String, check: [String] = [], leadsTo: String? = nil) {
            var seen = Set<String>()
            let unique = involved.filter { seen.insert($0.id).inserted }
            var names: [String] = []
            for c in unique where !names.contains(c.code) { names.append(c.code) }
            out.append(CodeFinding(id: id, title: title, detail: detail, checkFirst: check, leadsTo: leadsTo,
                                   severity: severity, codeIDs: unique.map(\.id), codes: names))
        }

        // Engine protection first.
        let protect = codes(["P0217", "P0524"])
        if !protect.isEmpty {
            add("engine-protection", "Engine protection: stop safely", .stop, protect,
                "Overheating or low oil pressure can destroy an engine within minutes.",
                check: ["Stop and switch off as soon as it's safe", "Check coolant and oil levels once cooled down"],
                leadsTo: "Severe engine damage.")
        }

        // Battery and voltage.
        let voltage = codes(["P0562", "P0563", "U3003"])
        if !voltage.isEmpty {
            add("voltage", "Battery or charging problem", .soon, voltage,
                "Voltage problems make other modules store faults too. Fix this first, then scan again: "
                    + "many of the other codes may go away.",
                check: ["Have the battery tested", "Check charging voltage with the engine running",
                        "If the battery was replaced, make sure it was registered to the car"],
                leadsTo: "A no-start and random warnings across the car.")
        }

        // Misfires.
        let misfires = matching { misfireCylinder($0) != nil }
        let random = codes(["P0300"])
        let cylinders = Set(misfires.compactMap { misfireCylinder($0.code) }).sorted()
        var explained = Set<Int>()
        for n in cylinders {
            let coil = matching { coilCylinder($0) == n }
            let injector = matching { injectorCylinder($0) == n }
            let here = misfires.filter { misfireCylinder($0.code) == n }
            if !coil.isEmpty {
                explained.insert(n)
                add("cyl\(n)-coil", "Cylinder \(n): misfire plus a coil fault", .now, here + coil,
                    "Both point to the ignition coil for cylinder \(n) or its connector.",
                    check: ["Swap the coil with a neighbor: if the misfire and the coil code move, replace the coil",
                            "Check the coil's connector"],
                    leadsTo: "Misfires overheat the catalytic converter.")
            } else if !injector.isEmpty {
                explained.insert(n)
                add("cyl\(n)-injector", "Cylinder \(n): misfire plus an injector fault", .now, here + injector,
                    "Both point to the fuel injector for cylinder \(n) or its wiring.",
                    check: ["Check the injector's connector and wiring", "Have the injector tested"],
                    leadsTo: "Misfires overheat the catalytic converter.")
            }
        }
        if cylinders.count >= 2 || (!random.isEmpty && !misfires.isEmpty) {
            add("multi-misfire", "Misfires on several cylinders", .now, random + misfires,
                "When more than one cylinder misfires, look for something they share before replacing coils: "
                    + "spark plugs due for a change, an air or boost leak, low fuel pressure, or carbon on the "
                    + "intake valves.",
                check: ["Check when the spark plugs were last changed", "Look for lean or fuel pressure codes",
                        "Check for air and boost leaks"],
                leadsTo: "Unburned fuel overheats and can ruin the catalytic converter.")
        } else if cylinders.count == 1, let n = cylinders.first, !explained.contains(n) {
            add("cyl\(n)", "Misfire on cylinder \(n) only", .now, misfires,
                "A problem limited to one cylinder is usually its coil or spark plug, sometimes its injector.",
                check: ["Swap the coil with a neighbor: if the misfire moves, it's the coil",
                        "If not, swap the spark plug the same way", "Then check the injector and compression"],
                leadsTo: "Unburned fuel overheats the catalytic converter.")
        }

        let catalyst = codes(["P0420", "P0430"])
        if !catalyst.isEmpty && !(misfires + random).isEmpty {
            add("misfire-catalyst", "Misfires and a catalytic converter code", .now, misfires + random + catalyst,
                "Fix the misfires first. Unburned fuel from misfires overheats the catalytic converter: the "
                    + "converter code may go away once they're fixed, or the converter may already be damaged.",
                check: ["Fix the misfires", "Drive normally for a few days, then scan again"],
                leadsTo: "A ruined catalytic converter, which is expensive.")
        }
        let rearO2 = codes(["P0036", "P0136", "P0137", "P0138", "P0139", "P0140", "P0141"])
        if !catalyst.isEmpty && !rearO2.isEmpty {
            add("catalyst-o2", "Catalyst code with a rear oxygen sensor fault", .soon, catalyst + rearO2,
                "The rear oxygen sensor is how the engine computer judges the catalytic converter. A faulty "
                    + "sensor can cause a false catalyst code, so check it first.",
                check: ["Check the rear oxygen sensor and its wiring before replacing the converter"])
        }

        // Mixture, fuel and air.
        let lean = codes(["P0171", "P0174", "P2177", "P2187", "P2191"])
        if !lean.isEmpty && !(misfires + random).isEmpty {
            add("lean-misfire", "Lean mixture and misfires together", .now, lean + misfires + random,
                "A lean mixture can cause misfires. Look for unmeasured air (vacuum or boost leak, crankcase "
                    + "ventilation) or low fuel pressure before replacing ignition parts.",
                check: ["Smoke test the intake", "Check fuel pressure"],
                leadsTo: "Misfires and, under load, a risk of knock on a turbo engine.")
        }
        let idleLean = codes(["P2187"]), loadLean = codes(["P2177", "P2191"])
        if !idleLean.isEmpty && loadLean.isEmpty {
            add("lean-idle", "Lean only at idle", .soon, idleLean + codes(["P0171"]),
                "A leak matters most at idle: vacuum leak, crankcase ventilation (often the valve cover) or "
                    + "the intake gasket. A smoke test finds these quickly.",
                check: ["Smoke test the intake", "Check the oil filler cap seal"])
        } else if !loadLean.isEmpty && idleLean.isEmpty {
            add("lean-load", "Lean only under load", .soon, loadLean + codes(["P0171"]),
                "Points to fuel delivery (in-tank pump, high-pressure pump, injectors) or the air flow reading "
                    + "rather than a vacuum leak.",
                check: ["Check fuel pressure at full load", "Check the air flow reading"],
                leadsTo: "Under heavy load, a lean turbo engine risks knock and engine damage.")
        }
        let lowFuel = codes(["P0087"])
        if !lowFuel.isEmpty && !lean.isEmpty {
            add("lean-fuel", "Lean mixture with low fuel pressure", .now, lowFuel + lean,
                "The fuel system isn't keeping up. Check the in-tank pump, the filter and the high-pressure pump. "
                    + "On a tuned engine, check that the fuel system can supply what the tune asks for.",
                check: ["Check low-side fuel pressure", "Watch requested vs actual rail pressure under load"],
                leadsTo: "Lean running under load can damage the engine.")
        }
        let underboost = codes(["P0299"]), leakSigns = codes(["P2279", "P0171", "P0068"])
        if !underboost.isEmpty && !leakSigns.isEmpty {
            add("boost-leak", "Underboost plus signs of a leak", .soon, underboost + leakSigns,
                "Together these point to a boost leak: charge pipe, intercooler hoses or clamps. A boost "
                    + "leak test finds it.",
                check: ["Inspect the charge pipe and intercooler hoses", "Do a boost leak test"],
                leadsTo: "Leaks grow, and the turbo works harder.")
        }
        let cam = matching { ["P0010", "P0011", "P0012", "P0013", "P0014", "P0015", "P0016", "P0017"].contains($0) }
        if Set(cam.map(\.code)).count >= 2 {
            add("cam", "Several cam timing codes", .soon, cam,
                "When cam timing disagrees in more than one place, look at shared causes: oil level and "
                    + "condition, oil pressure, then timing chain wear.",
                check: ["Check the oil level and service history", "Have the timing chain checked for stretch"],
                leadsTo: "A worn timing chain can eventually cause severe engine damage.")
        }
        let thermostat = codes(["P0128", "P0597", "P0598", "P0599"])
        if !codes(["P0128"]).isEmpty && thermostat.count >= 2 {
            add("thermostat", "Thermostat", .soon, thermostat,
                "Both point to the thermostat. BMW's electronically controlled thermostat is usually replaced "
                    + "as one part.",
                check: ["Watch coolant temperature after a cold start"])
        }
        let throttle = codes(["P0121", "P0122", "P0123", "P0221", "P0638", "P2101", "P2111", "P2112",
                              "P2119", "P2135", "P2138"])
        if Set(throttle.map(\.code)).count >= 2 {
            add("throttle", "Several throttle or pedal codes", .now, throttle,
                "These usually share one part: the throttle body or its connector and wiring. Expect reduced "
                    + "power mode.",
                check: ["Check the throttle body's connector", "Inspect and clean the throttle body"],
                leadsTo: "Sudden loss of power in traffic.")
        }
        let p0700 = codes(["P0700"])
        if !p0700.isEmpty {
            add("transmission", "The transmission has its own codes", .soon, p0700,
                "P0700 only says the transmission computer stored a fault. Its own codes say what the fault is.",
                check: ["Look at the transmission (EGS) module's codes in this scan"])
        }

        // Network: lost communication.
        let lost = matching { $0.hasPrefix("U01") || $0.hasPrefix("U02") }
        var reporters: [String: Set<UInt16>] = [:]
        for c in lost { reporters[c.code, default: []].insert(c.module) }
        for (code, modules) in reporters.sorted(by: { $0.key < $1.key }) where modules.count >= 2 {
            let target = CodeLibrary.shared.info(code)?.title ?? "Lost communication (\(code))"
            add("lost-\(code)", "Reported by several modules: \(target)", .soon,
                lost.filter { $0.code == code },
                "When several modules lose contact with the same module, that module (or its power, fuse or "
                    + "connector) is the likely cause, not the modules reporting it.",
                check: ["Check that module's fuses and connectors", "Have the battery tested"])
        }
        if reporters.count >= 3 {
            add("lost-many", "Many modules lost contact with each other", .soon, lost,
                "Lost communication with many different modules usually means low voltage or a data bus "
                    + "wiring fault rather than many broken modules.",
                check: ["Have the battery tested", "Check for water in connectors or recent repairs"])
        }

        // BMW codes, by module.
        for (address, label) in [(UInt16(0x01), "Airbag system"), (0x29, "Brakes and stability control"),
                                 (0x30, "Power steering")] {
            let here = faults.filter { $0.module == address }
            guard !here.isEmpty else { continue }
            let info = BMWModules.describe(address)
            let active = here.contains(where: \.isActive)
            add("safety-\(address)", "\(label): fault \(active ? "active" : "stored")",
                active ? .now : .soon, here,
                active ? info.drive
                    : "A stored fault in the \(info.short), not active now. If no warning light is on it may be "
                        + "old history, but a safety system is worth having checked.",
                check: ["Note which warning lights are on", "Have it checked by a workshop"])
        }
        let history = faults.filter { !$0.isSAE && !$0.isActive }
        let historyModules = Set(history.map(\.module))
        if historyModules.count >= 3 {
            add("history", "Old codes in many modules", .info, history,
                "Codes stored in several modules that aren't active now usually come from one event: a weak "
                    + "or disconnected battery, a jump start, or a software update. If the car drives normally, "
                    + "they're most likely history.",
                check: ["Have the battery tested", "Think back: battery replaced, jump start or dealer visit?"])
        }

        // Most urgent first; the order above breaks ties.
        return out.enumerated().sorted { a, b in
            a.element.severity != b.element.severity ? a.element.severity > b.element.severity : a.offset < b.offset
        }.map(\.element)
    }

    /// Findings that involve `code`.
    public static func related(to code: FoundCode, in findings: [CodeFinding]) -> [CodeFinding] {
        findings.filter { $0.codeIDs.contains(code.id) }
    }

    // MARK: code families

    /// P0301-P0312 -> cylinder number.
    public static func misfireCylinder(_ code: String) -> Int? { numbered(code, from: 301, to: 312) }
    /// P0351-P0362 (coil A-L) -> cylinder number, as most engines number them.
    public static func coilCylinder(_ code: String) -> Int? { numbered(code, from: 351, to: 362) }
    /// P0201-P0212 -> cylinder number.
    public static func injectorCylinder(_ code: String) -> Int? { numbered(code, from: 201, to: 212) }

    private static func numbered(_ code: String, from: Int, to: Int) -> Int? {
        guard code.count == 5, code.hasPrefix("P0"), let n = Int(code.dropFirst(2)), (from...to).contains(n) else {
            return nil
        }
        return n - from + 1
    }
}
