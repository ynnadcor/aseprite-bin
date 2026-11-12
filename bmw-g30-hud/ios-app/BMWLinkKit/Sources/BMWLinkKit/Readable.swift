// SPDX-License-Identifier: MIT
// Plain-language readings of BMW identification data. Mirrors
// tools/bmw_car_test.py, whose decoding was checked against the shapes a real
// 2018 G30 returned (17-byte software-list header, 8-byte entries, BCD date;
// fault lists full of "not tested yet" entries).
import Foundation

/// BMW software list (DID F101): a header, then `count` entries of
/// process class (1) + ID (4) + version (3). The header length is derived from
/// the count, so its exact layout doesn't matter.
public struct SoftwareList: Equatable, Sendable {
    public struct Part: Equatable, Sendable {
        public let processClass: String
        public let id: String
        /// "-" when the module gives no version.
        public let version: String
    }

    public let date: String?
    public let parts: [Part]
    public let dependenciesOK: Bool

    public static let classNames: [UInt8: String] = [
        0x01: "HWEL", 0x02: "HWAP", 0x03: "HWFR", 0x04: "GWTB", 0x05: "CAFD", 0x06: "BTLD",
        0x07: "FLSL", 0x08: "SWFL", 0x09: "SWFF", 0x0A: "SWPF", 0x0B: "ONPS", 0x0C: "IBAD",
        0x0F: "FAFP", 0x10: "FCFA", 0x1A: "TLRT", 0x1B: "TPRG", 0x1C: "BLUP", 0x1D: "FLUP",
        0xA0: "ENTD", 0xA1: "NAVD", 0xA2: "FCFN", 0xC0: "SWUP", 0xC1: "SWIP",
    ]

    public static func parse(_ data: [UInt8]) -> SoftwareList? {
        guard data.count >= 4 else { return nil }
        let count = Int(data[2]) << 8 | Int(data[3])
        let header = data.count - 8 * count
        guard count > 0, header >= 7 else { return nil }

        var date: String?
        let d = Array(data[4..<7])
        if d.allSatisfy({ $0 >> 4 <= 9 && $0 & 0x0F <= 9 }) {
            let n = d.map { Int($0 >> 4) * 10 + Int($0 & 0x0F) }
            if (1...12).contains(n[1]) && (1...31).contains(n[2]) {
                date = String(format: "20%02d-%02d-%02d", n[0], n[1], n[2])
            }
        }
        var parts: [Part] = []
        for i in 0..<count {
            let e = Array(data[(header + 8 * i)..<(header + 8 * i + 8)])
            let cls = classNames[e[0]] ?? String(format: "0x%02X", e[0])
            let version = e[5...7].allSatisfy({ $0 == 0xFF }) ? "-" : "\(e[5]).\(e[6]).\(e[7])"
            parts.append(Part(processClass: cls, id: Array(e[1..<5]).hexString.uppercased(), version: version))
        }
        return SoftwareList(date: date, parts: parts, dependenciesOK: data[1] == 0x01)
    }

    /// Short form for the screen: date, part count, software and coding versions.
    public var summary: String {
        var out = ["programmed \(date ?? "?")", "\(parts.count) parts"]
        for (cls, label) in [("SWFL", "software"), ("CAFD", "coding"), ("GWTB", "gateway table")] {
            var versions: [String] = []
            for p in parts where p.processClass == cls && p.version != "-" && !versions.contains(p.version) {
                versions.append(p.version)
            }
            if !versions.isEmpty { out.append("\(label) \(versions.joined(separator: "/"))") }
        }
        return out.joined(separator: "; ")
    }

    /// Every part, for the log.
    public var full: String {
        "programmed \(date ?? "?"), \(parts.count) parts: "
            + parts.map { "\($0.processClass) \($0.id) \($0.version)" }.joined(separator: ", ")
    }

    /// Summary when the bytes are a software list, otherwise hex (and text).
    public static func describe(_ data: [UInt8]) -> String {
        parse(data)?.summary ?? DIDCatalogue.hexAndText(data)
    }
}

/// Fault memory (ReadDTCInformation, status mask FF), in plain words.
public enum FaultMemory {
    /// Status bits that mean a real fault (ISO 14229): failed, failed this cycle,
    /// pending, confirmed, failed since last clear. 0x10 and 0x40 only say
    /// "not tested yet", which BMW modules report for most of their list.
    public static let faultBits: UInt8 = 0x2F

    public static func isFault(_ status: UInt8) -> Bool { status & faultBits != 0 }

    public static func statusText(_ status: UInt8) -> String {
        var words: [String] = []
        if status & 0x01 != 0 { words.append("active now") }
        if status & 0x08 != 0 { words.append("stored") }
        if status & 0x04 != 0 { words.append("pending") }
        if words.isEmpty && status & 0x22 != 0 { words.append("failed earlier") }
        return words.isEmpty ? "not tested yet" : words.joined(separator: ", ")
    }

    public static func summary(_ records: [UDS.DTCRecord]) -> String {
        if records.isEmpty { return "none stored" }
        let faults = records.filter { isFault($0.status) }
        if faults.isEmpty {
            return "no faults (\(records.count) entries, all just 'not tested yet')"
        }
        let shown = faults.prefix(12).map { String(format: "%06X", $0.dtc) + " (\(statusText($0.status)))" }
        let more = faults.count > 12 ? " and \(faults.count - 12) more" : ""
        return "\(faults.count) fault(s): " + shown.joined(separator: "; ") + more
            + "; \(records.count - faults.count) other entries not tested yet"
    }
}
