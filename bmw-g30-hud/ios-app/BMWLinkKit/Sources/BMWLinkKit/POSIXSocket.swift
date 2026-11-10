// SPDX-License-Identifier: MIT
// Minimal BSD-socket TCP/UDP and interface listing, shared by iOS and Linux.
//
// Why BSD sockets instead of Network.framework: the exact same code runs on
// the iPhone and in the Linux test environment, so the transport that talks
// to the car is the transport the integration tests exercise. On Apple
// platforms each socket is pinned to the USB Ethernet interface (IP_BOUND_IF)
// so iOS never routes car traffic over Wi-Fi.
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// errno-carrying socket error (lets discovery recognise "broadcast blocked").
public struct SocketError: Error, Equatable, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { message }

    /// Errors iOS returns when an app may not send broadcast/multicast
    /// (no multicast entitlement) or Local Network access was denied.
    public var looksLikePermissionBlock: Bool {
        code == EHOSTUNREACH || code == EACCES || code == EPERM || code == ENETUNREACH
    }
}

enum POSIX {
    static var sockStream: Int32 {
        #if canImport(Darwin)
        return SOCK_STREAM
        #else
        return Int32(SOCK_STREAM.rawValue)
        #endif
    }

    static var sockDgram: Int32 {
        #if canImport(Darwin)
        return SOCK_DGRAM
        #else
        return Int32(SOCK_DGRAM.rawValue)
        #endif
    }

    static var sendFlags: Int32 {
        #if canImport(Darwin)
        return 0
        #else
        return Int32(MSG_NOSIGNAL)
        #endif
    }

    static func errText(_ what: String, _ code: Int32 = errno) -> String {
        "\(what): \(String(cString: strerror(code))) (errno \(code))"
    }

    static func closeFD(_ fd: Int32) {
        #if canImport(Darwin)
        _ = Darwin.close(fd)
        #else
        _ = Glibc.close(fd)
        #endif
    }

    static func sysConnect(_ fd: Int32, _ a: UnsafePointer<sockaddr>, _ l: socklen_t) -> Int32 {
        #if canImport(Darwin)
        return Darwin.connect(fd, a, l)
        #else
        return Glibc.connect(fd, a, l)
        #endif
    }

    static func sysBind(_ fd: Int32, _ a: UnsafePointer<sockaddr>, _ l: socklen_t) -> Int32 {
        #if canImport(Darwin)
        return Darwin.bind(fd, a, l)
        #else
        return Glibc.bind(fd, a, l)
        #endif
    }

    static func makeAddr(_ host: String, _ port: UInt16) throws -> sockaddr_in {
        var addr = sockaddr_in()
        #if canImport(Darwin)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        let ok = host.withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }
        guard ok == 1 else { throw TransportError.io("not an IPv4 address: \(host)") }
        return addr
    }

    static func ipString(_ a: in_addr) -> String {
        var addr = a
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        _ = inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buf)
    }

    static func ipString(_ sa: UnsafeMutablePointer<sockaddr>?) -> String? {
        guard let sa = sa, sa.pointee.sa_family == sa_family_t(AF_INET) else { return nil }
        return sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { ipString($0.pointee.sin_addr) }
    }

    static func withSockAddr<T>(_ addr: inout sockaddr_in,
                                _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    static func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    static func setOption(_ fd: Int32, _ level: Int32, _ name: Int32, _ value: Int32) {
        var v = value
        _ = setsockopt(fd, level, name, &v, socklen_t(MemoryLayout<Int32>.size))
    }

    static func noSigPipe(_ fd: Int32) {
        #if canImport(Darwin)
        setOption(fd, SOL_SOCKET, SO_NOSIGPIPE, 1)
        #endif
    }

    /// Pin a socket to one interface (Apple platforms). No-op elsewhere.
    static func bindToInterface(_ fd: Int32, _ name: String?) {
        #if canImport(Darwin)
        guard let name = name else { return }
        var index = if_nametoindex(name)
        guard index != 0 else { return }
        _ = setsockopt(fd, Int32(IPPROTO_IP), IP_BOUND_IF, &index,
                       socklen_t(MemoryLayout<UInt32>.size))
        #endif
    }

    /// Wait for poll events. Returns revents, or nil on timeout.
    static func waitFD(_ fd: Int32, events: Int16, timeout: TimeInterval) throws -> Int16? {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while true {
            let remaining = deadline.timeIntervalSinceNow
            var p = pollfd(fd: fd, events: events, revents: 0)
            let ms = remaining <= 0 ? Int32(0) : Int32(min(remaining * 1000, 60_000).rounded(.up))
            let r = poll(&p, 1, ms)
            if r > 0 { return p.revents }
            if r == 0 {
                if deadline.timeIntervalSinceNow <= 0 { return nil }
                continue
            }
            if errno == EINTR { continue }
            throw TransportError.io(errText("poll"))
        }
    }
}

