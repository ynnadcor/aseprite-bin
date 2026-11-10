// SPDX-License-Identifier: MIT
// End-to-end over REAL sockets: a simulated gateway listens on 127.0.0.1 (TCP
// for diagnostics, UDP for discovery) and the production code paths -
// GatewayDiscovery.probe/sweep, DiagConnector.connect (TCPStream), the
// HSFZ/DoIP links and the identify sweep - talk to it. This is the same code
// that runs on the iPhone; only the gateway is simulated.
import XCTest
@testable import BMWLinkKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private let syntheticVIN = "WBAJE7C50JWA00000"   // test data, not a real vehicle

/// A MockGateway served over TCP + UDP on 127.0.0.1 (ephemeral ports).
final class LoopbackGateway {
    let gateway: MockGateway
    let udp: UDPSocket
    let tcpPort: UInt16
    var udpPort: UInt16 { udp.localPort }
    private let listenFD: Int32
    private let lock = NSLock()
    private var stopped = false
    private let group = DispatchGroup()

    init(kind: DiagProtocol, vin: String = syntheticVIN) throws {
        gateway = MockGateway(kind: kind, vin: vin)
        udp = try UDPSocket(bindHost: "127.0.0.1", bindPort: 0)

        let fd = socket(AF_INET, POSIX.sockStream, 0)
        guard fd >= 0 else { throw TransportError.io("socket") }
        POSIX.setOption(fd, SOL_SOCKET, SO_REUSEADDR, 1)
        var addr = try POSIX.makeAddr("127.0.0.1", 0)
        guard POSIX.withSockAddr(&addr, { POSIX.sysBind(fd, $0, $1) }) == 0, listen(fd, 4) == 0 else {
            POSIX.closeFD(fd)
            throw TransportError.io(POSIX.errText("bind/listen"))
        }
        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        tcpPort = UInt16(bigEndian: bound.sin_port)
        listenFD = fd
        start()
    }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    private func start() {
        group.enter()
        Thread {
            defer { self.group.leave() }
            while !self.isStopped {
                guard let pkt = try? self.udp.receive(timeout: 0.05) else { continue }
                if let reply = self.gateway.identReply(to: pkt.bytes) {
                    try? self.udp.send(reply, to: pkt.host, port: pkt.port)
                }
            }
        }.start()

        group.enter()
        Thread {
            defer { self.group.leave() }
            while !self.isStopped {
                guard let ev = try? POSIX.waitFD(self.listenFD, events: Int16(POLLIN), timeout: 0.05),
                      ev != 0 else { continue }
                let client = accept(self.listenFD, nil, nil)
                if client >= 0 { self.serve(TCPStream(fd: client, remote: "tester")) }
            }
        }.start()
    }

    private func serve(_ s: TCPStream) {
        var reader = FrameReader(format: gateway.kind == .hsfz ? .hsfz : .doip)
        while !isStopped {
            do {
                reader.append(try s.read(timeout: 0.05))
                while let f = try reader.nextFrame() {
                    for out in gateway.handle(f) { try s.write(out) }
                }
            } catch TransportError.timeout {
                continue
            } catch {
                break
            }
        }
        s.close()
    }

    func stop() {
        lock.lock(); stopped = true; lock.unlock()
        _ = group.wait(timeout: .now() + 3)
        udp.close()
        POSIX.closeFD(listenFD)
    }
}

final class LoopbackIntegrationTests: XCTestCase {
    /// Point discovery at the loopback gateway; the other protocol's ports go
    /// to the discard port so they never answer.
    func ports(_ server: LoopbackGateway) -> DiscoveryPorts {
        var p = DiscoveryPorts()
        p.hsfzIdent = 9; p.hsfzDiag = 9; p.doip = 9; p.doipDiag = 9
        if server.gateway.kind == .hsfz {
            p.hsfzIdent = server.udpPort; p.hsfzDiag = server.tcpPort
        } else {
            p.doip = server.udpPort; p.doipDiag = server.tcpPort
        }
        return p
    }

