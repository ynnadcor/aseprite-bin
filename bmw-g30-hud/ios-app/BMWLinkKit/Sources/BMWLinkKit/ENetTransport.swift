// SPDX-License-Identifier: MIT
// Real DoIP-over-TCP transport using Network.framework. Compiled only where
// Network is available (iOS/macOS). This is the piece that must be validated on
// the real car; it is written against the documented DoIP TCP behavior but is
// NOT yet verified against a vehicle (see docs/compatibility-assessment.md 4).
import Foundation

#if canImport(Network)
import Network

/// Thread-safe holder so Network's @Sendable callbacks never mutate captured vars.
private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// Blocking request/response DoIP client over TCP (default port 13400).
/// Reads one full DoIP message by first reading the 8-byte header, then the
/// declared payload length. The synchronous API keeps the read-only flow in
/// `ReadOnlyDiagClient` simple; call it off the main thread.
public final class ENetTransport: Transport {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "bmwlink.enet")
    private let timeout: TimeInterval
    private var started = false

    /// Upper bound on a single DoIP payload we are willing to buffer. Read-only
    /// identification/DTC/RDBI replies are small; this guards against a corrupt
    /// length field making us allocate or wait forever.
    public static let maxPayloadBytes = 64 * 1024

    public init(host: String, port: UInt16 = 13400, timeout: TimeInterval = 5.0) {
        // DoIP uses plain TCP; link-local 169.254.x.x requires the interface to
        // be present (USB-C Ethernet adapter). No TLS.
        self.connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? 13400,
            using: .tcp
        )
        self.timeout = timeout
    }

    private func startIfNeeded() throws {
        guard !started else { return }
        let sem = DispatchSemaphore(value: 0)
        let failure = LockedBox<Error?>(nil)
        let signalled = LockedBox(false)
        connection.stateUpdateHandler = { state in
            var shouldSignal = false
            switch state {
            case .ready:
                shouldSignal = true
            case .failed(let e), .waiting(let e):
                failure.value = e
                shouldSignal = true
            default:
                break
            }
            // Only wake the waiter once; later state changes are ignored here.
            if shouldSignal && !signalled.value {
                signalled.value = true
                sem.signal()
            }
        }
        connection.start(queue: queue)
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            connection.cancel()
            throw TransportError.timeout
        }
        if let f = failure.value {
            connection.cancel()
            throw TransportError.io("\(f)")
        }
        started = true
    }

    public func request(_ frame: [UInt8]) throws -> [UInt8] {
        try startIfNeeded()
        try send(Data(frame))
        let header = try receiveExactly(8)
        let plen = Int(header[4]) << 24 | Int(header[5]) << 16
                 | Int(header[6]) << 8 | Int(header[7])
        guard plen <= ENetTransport.maxPayloadBytes else {
            throw TransportError.io("DoIP payload length \(plen) exceeds limit")
        }
        let payload = try plen > 0 ? receiveExactly(plen) : Data()
        return [UInt8](header) + [UInt8](payload)
    }

    public func close() { connection.cancel() }

    // MARK: low-level

    private func send(_ data: Data) throws {
        let sem = DispatchSemaphore(value: 0)
        let failure = LockedBox<Error?>(nil)
        connection.send(content: data, completion: .contentProcessed { e in
            failure.value = e
            sem.signal()
        })
        if sem.wait(timeout: .now() + timeout) == .timedOut { throw TransportError.timeout }
        if let f = failure.value { throw TransportError.io("send: \(f)") }
    }

    private func receiveExactly(_ n: Int) throws -> Data {
        var acc = Data()
        while acc.count < n {
            let need = n - acc.count
            let sem = DispatchSemaphore(value: 0)
            let chunk = LockedBox<Data?>(nil)
            let failure = LockedBox<Error?>(nil)
            connection.receive(minimumIncompleteLength: 1, maximumLength: need) { data, _, _, e in
                chunk.value = data
                failure.value = e
                sem.signal()
            }
            if sem.wait(timeout: .now() + timeout) == .timedOut { throw TransportError.timeout }
            if let f = failure.value { throw TransportError.io("recv: \(f)") }
            guard let c = chunk.value, !c.isEmpty else { throw TransportError.io("connection closed") }
            acc.append(c)
        }
        // Normalize indices to start at 0 for callers that subscript by offset.
        return Data(acc)
    }
}
#endif