// MARK: - TCP

/// A connected TCP stream (to the car's gateway).
public final class TCPStream: ByteStream {
    private var fd: Int32
    private let lock = NSLock()
    public let remote: String

    init(fd: Int32, remote: String) {
        self.fd = fd
        self.remote = remote
    }

    deinit { close() }

    public static func connect(host: String, port: UInt16, interface: String? = nil,
                               timeout: TimeInterval = 5) throws -> TCPStream {
        var addr = try POSIX.makeAddr(host, port)
        let fd = socket(AF_INET, POSIX.sockStream, 0)
        guard fd >= 0 else { throw TransportError.io(POSIX.errText("socket")) }
        var ok = false
        defer { if !ok { POSIX.closeFD(fd) } }

        POSIX.noSigPipe(fd)
        POSIX.bindToInterface(fd, interface)
        POSIX.setOption(fd, Int32(IPPROTO_TCP), TCP_NODELAY, 1)
        POSIX.setNonBlocking(fd)

        let r = POSIX.withSockAddr(&addr) { POSIX.sysConnect(fd, $0, $1) }
        if r != 0 {
            let e = errno
            guard e == EINPROGRESS || e == EINTR else {
                throw TransportError.io(POSIX.errText("connect to \(host):\(port)", e))
            }
            guard try POSIX.waitFD(fd, events: Int16(POLLOUT), timeout: timeout) != nil else {
                throw TransportError.timeout("connecting to \(host):\(port)")
            }
            var soErr: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            _ = getsockopt(fd, SOL_SOCKET, SO_ERROR, &soErr, &len)
            if soErr != 0 {
                throw TransportError.io(POSIX.errText("connect to \(host):\(port)", soErr))
            }
        }
        ok = true
        return TCPStream(fd: fd, remote: "\(host):\(port)")
    }

    private func currentFD() throws -> Int32 {
        lock.lock(); defer { lock.unlock() }
        guard fd >= 0 else { throw TransportError.closed }
        return fd
    }

    public func write(_ bytes: [UInt8]) throws {
        let fd = try currentFD()
        var offset = 0
        while offset < bytes.count {
            let n = bytes[offset...].withUnsafeBytes { raw -> Int in
                send(fd, raw.baseAddress!, raw.count, POSIX.sendFlags)
            }
            if n > 0 { offset += n; continue }
            let e = errno
            if n < 0 && (e == EAGAIN || e == EWOULDBLOCK || e == EINTR) {
                guard try POSIX.waitFD(fd, events: Int16(POLLOUT), timeout: 5) != nil else {
                    throw TransportError.timeout("sending to \(remote)")
                }
                continue
            }
            if e == EPIPE || e == ECONNRESET { throw TransportError.closed }
            throw TransportError.io(POSIX.errText("send", e))
        }
    }

    public func read(timeout: TimeInterval) throws -> [UInt8] {
        let fd = try currentFD()
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            guard try POSIX.waitFD(fd, events: Int16(POLLIN),
                                   timeout: deadline.timeIntervalSinceNow) != nil else {
                throw TransportError.timeout("waiting for data from \(remote)")
            }
            var buf = [UInt8](repeating: 0, count: 65_536)
            let n = buf.withUnsafeMutableBytes { raw -> Int in
                recv(fd, raw.baseAddress!, raw.count, 0)
            }
            if n > 0 { return Array(buf[0..<n]) }
            if n == 0 { throw TransportError.closed }
            let e = errno
            if e == EAGAIN || e == EWOULDBLOCK || e == EINTR { continue }
            if e == ECONNRESET { throw TransportError.closed }
            throw TransportError.io(POSIX.errText("recv", e))
        }
    }

    public func close() {
        lock.lock()
        let old = fd
        fd = -1
        lock.unlock()
        if old >= 0 {
            _ = shutdown(old, Int32(SHUT_RDWR))
            POSIX.closeFD(old)
        }
    }
}

// MARK: - UDP

/// A UDP socket for gateway discovery.
public final class UDPSocket {
    private var fd: Int32

    public init(interface: String? = nil, broadcast: Bool = false,
                bindHost: String = "0.0.0.0", bindPort: UInt16 = 0) throws {
        fd = socket(AF_INET, POSIX.sockDgram, 0)
        guard fd >= 0 else { throw SocketError(code: errno, message: POSIX.errText("socket")) }
        POSIX.noSigPipe(fd)
        POSIX.setOption(fd, SOL_SOCKET, SO_REUSEADDR, 1)
        if broadcast { POSIX.setOption(fd, SOL_SOCKET, SO_BROADCAST, 1) }
        POSIX.bindToInterface(fd, interface)
        POSIX.setNonBlocking(fd)
        var addr = try POSIX.makeAddr(bindHost, bindPort)
        let r = POSIX.withSockAddr(&addr) { POSIX.sysBind(fd, $0, $1) }
        if r != 0 {
            let e = errno
            POSIX.closeFD(fd)
            fd = -1
            throw SocketError(code: e, message: POSIX.errText("bind", e))
        }
    }