    func roundTrip(_ kind: DiagProtocol) throws {
        let server = try LoopbackGateway(kind: kind)
        defer { server.stop() }
        let log = SessionLog()

        // 1. discovery by unicast probe (what the app does with a typed/remembered IP)
        let found = try GatewayDiscovery(ports: ports(server), log: log)
            .probe(host: "127.0.0.1", interface: nil, listen: 1.0)
        XCTAssertEqual(found.count, 1, "\(kind)")
        XCTAssertEqual(found.first?.protocolKind, kind)
        XCTAssertEqual(found.first?.vin, syntheticVIN)

        // 2. TCP connect + link open (+ DoIP routing activation)
        let link = try DiagConnector.connect(host: "127.0.0.1", protocolKind: kind, port: server.tcpPort,
                                             log: log, timeouts: .uniform(1.0))
        defer { link.close() }

        // 3. the read-only identify sweep
        let report = ReadOnlyDiagClient(link: link, log: log).runIdentify(plan: .g30, host: "127.0.0.1")
        XCTAssertEqual(report.vin, syntheticVIN, "\(kind)")
        XCTAssertGreaterThan(report.answeredCount, 6, "\(kind): \(report.summary)")
        // Everything the gateway received was a read-only request.
        XCTAssertFalse(server.gateway.udsRequestsSeen.isEmpty)
        for req in server.gateway.udsRequestsSeen {
            XCTAssertTrue(UDS.allowedServices.contains(req[0]), "non-read service sent: \(req.spacedHex)")
        }
        // The exported log is redacted.
        let text = log.export(secrets: [LogRedactor.vin(syntheticVIN)])
        XCTAssertFalse(text.contains(syntheticVIN))
        XCTAssertTrue(text.contains("TX"))
        XCTAssertTrue(text.contains("RX"))
    }

    func testHSFZEndToEndOverRealSockets() throws { try roundTrip(.hsfz) }
    func testDoIPEndToEndOverRealSockets() throws { try roundTrip(.doip) }

    func testProbeFallsBackToTCPWhenIdentIsIgnored() throws {
        let server = try LoopbackGateway(kind: .hsfz)
        defer { server.stop() }
        var p = ports(server)
        p.hsfzIdent = 9   // ident goes nowhere; only the TCP port is right
        let found = try GatewayDiscovery(ports: p).probe(host: "127.0.0.1", interface: nil, listen: 0.3)
        XCTAssertEqual(found, [DiscoveredGateway(host: "127.0.0.1", protocolKind: .hsfz)])
    }

    func testProbeOfEmptyAddressFindsNothing() throws {
        var p = DiscoveryPorts()
        p.hsfzIdent = 9; p.doip = 9; p.hsfzDiag = 9; p.doipDiag = 9
        let found = try GatewayDiscovery(ports: p).probe(host: "127.0.0.1", interface: nil,
                                                          listen: 0.2, tcpTimeout: 0.3)
        XCTAssertTrue(found.isEmpty)
    }

    func testSweepFindsGatewayForBothProtocols() throws {
        for kind in DiagProtocol.allCases {
            let server = try LoopbackGateway(kind: kind)
            defer { server.stop() }
            let one = GatewayDiscovery.ipValue("127.0.0.1")!
            var progressCalls = 0
            let gw = try GatewayDiscovery(ports: ports(server)).sweep(
                interface: nil, range: one...one, perSecond: 100, includeDoIP: true,
                progress: { _, _ in progressCalls += 1 })
            XCTAssertEqual(gw?.protocolKind, kind)
            XCTAssertEqual(gw?.host, "127.0.0.1")
            XCTAssertGreaterThan(progressCalls, 0)
        }
    }

    func testSweepCanBeCancelled() throws {
        let gw = try GatewayDiscovery().sweep(interface: nil, range: 0x7F00_0001...0x7F00_0001,
                                              perSecond: 100, isCancelled: { true })
        XCTAssertNil(gw)
    }

    func testConnectToClosedPortFailsCleanly() {
        XCTAssertThrowsError(try DiagConnector.connect(host: "127.0.0.1", protocolKind: .hsfz, port: 9,
                                                       timeouts: .uniform(0.5)))
    }
}
