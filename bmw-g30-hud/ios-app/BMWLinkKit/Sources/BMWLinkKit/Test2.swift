// SPDX-License-Identifier: MIT
// Test 2 (read-only): find every module with one request they all answer, and
// read standard engine values from the DME. Mirrors tools/bmw_car_test.py.
import Foundation

/// Usual BMW diagnostic addresses (F/G series). Only 0x10, 0x60 and 0x63 are
/// confirmed on the owner's car; the rest are the common assignments.
public enum BMWModules {
    public static let engine: UInt16 = 0x12

    public static let info: [UInt16: ModuleInfo] = Dictionary(uniqueKeysWithValues: [
        ModuleInfo(address: 0x01, short: "ACSM", name: "Crash safety module (ACSM, airbags)",
                   role: "airbags, seatbelt tensioners and crash detection.", kind: .safety,
                   drive: "If the airbag warning light is on, the airbags or seatbelt tensioners may not work "
                       + "in a crash. Have it checked soon."),
        ModuleInfo(address: 0x10, short: "ZGW", name: "Central gateway (ZGW)",
                   role: "the data links between modules and the diagnostic socket.", kind: .network,
                   drive: "Gateway codes are often history from a low battery or a software update. If the car "
                       + "behaves normally, it isn't urgent."),
        ModuleInfo(address: 0x12, short: "DME", name: "Engine computer (DME)",
                   role: "fuel, ignition, turbo boost and emissions.", kind: .drivetrain,
                   drive: "Watch for the engine light and how the engine runs. If it runs normally, drive "
                       + "gently until the code is looked up."),
        ModuleInfo(address: 0x18, short: "EGS", name: "Transmission (EGS)",
                   role: "the automatic transmission's shifting.", kind: .drivetrain,
                   drive: "If shifting is harsh or the car stays in one gear, drive gently and get it checked."),
        ModuleInfo(address: 0x29, short: "DSC", name: "Stability control (DSC)",
                   role: "ABS, traction and stability control, and other brake functions.", kind: .safety,
                   drive: "The brakes still work, but ABS or stability control may be limited while a fault is "
                       + "active. Drive carefully and get it checked."),
        ModuleInfo(address: 0x30, short: "EPS", name: "Power steering (EPS)",
                   role: "the electric power steering.", kind: .safety,
                   drive: "Steering can get heavy while a fault is active. Drive carefully and get it checked."),
        ModuleInfo(address: 0x40, short: "BDC", name: "Body domain controller (BDC)",
                   role: "lights, locks, windows, wipers, keys and other body functions.", kind: .body,
                   drive: "Usually not urgent, unless lights, wipers or locks stop working."),
        ModuleInfo(address: 0x60, short: "KOMBI", name: "Instrument cluster (KOMBI)",
                   role: "the gauges, warning lights and Check Control messages.", kind: .cluster,
                   drive: "Not urgent, unless warning lights or gauges stop working."),
        ModuleInfo(address: 0x63, short: "HU", name: "Head unit (NBT EVO)",
                   role: "the iDrive screen, navigation, media, phone and CarPlay.", kind: .infotainment,
                   drive: "Not a driving-safety issue."),
    ].map { ($0.address, $0) })

    public static let names: [UInt16: String] = info.mapValues(\.name)

    public static func name(_ address: UInt16) -> String { names[address] ?? "Unknown module" }
    public static func describe(_ address: UInt16) -> ModuleInfo { info[address] ?? .unknown(address) }
}

public struct ModuleScanResult: Identifiable, Equatable, Sendable {
    public enum Outcome: String, Sendable { case answered, declined, oddAnswer = "odd answer" }
    public var id: UInt16 { address }
    public let address: UInt16
    public let name: String
    public let outcome: Outcome
    public let detail: String
    public var isKnown: Bool { BMWModules.names[address] != nil }
}

extension IdentifyPlan {
    /// Test 2: the engine computer. Reads only; the MHD tune is not touched.
    public static let engine = IdentifyPlan(targets: [
        ECUTarget(name: "Engine computer (DME)", address: 0x12, addressConfirmed: false,
                  dids: [0xF150, 0xF101] + DIDCatalogue.obdOrder, readDTCs: false),
    ])
}

