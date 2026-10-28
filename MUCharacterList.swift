import Foundation

/// Character records from the public MU Season 6 F3/00 packet description.
/// This only parses inbound character-list bytes after authentication.
/// It neither authenticates accounts nor verifies ThanhThan compatibility.
///
/// Reference: MUnique/OpenMU docs/Packets/C1-F3-00-CharacterList_by-server.md
/// and C1-F3-00-CharacterListExtended_by-server.md (MIT project).
enum MUCharacterListVariant: Equatable {
    case standard // 34-byte record
    case extended // 44-byte record
}

struct MUCharacterSnapshot: Equatable {
    let slot: UInt8
    let name: String
    let level: UInt16
    /// Source bytes are retained because class/equipment packing varies by season.
    let statusBits: UInt8
    let appearance: Data
    let guildRole: UInt8
    let originalRecord: Data
}

struct MUCharacterListSnapshot: Equatable {
    let variant: MUCharacterListVariant
    let unlockFlags: UInt8
    let moveCount: UInt8
    let vaultExtended: Bool
    let characters: [MUCharacterSnapshot]
}

enum MUCharacterListDecodeResult: Equatable {
    case list(MUCharacterListSnapshot)
    case notCharacterList
    case encryptedPayload
    case malformed
    case unsupportedVariant
}

enum MUCharacterListDecoder {
    static func decode(_ packet: MUWirePacket) -> MUCharacterListDecodeResult {
        guard !packet.type.hasSimpleModulusEncryption else { return .encryptedPayload }
        let bytes = Array(packet.data)
        guard packet.type == .c1, bytes.count >= 4,
              bytes[2] == 0xF3, bytes[3] == 0x00 else { return .notCharacterList }
        guard bytes.count >= 8, bytes.count == Int(bytes[1]) else { return .malformed }

        let count = Int(bytes[6])
        guard count <= 32, bytes[7] <= 1 else { return .malformed }
        let variant: MUCharacterListVariant
        let size: Int
        if bytes.count == 8 + count * 34 {
            variant = .standard
            size = 34
        } else if count > 0 && bytes.count == 8 + count * 44 {
            variant = .extended
            size = 44
        } else {
            // F3/00 has several incompatible version-specific layouts.
            return .unsupportedVariant
        }

        var result: [MUCharacterSnapshot] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let start = 8 + index * size
            let record = Array(bytes[start..<(start + size)])
            let rawName = Array(record[1..<11])
            let nameBytes = Array(rawName.prefix(while: { $0 != 0 }))
            // MU character names are printable ASCII in the documented protocol.
            guard !nameBytes.isEmpty,
                  nameBytes.allSatisfy({ (0x20...0x7E).contains($0) }),
                  rawName.dropFirst(nameBytes.count).allSatisfy({ $0 == 0 }),
                  let name = String(bytes: nameBytes, encoding: .ascii)
            else { return .malformed }

            let level = UInt16(record[12]) | UInt16(record[13]) << 8
            let appearanceEnd = variant == .standard ? 33 : 42
            let guildIndex = variant == .standard ? 33 : 42
            result.append(MUCharacterSnapshot(
                slot: record[0],
                name: name,
                level: level,
                statusBits: record[14],
                appearance: Data(record[15..<appearanceEnd]),
                guildRole: record[guildIndex],
                originalRecord: Data(record)
            ))
        }

        return .list(MUCharacterListSnapshot(
            variant: variant,
            unlockFlags: bytes[4],
            moveCount: bytes[5],
            vaultExtended: bytes[7] == 1,
            characters: result
        ))
    }
}
