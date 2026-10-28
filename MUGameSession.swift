import Foundation

/// State of a MU game-server session as documented by OpenMU Season 6.
///
/// This is a protocol foundation, not a ThanhThan login implementation.
/// A real client must still negotiate the actual version, ciphers and
/// authentication packet format before markLoginRequestSubmitted() is valid.
enum MUGameSessionPhase: Equatable {
    case idle
    case waitingForGameHello
    case loginReady(playerID: UInt16, version: Data)
    case waitingForLoginResponse
    case loginRejected(code: UInt8)
    case waitingForCharacterList
    case charactersAvailable(MUCharacterListSnapshot)
    case serverRejected
    case encryptionUnsupported
    case characterFormatUnsupported
    case protocolError
}

enum MUGameSessionCommands {
    /// OpenMU C1/F3/00, request the authenticated account's characters.
    /// Does NOT include credentials and must never be sent before login.
    static func requestCharacterList(language: UInt8 = 0) -> Data {
        Data([0xC1, 0x05, 0xF3, 0x00, language])
    }
}

/// Pure deterministic state machine. No real endpoint, credentials or
/// network traffic. Production code can attach this to MUTransport only
/// after an authorized login implementation is available.
struct MUGameSessionFlow {
    private(set) var phase: MUGameSessionPhase = .idle
    let language: UInt8

    init(language: UInt8 = 0) {
        self.language = language
    }

    mutating func beginSession() {
        phase = .waitingForGameHello
    }

    mutating func reset() {
        phase = .idle
    }

    /// Mark an authenticated *request* as submitted (not as successful).
    /// Calling before the server's hello or calling twice is rejected.
    @discardableResult
    mutating func markLoginRequestSubmitted() -> Bool {
        guard case .loginReady = phase else { return false }
        phase = .waitingForLoginResponse
        return true
    }

    /// Handles complete, non-decrypted MU packets. Returns a character-list
    /// request only after the server replies that login succeeded.
    /// Server-specific variants and encrypted payloads are never guessed.
    mutating func receive(_ packet: MUWirePacket) -> Data? {
        switch phase {
        case .waitingForGameHello:
            switch MUServerPacketDecoder.decode(packet) {
            case .event(.gameServerEntered(let success, let playerID, let version)):
                if success {
                    phase = .loginReady(playerID: playerID, version: version)
                } else {
                    phase = .serverRejected
                }
            case .encryptedPayload:
                phase = .encryptionUnsupported
            case .malformedKnownPacket:
                phase = .protocolError
            default:
                break
            }
            return nil

        case .waitingForLoginResponse:
            switch MUServerPacketDecoder.decode(packet) {
            case .event(.loginResponse(let code)):
                if code == 1 {
                    phase = .waitingForCharacterList
                    return MUGameSessionCommands.requestCharacterList(language: language)
                }
                phase = .loginRejected(code: code)
            case .encryptedPayload:
                phase = .encryptionUnsupported
            case .malformedKnownPacket:
                phase = .protocolError
            default:
                break
            }
            return nil

        case .waitingForCharacterList:
            switch MUCharacterListDecoder.decode(packet) {
            case .list(let characters):
                phase = .charactersAvailable(characters)
            case .encryptedPayload:
                phase = .encryptionUnsupported
            case .unsupportedVariant:
                phase = .characterFormatUnsupported
            case .malformed:
                phase = .protocolError
            case .notCharacterList:
                if case .malformedKnownPacket = MUServerPacketDecoder.decode(packet) {
                    phase = .protocolError
                }
            }
            return nil

        default:
            return nil
        }
    }
}
