import Foundation
import Network
import os

/// One TCP connection with async send and receive. PTP/IP uses two: a command
/// channel and an event channel, both to the camera's port 15740.
final class TCPChannel: @unchecked Sendable {
    /// Largest packet accepted. Full-size ARW files are ~25 MB; this leaves room.
    static let maxPacketLength: UInt32 = 256 * 1024 * 1024

    private let connection: NWConnection
    private let queue: DispatchQueue

    init(host: String, port: UInt16, label: String) {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 5
        tcp.enableKeepalive = true
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? 15740,
            using: NWParameters(tls: nil, tcp: tcp)
        )
        queue = DispatchQueue(label: "shutterdrop.ptpip.\(label)")
    }

    func open() async throws {
        let resumed = OSAllocatedUnfairLock(initialState: false)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [connection] state in
                let result: Result<Void, Error>
                switch state {
                case .ready: result = .success(())
                // .waiting means unreachable or refused; for a camera on the LAN, treat it as failure.
                case .failed(let error), .waiting(let error): result = .failure(error)
                case .cancelled: result = .failure(PTPIPError.connectionClosed)
                default: return
                }
                let first = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(with: result) }
                if case .failure = result { connection.cancel() }
            }
            connection.start(queue: queue)
        }
    }

    func close() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    func write(_ packet: Packet) async throws {
        let data = packet.encoded()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    func readPacket() async throws -> Packet {
        let (length, type) = try Packet.header([UInt8](try await receive(exactly: Packet.headerSize)))
        guard length >= Packet.headerSize else { throw PTPIPError.malformedPacket(length: length) }
        guard length <= Self.maxPacketLength else { throw PTPIPError.packetTooLarge(length: length) }
        let bodyLength = Int(length) - Packet.headerSize
        let body = bodyLength > 0 ? try await receive(exactly: bodyLength) : Data()
        return try Packet.decode(type: type, payload: [UInt8](body))
    }

    private func receive(exactly count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, data.count == count {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: PTPIPError.connectionClosed)
                }
            }
        }
    }
}
