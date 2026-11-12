// SPDX-License-Identifier: MIT
// DID catalogue. Mirrors proto/bmwdiag/dids.py. Standard DIDs are stable;
// BMW/B58 candidate live values are flagged `verified = false` until captured
// on the real car (their numbers/scaling are placeholders).
import Foundation

public struct DIDMeta {
    public let did: UInt16
    public let name: String
    public let verified: Bool
    public let unit: String
    public let note: String
    public let decode: (([UInt8]) -> String)?
}

public enum DIDCatalogue {
    static func ascii(_ b: [UInt8]) -> String {
        String(bytes: b, encoding: .ascii)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""
    }

    /// Hex, plus the printable ASCII reading when the bytes look like text.
    static func hexAndText(_ b: [UInt8]) -> String {
        let printable = b.filter { $0 >= 0x20 && $0 < 0x7F }
        let hex = b.spacedHex
        if !b.isEmpty && printable.count * 10 >= b.count * 8 {
            return "\(hex)  \"\(ascii(b))\""
        }
        return hex
    }

    public static let standard: [UInt16: DIDMeta] = [
        0xF190: DIDMeta(did: 0xF190, name: "VIN", verified: true, unit: "", note: "ISO VIN",
                        decode: DIDCatalogue.ascii),
        0xF18C: DIDMeta(did: 0xF18C, name: "ECU serial", verified: true, unit: "", note: "",
                        decode: DIDCatalogue.ascii),
        0xF191: DIDMeta(did: 0xF191, name: "ECU hardware number", verified: true, unit: "", note: "",
                        decode: DIDCatalogue.ascii),
        0xF194: DIDMeta(did: 0xF194, name: "Supplier software version", verified: true, unit: "", note: "",
                        decode: DIDCatalogue.ascii),
        0xF195: DIDMeta(did: 0xF195, name: "Application software version", verified: true, unit: "", note: "",
                        decode: DIDCatalogue.ascii),
        0xF197: DIDMeta(did: 0xF197, name: "System / ECU name", verified: true, unit: "", note: "",
                        decode: DIDCatalogue.ascii),
        // BMW identification data (read-only). Contents are BMW-specific, so
        // they are shown as hex for analysis rather than decoded.
        0xF150: DIDMeta(did: 0xF150, name: "BMW ECU variant index (F150)", verified: false, unit: "",
                        note: "BMW-specific; shown raw", decode: DIDCatalogue.hexAndText),
        0xF101: DIDMeta(did: 0xF101, name: "BMW software list, SVK (F101)", verified: false, unit: "",
                        note: "BMW-specific; decoded by SoftwareList", decode: SoftwareList.describe),
    ]

    public static let bmwCandidates: [UInt16: DIDMeta] = [
        0xDD01: DIDMeta(did: 0xDD01, name: "Coolant temp (candidate)", verified: false, unit: "°C",
                        note: "UNVERIFIED — confirm DID & scaling on-car",
                        decode: { b in b.first.map { "\(Int($0) - 40)" } ?? "" }),
        0xDD02: DIDMeta(did: 0xDD02, name: "Intake air temp (candidate)", verified: false, unit: "°C",
                        note: "UNVERIFIED — confirm DID & scaling on-car",
                        decode: { b in b.first.map { "\(Int($0) - 40)" } ?? "" }),
        0xDD03: DIDMeta(did: 0xDD03, name: "Oil temp (candidate)", verified: false, unit: "°C",
                        note: "UNVERIFIED — confirm DID & scaling on-car",
                        decode: { b in b.first.map { "\(Int($0) - 40)" } ?? "" }),
        0xDD04: DIDMeta(did: 0xDD04, name: "Charge/boost pressure (candidate)", verified: false, unit: "mbar",
                        note: "UNVERIFIED — confirm DID & scaling on-car",
                        decode: { b in b.count >= 2 ? "\(Int(b[0]) << 8 | Int(b[1]))" : "" }),
        0xDD05: DIDMeta(did: 0xDD05, name: "Engine load (candidate)", verified: false, unit: "%",
                        note: "UNVERIFIED — confirm DID & scaling on-car",
                        decode: { b in b.first.map { String(format: "%.0f", Double($0) * 100.0 / 255.0) } ?? "" }),
    ]

    public static func lookup(_ did: UInt16) -> DIDMeta? {
        standard[did] ?? bmwCandidates[did]
    }
}
