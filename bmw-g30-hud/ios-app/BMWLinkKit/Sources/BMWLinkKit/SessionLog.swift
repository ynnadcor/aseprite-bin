// SPDX-License-Identifier: MIT
// A session log of everything sent to and received from the car, so a first
// test produces something useful to send back even when it fails. Export
// redacts the VIN and the car's MAC address by default.
import Foundation

public final class SessionLog: @unchecked Sendable {
    public enum Kind: String, Sendable {
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
        case tx = "TX"
        case rx = "RX"
    }

    public struct Entry: Sendable {
        public let time: Date
        public let kind: Kind
        public let text: String
        public let bytes: [UInt8]?
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let start: Date
    private let maxEntries: Int
    /// Called (on the logging thread) after each append. UI hook.
    public var onAppend: (@Sendable (Entry) -> Void)?

    public init(start: Date = Date(), maxEntries: Int = 20_000) {
        self.start = start
        self.maxEntries = maxEntries
    }

    public func add(_ kind: Kind, _ text: String, bytes: [UInt8]? = nil) {
        let e = Entry(time: Date(), kind: kind, text: text, bytes: bytes)
        lock.lock()
        entries.append(e)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        let hook = onAppend
        lock.unlock()
        hook?(e)
    }

    public func info(_ s: String) { add(.info, s) }
    public func warn(_ s: String) { add(.warn, s) }
    public func error(_ s: String) { add(.error, s) }
    public func tx(_ label: String, _ bytes: [UInt8]) { add(.tx, label, bytes: bytes) }
    public func rx(_ label: String, _ bytes: [UInt8]) { add(.rx, label, bytes: bytes) }

    public var all: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    public func clear() {
        lock.lock(); entries.removeAll(); lock.unlock()
    }

    public func format(_ e: Entry) -> String {
        let t = String(format: "%9.3f", e.time.timeIntervalSince(start))
        var line = "\(t)s \(e.kind.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0)) \(e.text)"
        if let b = e.bytes { line += "  [\(b.count)] " + b.spacedHex }
        return line
    }

    /// Plain-text export. `secrets` are masked in both text and hex dumps.
    public func export(header: [String] = [], secrets: [LogRedactor.Secret] = []) -> String {
        let body = all.map(format).joined(separator: "\n")
        let text = (header + ["", body]).joined(separator: "\n") + "\n"
        return LogRedactor.redact(text, secrets: secrets)
    }
}

public enum LogRedactor {
    public struct Secret: Equatable, Sendable {
        public let value: String
        /// Characters left readable at the start (e.g. 3 for a VIN: the
        /// manufacturer code "WBA" says only "BMW AG").
        public let keepPrefix: Int
        public init(_ value: String, keepPrefix: Int) {
            self.value = value
            self.keepPrefix = keepPrefix
        }
    }

    public static func vin(_ v: String) -> Secret { Secret(v, keepPrefix: 3) }
    /// Keep the OUI (vendor) part of a 12-hex-digit MAC.
    public static func mac(_ m: String) -> Secret { Secret(m, keepPrefix: 6) }

    public static func redact(_ text: String, secrets: [Secret]) -> String {
        var out = text
        for s in secrets where s.value.count > s.keepPrefix && !s.value.isEmpty {
            let keep = String(s.value.prefix(s.keepPrefix))
            let maskedASCII = keep + String(repeating: "*", count: s.value.count - s.keepPrefix)
            out = out.replacingOccurrences(of: s.value, with: maskedASCII)
            // The same characters as they appear in hex dumps ("57 42 41 ...").
            let bytes = Array(s.value.utf8)
            let hex = bytes.spacedHex
            let maskedHex = (Array(bytes.prefix(s.keepPrefix)).spacedHex.split(separator: " ").map(String.init)
                + Array(repeating: "**", count: bytes.count - s.keepPrefix)).joined(separator: " ")
            out = out.replacingOccurrences(of: hex, with: maskedHex)
        }
        return out
    }

    /// For on-screen display: "WBA…1234".
    public static func shortVIN(_ vin: String) -> String {
        guard vin.count == 17 else { return vin }
        return String(vin.prefix(3)) + "…" + String(vin.suffix(4))
    }
}
