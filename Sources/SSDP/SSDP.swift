import Darwin
import Foundation

/// One SSDP message seen on the network: a reply to our search, or a NOTIFY or
/// M-SEARCH multicast by another device.
public struct SSDPMessage: Sendable, Equatable {
    public enum Kind: Sendable { case response, notify, search, other }

    public var kind: Kind
    public var sender: String
    public var startLine: String
    /// Header names are uppercased.
    public var headers: [String: String]

    public var location: String? { headers["LOCATION"] }

    /// Heuristic for a camera: an ILCE model name, Sony's imaging-device server
    /// string, or the MTP "null service" used by Send to Computer.
    public var looksLikeSonyCamera: Bool {
        ["ilce", "imagingdevice", "mtpnullservice"].contains { searchableText.contains($0) }
    }

    /// Any Sony device, cameras or not (Bravia TVs also answer SSDP).
    public var mentionsSony: Bool { searchableText.contains("sony") }

    private var searchableText: String {
        ([startLine] + headers.values).joined(separator: " ").lowercased()
    }

    public static func parse(_ text: String, sender: String) -> SSDPMessage? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let startLine = lines.first?.trimmingCharacters(in: .whitespaces), !startLine.isEmpty else { return nil }
        let kind: Kind =
            if startLine.hasPrefix("HTTP/") { .response }
            else if startLine.hasPrefix("NOTIFY") { .notify }
            else if startLine.hasPrefix("M-SEARCH") { .search }
            else { .other }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        return SSDPMessage(kind: kind, sender: sender, startLine: startLine, headers: headers)
    }
}

public enum SSDPError: Error, CustomStringConvertible {
    case socket(String, Int32)

    public var description: String {
        switch self {
        case let .socket(call, code): "\(call) failed: \(String(cString: strerror(code)))"
        }
    }
}

public enum SSDP {
    public static let multicastGroup = "239.255.255.250"
    public static let port: UInt16 = 1900

    /// Sends M-SEARCH a few times and reports every SSDP message received for
    /// `seconds`, or until `onMessage` returns true. Also listens on port 1900
    /// for NOTIFY/M-SEARCH from other devices when that port can be shared.
    /// Returns whether it could.
    @discardableResult
    public static func discover(
        seconds: Double,
        searchTarget: String = "ssdp:all",
        onMessage: @escaping @Sendable (SSDPMessage) -> Bool
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result {
                    try run(seconds: seconds, searchTarget: searchTarget, onMessage: onMessage)
                })
            }
        }
    }

    private static func run(seconds: Double, searchTarget: String, onMessage: (SSDPMessage) -> Bool) throws -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw SSDPError.socket("socket", errno) }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))

        let listening = bindSocket(fd, port: port)
        if listening {
            var membership = ip_mreq(imr_multiaddr: in_addr(s_addr: inet_addr(multicastGroup)), imr_interface: in_addr(s_addr: 0))
            if setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership, socklen_t(MemoryLayout<ip_mreq>.size)) != 0 {
                throw SSDPError.socket("IP_ADD_MEMBERSHIP", errno)
            }
        } else if !bindSocket(fd, port: 0) {
            throw SSDPError.socket("bind", errno)
        }

        var ttl: UInt8 = 2
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        // Don't receive our own M-SEARCH back.
        var loop: UInt8 = 0
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, socklen_t(MemoryLayout<UInt8>.size))
        var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let search = Array("""
            M-SEARCH * HTTP/1.1\r
            HOST: \(multicastGroup):\(port)\r
            MAN: "ssdp:discover"\r
            MX: 2\r
            ST: \(searchTarget)\r
            \r

            """.utf8)

        let start = Date()
        var searchesSent = 0
        var buffer = [UInt8](repeating: 0, count: 8192)
        while Date().timeIntervalSince(start) < seconds {
            // Repeat the search at 0 s, 1 s and 2 s; UDP multicast is lossy.
            if searchesSent < 3, Date().timeIntervalSince(start) >= Double(searchesSent) {
                try send(search, from: fd)
                searchesSent += 1
            }

            var from = sockaddr_in()
            var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buffer, buffer.count, 0, $0, &fromLength)
                }
            }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { continue }
                throw SSDPError.socket("recvfrom", errno)
            }
            let sender = String(cString: inet_ntoa(from.sin_addr))
            if let message = SSDPMessage.parse(String(decoding: buffer[0..<count], as: UTF8.self), sender: sender),
               onMessage(message) {
                break
            }
        }
        return listening
    }

    private static func bindSocket(_ fd: Int32, port: UInt16) -> Bool {
        var address = socketAddress(ip: 0, port: port)
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        } == 0
    }

    private static func send(_ bytes: [UInt8], from fd: Int32) throws {
        var destination = socketAddress(ip: inet_addr(multicastGroup), port: port)
        let sent = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if sent < 0 { throw SSDPError.socket("sendto", errno) }
    }

    /// `ip` is already in network byte order (as `inet_addr` returns it).
    private static func socketAddress(ip: in_addr_t, port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: ip)
        return address
    }
}
