// SPDX-License-Identifier: MIT
// A byte stream (TCP or an in-memory mock) and a frame reader that turns it
// into whole HSFZ/DoIP frames, coping with partial and merged reads.
import Foundation

public enum TransportError: Error, Equatable, CustomStringConvertible {
    case closed
    case timeout(String)
    case io(String)
    case protocolError(String)

    public var description: String {
        switch self {
        case .closed: return "connection closed by the car"
        case .timeout(let s): return "timed out: \(s)"
        case .io(let s): return "network error: \(s)"
        case .protocolError(let s): return "protocol error: \(s)"
        }
    }
}

/// Blocking, timeout-based byte I/O. Implementations: `TCPStream` (real
/// socket) and `MockGatewayStream` (in-memory simulated car).
public protocol ByteStream: AnyObject {
    func write(_ bytes: [UInt8]) throws
    /// Returns at least one byte, or throws `.timeout` / `.closed`.
    func read(timeout: TimeInterval) throws -> [UInt8]
    func close()
}

public enum FrameFormat: String, Sendable {
    case hsfz
    case doip
}

/// Accumulates bytes and yields complete frames.
public struct FrameReader {
    public let format: FrameFormat
    public let maxFrameBytes: Int
    private(set) var buffer: [UInt8] = []

    public init(format: FrameFormat, maxFrameBytes: Int = 1 << 20) {
        self.format = format
        self.maxFrameBytes = maxFrameBytes
    }

    public mutating func append(_ bytes: [UInt8]) {
        buffer += bytes
    }

    /// The next complete frame, or nil if more bytes are needed.
    public mutating func nextFrame() throws -> [UInt8]? {
        let total: Int?
        switch format {
        case .hsfz:
            total = HSFZ.frameLength(header: buffer)
        case .doip:
            if buffer.count >= 2 && (buffer[0] ^ buffer[1]) != 0xFF {
                throw TransportError.protocolError("DoIP header version check failed")
            }
            total = DoIP.frameLength(header: buffer)
        }
        guard let t = total else { return nil }
        guard t <= maxFrameBytes else {
            throw TransportError.protocolError("frame of \(t) bytes exceeds limit")
        }
        guard buffer.count >= t else { return nil }
        let frame = Array(buffer[0..<t])
        buffer.removeFirst(t)
        return frame
    }
}
