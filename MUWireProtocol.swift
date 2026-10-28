import Foundation

// MU Online packet envelopes C1/C2/C3/C4.
// Reference: MUnique/OpenMU (MIT), docs/Packets/PacketTypes.md.
// This is independently written Swift framing code, not an authentication
// client, packet decryptor, or a claim of ThanhThan server compatibility.
enum MUWirePacketType: UInt8 {
    case c1 = 0xC1
    case c2 = 0xC2
    case c3 = 0xC3
    case c4 = 0xC4

    var headerLength: Int {
        switch self {
        case .c1, .c3: return 2
        case .c2, .c4: return 3
        }
    }

    var hasSimpleModulusEncryption: Bool {
        switch self {
        case .c1, .c2: return false
        case .c3, .c4: return true
        }
    }
}

enum MUWireError: Error, Equatable {
    case unknownPacketType(UInt8)
    case invalidLength(Int)
    case lengthOverflow(Int)
    case bufferOverflow
    case outgoingEncryptedPacketNotSupported
}

struct MUWirePacket {
    let type: MUWirePacketType
    let data: Data

    var body: Data {
        Data(data.dropFirst(type.headerLength))
    }
}

/// Splits arbitrary TCP byte chunks into complete MU packet envelopes.
/// TCP read boundaries are not packet boundaries. No packet is decrypted here.
struct MUWireFramer {
    private var buffer: [UInt8] = []
    let maximumBufferedBytes: Int

    init(maximumBufferedBytes: Int = 262_144) {
        self.maximumBufferedBytes = maximumBufferedBytes
    }

    var bufferedByteCount: Int { buffer.count }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    mutating func feed(_ chunk: Data) throws -> [MUWirePacket] {
        guard chunk.count <= maximumBufferedBytes - buffer.count else {
            throw MUWireError.bufferOverflow
        }
        buffer.append(contentsOf: chunk)

        var packets: [MUWirePacket] = []
        // TCP may coalesce hundreds of short frames in one read. Track a
        // cursor and compact once instead of shifting the entire array for
        // every frame (quadratic work for large frame batches).
        var consumed = 0
        while consumed < buffer.count {
            guard let type = MUWirePacketType(rawValue: buffer[consumed]) else {
                throw MUWireError.unknownPacketType(buffer[consumed])
            }
            let available = buffer.count - consumed
            guard available >= type.headerLength else { break }

            let packetLength: Int
            if type.headerLength == 2 {
                packetLength = Int(buffer[consumed + 1])
            } else {
                packetLength = (Int(buffer[consumed + 1]) << 8) | Int(buffer[consumed + 2])
            }
            guard packetLength > type.headerLength else {
                throw MUWireError.invalidLength(packetLength)
            }
            guard packetLength <= maximumBufferedBytes else {
                throw MUWireError.lengthOverflow(packetLength)
            }
            guard available >= packetLength else { break }

            packets.append(MUWirePacket(
                type: type,
                data: Data(buffer[consumed..<(consumed + packetLength)])
            ))
            consumed += packetLength
        }
        // Preserve an incomplete trailing header/frame for the next read.
        if consumed > 0 {
            buffer.removeFirst(consumed)
        }
        return packets
    }
}

enum MUWireCodec {
    /// Builds only a plain C1/C2 envelope. Outgoing MU traffic may additionally
    /// require XOR32, SimpleModulus, login handshakes and server-specific fields.
    /// Do not send this directly to a live server as an authentication attempt.
    static func makePlain(type: MUWirePacketType, body: [UInt8]) throws -> Data {
        guard type == .c1 || type == .c2 else {
            throw MUWireError.outgoingEncryptedPacketNotSupported
        }
        guard !body.isEmpty else { throw MUWireError.invalidLength(0) }

        let totalLength = type.headerLength + body.count
        guard totalLength <= (type == .c1 ? 255 : 65535) else {
            throw MUWireError.lengthOverflow(totalLength)
        }

        if type == .c1 {
            return Data([type.rawValue, UInt8(totalLength)] + body)
        }
        return Data([
            type.rawValue,
            UInt8((totalLength >> 8) & 0xFF),
            UInt8(totalLength & 0xFF)
        ] + body)
    }
}