extension ReadOnlyDiagClient {
    /// One ReadDataByIdentifier F150 to every module at once.
    public func scanModules() throws -> [ModuleScanResult] {
        let req = try UDS.buildReadDataByIdentifier(0xF150)
        var results: [ModuleScanResult] = []
        for (address, answer) in try link.requestFunctional(uds: req) {
            let name = BMWModules.name(address)
            do {
                guard case let .rdbi(r) = try UDS.parseResponse(request: req, response: answer) else {
                    throw UDS.UDSError.malformed("not a ReadDataByIdentifier answer")
                }
                results.append(ModuleScanResult(address: address, name: name, outcome: .answered, detail: r.data.spacedHex))
            } catch let UDS.UDSError.negativeResponse(_, nrc) {
                results.append(ModuleScanResult(address: address, name: name, outcome: .declined, detail: UDS.nrcName(nrc)))
            } catch {
                results.append(ModuleScanResult(address: address, name: name, outcome: .oddAnswer, detail: "\(error)"))
            }
        }
        return results
    }
}

public enum EngineValues {
    /// Boost from manifold minus barometric pressure, if the DME shared both.
    /// (OBD 0B tops out at 255 kPa, about 22 psi of boost at sea level.)
    public static func boost(from report: IdentifyReport) -> String? {
        guard let m = report.raw[0x12 << 16 | 0xF40B]?.first,
              let b = report.raw[0x12 << 16 | 0xF433]?.first else { return nil }
        let kpa = Int(m) - Int(b)
        return String(format: "%.1f psi (%d kPa above outside air)", Double(kpa) * 0.1450377, kpa)
    }
}

extension DIDCatalogue {
    /// Standard OBD values read as UDS identifiers (SAE J1979-2 / ISO 27145
    /// map OBD PID xx to DID F4xx). Whether a 2018 BMW DME shares them this way
    /// is what Test 2 finds out.
    public static let obdOrder: [UInt16] = [0xF40C, 0xF405, 0xF40F, 0xF45C, 0xF40B, 0xF433, 0xF404, 0xF40D]

    public static let obd: [UInt16: DIDMeta] = [
        0xF40C: obdMeta(0xF40C, "Engine speed (OBD 0C)", "rpm") { b in
            b.count >= 2 ? String(format: "%.0f rpm", Double(Int(b[0]) << 8 | Int(b[1])) / 4) : nil },
        0xF405: obdMeta(0xF405, "Coolant temperature (OBD 05)", "°C") { b in b.first.map { "\(Int($0) - 40) °C" } },
        0xF40F: obdMeta(0xF40F, "Intake air temperature (OBD 0F)", "°C") { b in b.first.map { "\(Int($0) - 40) °C" } },
        0xF45C: obdMeta(0xF45C, "Oil temperature (OBD 5C)", "°C") { b in b.first.map { "\(Int($0) - 40) °C" } },
        0xF40B: obdMeta(0xF40B, "Intake manifold pressure (OBD 0B)", "kPa") { b in b.first.map { "\($0) kPa" } },
        0xF433: obdMeta(0xF433, "Barometric pressure (OBD 33)", "kPa") { b in b.first.map { "\($0) kPa" } },
        0xF404: obdMeta(0xF404, "Engine load (OBD 04)", "%") { b in
            b.first.map { String(format: "%.0f %%", Double($0) * 100 / 255) } },
        0xF40D: obdMeta(0xF40D, "Vehicle speed (OBD 0D)", "km/h") { b in b.first.map { "\($0) km/h" } },
    ]

    private static func obdMeta(_ did: UInt16, _ name: String, _ unit: String,
                                _ f: @escaping ([UInt8]) -> String?) -> DIDMeta {
        DIDMeta(did: did, name: name, verified: true, unit: unit, note: "standard OBD value",
                decode: { f($0) ?? $0.spacedHex })
    }
}
