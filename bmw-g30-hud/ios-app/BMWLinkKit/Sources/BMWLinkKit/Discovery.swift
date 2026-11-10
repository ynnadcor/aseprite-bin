// SPDX-License-Identifier: MIT
// Finding the car's gateway on the ENET cable.
//
// The car gives itself a link-local (169.254.x.x) address, so the app has to
// discover it. Three ways, in order of preference:
//  1. Broadcast: one HSFZ ident (UDP 6811) + one DoIP vehicle identification
//     (UDP 13400) to the broadcast address - what every BMW tool does. On
//     iOS 14.5+ an app may only send broadcasts with Apple's multicast
//     entitlement (paid developer account + Apple approval); without it iOS
//     rejects the send, which we report clearly.
//  2. Probe one address the user typed or that worked last time (unicast; no
//     entitlement needed), with a TCP fallback in case UDP ident is ignored.
//  3. Opt-in sweep: unicast ident to each link-local address in turn, paced
//     (default 250 addresses/s, ~4 minutes worst case). Each probe costs one
//     tiny ARP request on the cable; non-matching ARP requests are ignored by
//     the car's network stack. Only the ident message - the same one BMW tools
//     broadcast - ever reaches the gateway. Stops at the first answer.
import Foundation

public struct DiscoveredGateway: Equatable, Sendable, Identifiable, Codable {
    public var id: String { host + "/" + protocolKind.rawValue }
    public let host: String
    public let protocolKind: DiagProtocol
    public let vin: String
    public let mac: String
    public let logicalAddress: UInt16

    public init(host: String, protocolKind: DiagProtocol, vin: String = "", mac: String = "",
                logicalAddress: UInt16 = 0x10) {
        self.host = host
        self.protocolKind = protocolKind
        self.vin = vin
        self.mac = mac
        self.logicalAddress = logicalAddress
    }
}

public struct DiscoveryPorts: Sendable {
    public var hsfzIdent: UInt16 = HSFZ.identPort
    public var doip: UInt16 = DoIP.port
    public var hsfzDiag: UInt16 = HSFZ.diagPort
    public var doipDiag: UInt16 = DoIP.port
    public init() {}
    public static let standard = DiscoveryPorts()
}

public enum DiscoveryError: Error, Equatable, CustomStringConvertible {
    case broadcastBlocked(String)
    case io(String)

    public var description: String {
        switch self {
        case .broadcastBlocked(let s):
            return "iOS blocked the broadcast (\(s)). Automatic search needs Apple's multicast "
                + "networking entitlement; use 'Search the cable' or enter the address instead."
        case .io(let s): return s
        }
    }
}

public final class GatewayDiscovery {
    public let ports: DiscoveryPorts
    private let log: SessionLog?

    public init(ports: DiscoveryPorts = .standard, log: SessionLog? = nil) {
        self.ports = ports
        self.log = log
    }

    static let identRequests: (hsfz: [UInt8], doip: [UInt8]) =
        (HSFZ.buildIdentRequest(), DoIP.buildVehicleIdentificationRequest(version: DoIP.bmwProtocolVersion))

    /// Classify a UDP reply by the port it came from.
    public static func parseReply(_ data: [UInt8], host: String, port: UInt16,
                                  ports: DiscoveryPorts = .standard) -> DiscoveredGateway? {
        if port == ports.hsfzIdent, let id = HSFZ.parseIdentReply(data) {
            return DiscoveredGateway(host: host, protocolKind: .hsfz, vin: id.vin, mac: id.mac,
                                     logicalAddress: UInt16(id.diagAddress))
        }
        if port == ports.doip, let (h, p) = try? DoIP.parseHeader(data),
           h.payloadType == DoIP.PayloadType.vehicleAnnouncement.rawValue,
           let ann = try? DoIP.parseVehicleAnnouncement(p) {
            return DiscoveredGateway(host: host, protocolKind: .doip, vin: ann.vin,
                                     mac: ann.eid.hexString.uppercased(), logicalAddress: ann.logicalAddress)
        }
        return nil
    }

    /// Read replies for `duration` seconds. With duration 0 it still drains
    /// everything that has already arrived (used between sweep batches).
    private func collect(_ sock: UDPSocket, for duration: TimeInterval,
                         stopAtFirst: Bool = false) -> [DiscoveredGateway] {
        var found: [DiscoveredGateway] = []
        let deadline = Date().addingTimeInterval(duration)
        while true {
            guard let pkt = try? sock.receive(timeout: max(0, deadline.timeIntervalSinceNow)) else { break }
            log?.rx("UDP reply from \(pkt.host):\(pkt.port)", pkt.bytes)
            if let gw = Self.parseReply(pkt.bytes, host: pkt.host, port: pkt.port, ports: ports),
               !found.contains(gw) {
                log?.info("Found \(gw.protocolKind.displayName) gateway at \(gw.host)")
                found.append(gw)
                if stopAtFirst { break }
            }
        }
        return found
    }

    // MARK: 1. broadcast

