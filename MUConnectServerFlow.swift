import Foundation

/// Local, deterministic ConnectServer negotiation for the documented
/// OpenMU Season 6 packet variant. Does not attempt authentication.
///
/// This state machine is intentionally disconnected from the live ThanhThan
/// endpoint until server version and permission are verified.
struct MUConnectServerFlow {
    enum Phase: Equatable {
        case idle
        case waitingForHello
        case waitingForServerList
        case serversAvailable([MUListedServer])
        case waitingForServerAddress(UInt16)
        case serverAddressResolved(host: String, port: UInt16)
        case protocolError
    }

    private(set) var phase: Phase = .idle

    mutating func beginSession() {
        phase = .waitingForHello
    }

    mutating func reset() {
        phase = .idle
    }

    /// Returns one outgoing unencrypted packet when a documented response
    /// advances the handshake. Caller controls whether/where to send it.
    mutating func receive(_ incoming: MUServerPacketResult) -> Data? {
        if case .malformedKnownPacket = incoming {
            phase = .protocolError
            return nil
        }

        guard case .event(let event) = incoming else { return nil }
        switch (phase, event) {
        case (.waitingForHello, .connectHello):
            phase = .waitingForServerList
            return MUConnectServerCommands.requestServerList()

        case (.waitingForServerList, .serverList(let servers)):
            phase = .serversAvailable(servers)
            return nil

        case (.waitingForServerAddress, .serverAddress(let host, let port)):
            phase = .serverAddressResolved(host: host, port: port)
            return nil

        default:
            // Reject out-of-order responses without making up server state.
            return nil
        }
    }

    /// Only valid when the server itself offered this server id.
    mutating func requestServer(_ serverID: UInt16) -> Data? {
        guard case .serversAvailable(let servers) = phase,
              servers.contains(where: { $0.id == serverID })
        else { return nil }

        phase = .waitingForServerAddress(serverID)
        return MUConnectServerCommands.requestConnectionInfo(serverID: serverID)
    }
}

enum MUConnectServerCommands {
    /// C1 F4 06 from OpenMU docs; unencrypted request for server list.
    static func requestServerList() -> Data {
        Data([0xC1, 0x04, 0xF4, 0x06])
    }

    /// C1 F4 03: variant with little-endian 16-bit server identifier.
    /// Old 0.75 clients use a different one-byte format; NOT implemented.
    static func requestConnectionInfo(serverID: UInt16) -> Data {
        Data([0xC1, 0x06, 0xF4, 0x03,
              UInt8(serverID & 0xFF), UInt8((serverID >> 8) & 0xFF)])
    }
}