    deinit { close() }

    public var localPort: UInt16 {
        var addr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let r = withUnsafeMutablePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        return r == 0 ? UInt16(bigEndian: addr.sin_port) : 0
    }

    public func send(_ bytes: [UInt8], to host: String, port: UInt16) throws {
        var addr = try POSIX.makeAddr(host, port)
        let n = bytes.withUnsafeBytes { raw -> Int in
            POSIX.withSockAddr(&addr) { sa, len in
                sendto(fd, raw.baseAddress, raw.count, POSIX.sendFlags, sa, len)
            }
        }
        if n < 0 {
            let e = errno
            throw SocketError(code: e, message: POSIX.errText("sendto \(host):\(port)", e))
        }
    }

    /// Next datagram, or nil when `timeout` passes without one.
    public func receive(timeout: TimeInterval) throws -> (bytes: [UInt8], host: String, port: UInt16)? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            guard try POSIX.waitFD(fd, events: Int16(POLLIN),
                                   timeout: deadline.timeIntervalSinceNow) != nil else { return nil }
            var buf = [UInt8](repeating: 0, count: 2048)
            var from = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = buf.withUnsafeMutableBytes { raw -> Int in
                withUnsafeMutablePointer(to: &from) { p in
                    p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(fd, raw.baseAddress, raw.count, 0, $0, &len)
                    }
                }
            }
            if n >= 0 {
                return (Array(buf[0..<n]), POSIX.ipString(from.sin_addr), UInt16(bigEndian: from.sin_port))
            }
            let e = errno
            if e == EAGAIN || e == EWOULDBLOCK || e == EINTR {
                if deadline.timeIntervalSinceNow <= 0 { return nil }
                continue
            }
            throw SocketError(code: e, message: POSIX.errText("recvfrom", e))
        }
    }

    public func close() {
        if fd >= 0 {
            POSIX.closeFD(fd)
            fd = -1
        }
    }
}

// MARK: - Interfaces

public struct NetInterface: Equatable, Sendable, Identifiable {
    public var id: String { name + "/" + address }
    public let name: String
    public let address: String
    public let netmask: String
    public let broadcast: String?
    public let isUp: Bool
    public let isLoopback: Bool
    public var isLinkLocal: Bool { address.hasPrefix("169.254.") }

    public init(name: String, address: String, netmask: String, broadcast: String?,
                isUp: Bool, isLoopback: Bool) {
        self.name = name
        self.address = address
        self.netmask = netmask
        self.broadcast = broadcast
        self.isUp = isUp
        self.isLoopback = isLoopback
    }
}

public enum NetInterfaces {
    /// All IPv4 interfaces (via getifaddrs - no permission needed).
    public static func list() -> [NetInterface] {
        var result: [NetInterface] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var cur = head
        while let p = cur {
            let ifa = p.pointee
            if let address = POSIX.ipString(ifa.ifa_addr) {
                let flags = Int(ifa.ifa_flags)
                var bcast: String?
                if flags & Int(IFF_BROADCAST) != 0 {
                    #if canImport(Darwin)
                    bcast = POSIX.ipString(ifa.ifa_dstaddr)
                    #else
                    bcast = POSIX.ipString(ifa.ifa_ifu.ifu_broadaddr)
                    #endif
                }
                result.append(NetInterface(
                    name: String(cString: ifa.ifa_name),
                    address: address,
                    netmask: POSIX.ipString(ifa.ifa_netmask) ?? "",
                    broadcast: bcast,
                    isUp: flags & Int(IFF_UP) != 0,
                    isLoopback: flags & Int(IFF_LOOPBACK) != 0))
            }
            cur = ifa.ifa_next
        }
        return result
    }

    /// The interface most likely to be the USB-C Ethernet adapter + ENET cable.
    /// iPhone Wi-Fi is en0 and cellular is pdp_ip*; USB Ethernet adapters show
    /// up as another enN. With no DHCP server on the cable, iOS gives that
    /// adapter a self-assigned 169.254.x.x address, which is what we look for.
    public static func wiredCandidate(_ list: [NetInterface]) -> NetInterface? {
        let usable = list.filter { $0.isUp && !$0.isLoopback }
        if let i = usable.first(where: { $0.isLinkLocal && $0.name.hasPrefix("en") && $0.name != "en0" }) {
            return i
        }
        if let i = usable.first(where: { $0.isLinkLocal }) { return i }
        return usable.first(where: { $0.name.hasPrefix("en") && $0.name != "en0" })
    }
}