    public func broadcast(interface: NetInterface?, listen: TimeInterval = 2.0) throws -> [DiscoveredGateway] {
        let sock: UDPSocket
        do {
            sock = try UDPSocket(interface: interface?.name, broadcast: true)
        } catch let e as SocketError {
            throw DiscoveryError.io(e.message)
        }
        defer { sock.close() }

        var destinations = ["255.255.255.255"]
        if let b = interface?.broadcast, !destinations.contains(b) { destinations.append(b) }
        var sent = 0
        var lastError: SocketError?
        for dest in destinations {
            for (payload, port) in [(Self.identRequests.hsfz, ports.hsfzIdent), (Self.identRequests.doip, ports.doip)] {
                do {
                    try sock.send(payload, to: dest, port: port)
                    log?.tx("UDP broadcast ident → \(dest):\(port)", payload)
                    sent += 1
                } catch let e as SocketError {
                    log?.warn("broadcast to \(dest):\(port) failed: \(e.message)")
                    lastError = e
                }
            }
        }
        if sent == 0 {
            if let e = lastError, e.looksLikePermissionBlock { throw DiscoveryError.broadcastBlocked(e.message) }
            throw DiscoveryError.io(lastError?.message ?? "could not send")
        }
        return collect(sock, for: listen)
    }

    // MARK: 2. probe one address

    public func probe(host: String, interface: NetInterface?, listen: TimeInterval = 1.5,
                      tcpTimeout: TimeInterval = 2.0) throws -> [DiscoveredGateway] {
        let sock: UDPSocket
        do {
            sock = try UDPSocket(interface: interface?.name)
        } catch let e as SocketError {
            throw DiscoveryError.io(e.message)
        }
        defer { sock.close() }
        for (payload, port) in [(Self.identRequests.hsfz, ports.hsfzIdent), (Self.identRequests.doip, ports.doip)] {
            do {
                try sock.send(payload, to: host, port: port)
                log?.tx("UDP ident → \(host):\(port)", payload)
            } catch let e as SocketError {
                log?.warn("ident to \(host):\(port) failed: \(e.message)")
            }
        }
        let found = collect(sock, for: listen)
        if !found.isEmpty { return found }

        // Some gateways may ignore unicast ident; see which diagnostic port accepts TCP.
        log?.info("No UDP ident reply from \(host); trying TCP ports")
        for (kind, port) in [(DiagProtocol.hsfz, ports.hsfzDiag), (DiagProtocol.doip, ports.doipDiag)] {
            if let s = try? TCPStream.connect(host: host, port: port, interface: interface?.name,
                                              timeout: tcpTimeout) {
                s.close()
                log?.info("\(host) accepts TCP on \(port) → \(kind.displayName)")
                return [DiscoveredGateway(host: host, protocolKind: kind)]
            }
        }
        return []
    }

    // MARK: 3. opt-in sweep

    /// 169.254.1.0 ... 169.254.254.255 (RFC 3927 usable range).
    public static let linkLocalRange: ClosedRange<UInt32> = 0xA9FE_0100...0xA9FE_FEFF

    public static func ipString(_ v: UInt32) -> String {
        "\(v >> 24 & 0xFF).\(v >> 16 & 0xFF).\(v >> 8 & 0xFF).\(v & 0xFF)"
    }

    public static func ipValue(_ s: String) -> UInt32? {
        let parts = s.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 <= 255 }) else { return nil }
        return parts[0] << 24 | parts[1] << 16 | parts[2] << 8 | parts[3]
    }

    /// Unicast ident to each address in `range`, paced at `perSecond`.
    /// DoIP probes trail the HSFZ probes by ~0.5 s so an address's ARP lookup
    /// has finished before the second datagram is queued.
    public func sweep(interface: NetInterface?, range: ClosedRange<UInt32> = GatewayDiscovery.linkLocalRange,
                      perSecond: Int = 250, includeDoIP: Bool = true,
                      isCancelled: () -> Bool = { false },
                      progress: (Int, Int) -> Void = { _, _ in }) throws -> DiscoveredGateway? {
        let sock: UDPSocket
        do {
            sock = try UDPSocket(interface: interface?.name)
        } catch let e as SocketError {
            throw DiscoveryError.io(e.message)
        }
        defer { sock.close() }

        let own = interface.flatMap { Self.ipValue($0.address) }
        let total = Int(range.upperBound - range.lowerBound) + 1
        let rate = max(10, perSecond)
        let batch = max(1, rate / 20)          // one batch every 50 ms
        let lag = includeDoIP ? max(1, rate / 2) : 0
        log?.info("Sweep: \(total) addresses at \(rate)/s on \(interface?.name ?? "default route")")

        var sendErrors = 0
        var index = 0
        var last = Date()
        while index < total + lag {
            if isCancelled() { log?.info("Sweep cancelled at \(index)/\(total)"); return nil }
            let end = min(index + batch, total + lag)
            for i in index..<end {
                if i < total {
                    let a = range.lowerBound + UInt32(i)
                    if a != own {
                        do { try sock.send(Self.identRequests.hsfz, to: Self.ipString(a), port: ports.hsfzIdent) }
                        catch { sendErrors += 1 }
                    }
                }
                if includeDoIP, i >= lag, i - lag < total {
                    let a = range.lowerBound + UInt32(i - lag)
                    if a != own {
                        do { try sock.send(Self.identRequests.doip, to: Self.ipString(a), port: ports.doip) }
                        catch { sendErrors += 1 }
                    }
                }
            }
            index = end
            progress(min(index, total), total)
            if let gw = collect(sock, for: 0, stopAtFirst: true).first {
                log?.info("Sweep found the gateway after \(min(index, total)) addresses")
                return gw
            }
            if sendErrors > 1000 && sendErrors * 2 > index {
                throw DiscoveryError.io("most sends are failing (Local Network access denied?)")
            }
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < 0.05 { Thread.sleep(forTimeInterval: 0.05 - elapsed) }
            last = Date()
        }
        // Late replies.
        let gw = collect(sock, for: 2.0, stopAtFirst: true).first
        if gw == nil { log?.info("Sweep finished: no gateway answered (\(sendErrors) send errors)") }
        return gw
    }
}
