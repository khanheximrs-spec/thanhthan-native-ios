import Foundation

/// Read-only decoders for a documented subset of OpenMU Season 6 server packets.
///
/// IMPORTANT: ThanhThan's custom server compatibility has NOT been established.
/// This code never sends requests or accepts credentials. Encrypted packets are
/// intentionally opaque until the correct negotiated cipher is known.
/// Packet layouts: https://github.com/MUnique/OpenMU/tree/master/docs/Packets
struct MUListedServer: Equatable {
    let id: UInt16
    let loadPercent: UInt8
    /// The fourth entry byte is kept opaque: variants give it different meanings.
    let optionByte: UInt8
}

enum MUServerEvent: Equatable {
    case connectHello
    case serverList([MUListedServer])
    case serverAddress(host: String, port: UInt16)
    case gameServerEntered(success: Bool, playerID: UInt16, version: Data)
    case loginResponse(code: UInt8)
}

enum MUServerPacketResult: Equatable {
    case event(MUServerEvent)
    case encryptedPayload
    case notRecognized
    case malformedKnownPacket
}

/// Interprets complete MU envelopes, without decrypting or modifying them.
/// A known packet with an invalid layout is rejected, not partially decoded.
enum MUServerPacketDecoder {
    static func decode(_ packet: MUWirePacket) -> MUServerPacketResult {
        guard !packet.type.hasSimpleModulusEncryption else { return .encryptedPayload }
        let bytes = [UInt8](packet.data)
        let start = packet.type.headerLength
        guard bytes.count >= start + 1 else { return .malformedKnownPacket }

        switch (packet.type, bytes[start]) {
        case (.c1, 0x00):
            guard bytes.count >= start + 2, bytes[start + 1] == 0x01 else {
                return .notRecognized
            }
            return bytes.count == 4 ? .event(.connectHello) : .malformedKnownPacket

        case (.c2, 0xF4):
            guard bytes.count >= start + 2, bytes[start + 1] == 0x06 else {
                return .notRecognized
            }
            guard bytes.count >= 7 else { return .malformedKnownPacket }
            let count = (Int(bytes[5]) << 8) | Int(bytes[6])
            guard count <= 1024, bytes.count == 7 + count * 4 else {
                return .malformedKnownPacket
            }
            var servers: [MUListedServer] = []
            servers.reserveCapacity(count)
            for i in 0..<count {
                let p = 7 + i * 4
                let id = UInt16(bytes[p]) | (UInt16(bytes[p + 1]) << 8)
                servers.append(MUListedServer(
                    id: id,
                    loadPercent: bytes[p + 2],
                    optionByte: bytes[p + 3]
                ))
            }
            return .event(.serverList(servers))

        case (.c1, 0xF4):
            guard bytes.count >= start + 2, bytes[start + 1] == 0x03 else {
                return .notRecognized
            }
            guard bytes.count == 22 else { return .malformedKnownPacket }
            let hostField = Array(bytes[4..<20])
            let hostBytes = Array(hostField.prefix(while: { $0 != 0 }))
            guard !hostBytes.isEmpty,
                  hostBytes.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) ||
                      (97...122).contains($0) || $0 == 45 || $0 == 46 }),
                  hostField.dropFirst(hostBytes.count).allSatisfy({ $0 == 0 }),
                  let host = String(bytes: hostBytes, encoding: .ascii)
            else { return .malformedKnownPacket }
            let port = UInt16(bytes[20]) | (UInt16(bytes[21]) << 8)
            guard port != 0 else { return .malformedKnownPacket }
            return .event(.serverAddress(host: host, port: port))

        case (.c1, 0xF1):
            guard bytes.count >= start + 2 else { return .malformedKnownPacket }
            switch bytes[start + 1] {
            case 0x00:
                guard bytes.count == 12 else { return .malformedKnownPacket }
                let id = (UInt16(bytes[5]) << 8) | UInt16(bytes[6])
                return .event(.gameServerEntered(
                    success: bytes[4] == 1,
                    playerID: id,
                    version: Data(bytes[7..<12])
                ))
            case 0x01:
                guard bytes.count == 5 else { return .malformedKnownPacket }
                return .event(.loginResponse(code: bytes[4]))
            default:
                return .notRecognized
            }

        default:
            return .notRecognized
        }
    }
}
