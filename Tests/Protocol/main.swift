import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

do {
    let c1 = try MUWireCodec.makePlain(type: .c1, body: [0xF4, 0x06])
    check(Array(c1) == [0xC1, 0x04, 0xF4, 0x06], "Incorrect C1 header")
    let c2 = try MUWireCodec.makePlain(
        type: .c2,
        body: [0xF4] + Array(repeating: UInt8(0x7A), count: 280)
    )
    check(c2.count == 284, "Incorrect C2 packet size")
    check(c2[0] == 0xC2 && c2[1] == 0x01 && c2[2] == 0x1C, "Incorrect C2 length")

    var framer = MUWireFramer()
    let partial = try framer.feed(Data([0xC1, 0x04]))
    check(partial.isEmpty, "Partial header/frame must wait")
    let first = try framer.feed(Data([0xF4, 0x06]))
    check(first.count == 1 && first[0].type == .c1, "Fragmented C1 failed")
    check(first[0].body == Data([0xF4, 0x06]), "C1 body lost")
    check(framer.bufferedByteCount == 0, "Framer did not drain C1")

    let combined = c2 + Data([0xC3, 0x04, 0xAA, 0xBB]) + c1
    let packets = try framer.feed(combined)
    check(packets.count == 3, "Coalesced packets failed")
    check(packets[0].type == .c2, "C2 lost")
    check(packets[1].type == .c3 && packets[1].body.count == 2, "C3 framing failed")
    check(packets[2].type == .c1, "Trailing C1 lost")
    
    // Stress coalesced TCP reads: short packets must retain their ordering
    // without repeatedly shifting the entire buffer. The last C2 header
    // intentionally arrives across separate reads.
    var batchFramer = MUWireFramer()
    var batch = Data()
    for _ in 0..<4096 { batch.append(c1) }
    batch.append(Data([0xC2, 0x00]))
    let batchPackets = try batchFramer.feed(batch)
    check(batchPackets.count == 4096, "Coalesced frame batch lost packets")
    check(batchPackets.allSatisfy({ $0.data == c1 }), "Coalesced packet bytes changed")
    check(batchFramer.bufferedByteCount == 2, "Partial C2 header was not retained")
    let tail = try batchFramer.feed(Data([0x04, 0xF4]))
    check(tail.count == 1 && tail[0].data == Data([0xC2, 0x00, 0x04, 0xF4]),
          "Fragmented trailing C2 frame was not recovered")
    check(batchFramer.bufferedByteCount == 0, "Batch buffer was not drained")
    
    // The buffer limit applies even when no complete packet can be decoded.
    var bounded = MUWireFramer(maximumBufferedBytes: 8)
    _ = try bounded.feed(Data([0xC2, 0x00, 0x08, 0xF4, 0x06, 0x00, 0x01]))
    do {
        _ = try bounded.feed(Data([0x00, 0x01]))
        fatalError("Oversized buffered TCP input was accepted")
    } catch MUWireError.bufferOverflow {
        // Expected: never grow beyond the configured bound.
    }


    var invalid = MUWireFramer()
    do {
        _ = try invalid.feed(Data([0x00, 0x04, 0xFF, 0xFF]))
        fatalError("Invalid packet type accepted")
    } catch MUWireError.unknownPacketType(0x00) {
        // Expected.
    }

    do {
        _ = try MUWireCodec.makePlain(type: .c3, body: [0xF1])
        fatalError("Encrypted packet construction unexpectedly allowed")
    } catch MUWireError.outgoingEncryptedPacketNotSupported {
        // Expected.
    }


    // Documented OpenMU server packets, tested ONLY with synthetic fixtures.
    let hello = MUWirePacket(type: .c1, data: Data([0xC1, 0x04, 0x00, 0x01]))
    check(MUServerPacketDecoder.decode(hello) == .event(.connectHello), "Hello packet decode failed")

    let listData: [UInt8] = [
        0xC2, 0x00, 0x0F, 0xF4, 0x06, 0x00, 0x02,
        0x01, 0x00, 0x3C, 0x00,
        0x02, 0x00, 0x64, 0x01
    ]
    let listPacket = MUWirePacket(type: .c2, data: Data(listData))
    let expectedServers = [
        MUListedServer(id: 1, loadPercent: 60, optionByte: 0),
        MUListedServer(id: 2, loadPercent: 100, optionByte: 1)
    ]
    check(MUServerPacketDecoder.decode(listPacket) == .event(.serverList(expectedServers)),
          "Server list decode failed")

    var addressBytes: [UInt8] = [0xC1, 0x16, 0xF4, 0x03]
    let host = Array("127.0.0.1".utf8)
    addressBytes.append(contentsOf: host)
    addressBytes.append(contentsOf: repeatElement(UInt8(0), count: 16 - host.count))
    let port: UInt16 = 55901
    addressBytes.append(UInt8(port & 0xFF))
    addressBytes.append(UInt8((port >> 8) & 0xFF))
    check(MUServerPacketDecoder.decode(
        MUWirePacket(type: .c1, data: Data(addressBytes))
    ) == .event(.serverAddress(host: "127.0.0.1", port: 55901)),
          "Connect server hand-off address decode failed")

    let entered = MUWirePacket(type: .c1, data: Data([
        0xC1, 0x0C, 0xF1, 0x00, 0x01, 0x00, 0x42,
        0x31, 0x2E, 0x30, 0x30, 0x41
    ]))
    check(MUServerPacketDecoder.decode(entered) == .event(.gameServerEntered(
        success: true, playerID: 66, version: Data("1.00A".utf8)
    )), "Game server enter decode failed")

    let login = MUWirePacket(type: .c1, data: Data([0xC1, 0x05, 0xF1, 0x01, 0x01]))
    check(MUServerPacketDecoder.decode(login) == .event(.loginResponse(code: 1)),
          "Login response decode failed")

    let cipher = MUWirePacket(type: .c3, data: Data([0xC3, 0x04, 0xF1, 0x01]))
    check(MUServerPacketDecoder.decode(cipher) == .encryptedPayload,
          "Encrypted payload must remain opaque")

    var malformedList = listData
    malformedList[6] = 3
    check(MUServerPacketDecoder.decode(
        MUWirePacket(type: .c2, data: Data(malformedList))
    ) == .malformedKnownPacket, "Truncated server list accepted")

    var badHost = addressBytes
    badHost[4] = 0x0A // newline must not enter a host name
    check(MUServerPacketDecoder.decode(
        MUWirePacket(type: .c1, data: Data(badHost))
    ) == .malformedKnownPacket, "Unsafe host name accepted")

    let unknown = MUWirePacket(type: .c1, data: Data([0xC1, 0x04, 0x7F, 0x01]))
    check(MUServerPacketDecoder.decode(unknown) == .notRecognized,
          "Unknown packet must not be guessed")


    var session = MUConnectServerFlow()
    session.beginSession()
    check(session.phase == .waitingForHello, "Negotiation must wait for hello")
    check(session.requestServer(1) == nil, "Cannot select server before server list")
    let askList = session.receive(.event(.connectHello))
    check(askList == Data([0xC1, 0x04, 0xF4, 0x06]),
          "Connect server list request bytes mismatch")
    check(session.phase == .waitingForServerList, "Server list negotiation phase incorrect")
    check(session.receive(.event(.serverList(expectedServers))) == nil,
          "Server list should not auto-select a server")
    check(session.phase == .serversAvailable(expectedServers),
          "Server list must be retained")
    check(session.requestServer(3) == nil, "Unknown server ID must be rejected")
    check(session.requestServer(2) == Data([0xC1, 0x06, 0xF4, 0x03, 0x02, 0x00]),
          "Server selection request bytes mismatch")
    check(session.phase == .waitingForServerAddress(2),
          "Server address negotiation phase incorrect")
    check(session.receive(.event(.serverAddress(host: "127.0.0.1", port: 55901))) == nil,
          "Server handoff must not initiate a hidden connection")
    check(session.phase == .serverAddressResolved(host: "127.0.0.1", port: 55901),
          "Game server address was not retained")
    session.reset()
    check(session.phase == .idle, "Reset must clear session")
    session.beginSession()
    check(session.receive(.malformedKnownPacket) == nil &&
          session.phase == .protocolError,
          "Malformed server reply should abort negotiation")


    // Synthetic Season 6 F3/00 character records, no personal account data.
    var standard = [UInt8](repeating: 0, count: 34)
    standard[0] = 2                           // character slot
    for (i, byte) in Array("TestKnight".utf8).enumerated() { standard[1 + i] = byte }
    standard[12] = 0x2A                      // level 298, little endian
    standard[13] = 0x01
    standard[14] = 0x00
    standard[33] = 0xFF                       // no guild
    let standardFrame = [UInt8]([0xC1, 42, 0xF3, 0x00, 0, 0, 1, 0]) + standard
    let decodedStandard = MUCharacterListDecoder.decode(MUWirePacket(
        type: .c1, data: Data(standardFrame)
    ))
    if case .list(let list) = decodedStandard {
        check(list.variant == .standard, "Standard F3/00 variant not identified")
        check(list.characters.count == 1, "Standard F3/00 count mismatch")
        check(list.characters[0].name == "TestKnight", "Character name incorrectly decoded")
        check(list.characters[0].level == 298, "Character level incorrectly decoded")
        check(list.characters[0].appearance.count == 18, "Standard appearance must stay opaque")
    } else { fatalError("Documented standard character list not decoded") }

    var extended = [UInt8](repeating: 0, count: 44)
    extended[0] = 1
    for (i, byte) in Array("TestElf".utf8).enumerated() { extended[1 + i] = byte }
    extended[12] = 0x90
    extended[13] = 0x01
    extended[42] = 0x80
    let extendedFrame = [UInt8]([0xC1, 52, 0xF3, 0x00, 2, 0, 1, 1]) + extended
    let decodedExtended = MUCharacterListDecoder.decode(MUWirePacket(
        type: .c1, data: Data(extendedFrame)
    ))
    if case .list(let list) = decodedExtended {
        check(list.variant == .extended, "Extended F3/00 variant not identified")
        check(list.vaultExtended, "Extended vault flag lost")
        check(list.characters[0].name == "TestElf", "Extended name decoded incorrectly")
        check(list.characters[0].level == 400, "Extended character level incorrect")
        check(list.characters[0].appearance.count == 27, "Extended appearance length incorrect")
    } else { fatalError("Documented extended character list not decoded") }

    var truncatedCharacterList = standardFrame
    truncatedCharacterList[6] = 2
    check(MUCharacterListDecoder.decode(MUWirePacket(
        type: .c1, data: Data(truncatedCharacterList)
    )) == .unsupportedVariant, "Character count mismatch must not be accepted")

    check(MUCharacterListDecoder.decode(MUWirePacket(
        type: .c3, data: Data([0xC3, 0x04, 0xF3, 0x00])
    )) == .encryptedPayload, "Never inspect encrypted character data")


    // Game server progression: hello -> explicit login request -> server
    // confirmation -> character list -> real-account snapshot format.
    // All packets in these tests are local, synthetic examples.
    var game = MUGameSessionFlow(language: 0)
    game.beginSession()
    check(game.phase == .waitingForGameHello, "Game session did not start")
    check(!game.markLoginRequestSubmitted(), "Login must wait for server hello")
    check(game.receive(entered) == nil, "Hello must not auto-send credentials")
    check(game.phase == .loginReady(
        playerID: 66, version: Data("1.00A".utf8)
    ), "Game-server hello state lost")
    check(game.markLoginRequestSubmitted(), "Expected explicit login transition")
    check(!game.markLoginRequestSubmitted(), "Duplicate login request was accepted")
    check(game.receive(login) == MUGameSessionCommands.requestCharacterList(language: 0),
          "Login success must trigger documented character-list request")
    check(game.phase == .waitingForCharacterList, "Game session skipped list phase")
    check(game.receive(MUWirePacket(type: .c1, data: Data(standardFrame))) == nil,
          "Character-list response must not trigger another request")
    if case .charactersAvailable(let snapshot) = game.phase {
        check(snapshot.characters.count == 1, "Game session lost character count")
        check(snapshot.characters[0].name == "TestKnight", "Game session lost character")
        check(snapshot.characters[0].level == 298, "Game session lost character level")
    } else { fatalError("Game session did not receive characters") }

    var rejected = MUGameSessionFlow()
    rejected.beginSession()
    _ = rejected.receive(entered)
    check(rejected.markLoginRequestSubmitted(), "Rejected login fixture not initialized")
    check(rejected.receive(MUWirePacket(
        type: .c1, data: Data([0xC1, 0x05, 0xF1, 0x01, 0x00])
    )) == nil && rejected.phase == .loginRejected(code: 0),
          "Wrong-password result cannot be treated as successful")
    check(rejected.receive(MUWirePacket(
        type: .c1, data: Data(standardFrame)
    )) == nil, "Character list must not be accepted after rejected login")

    var encryptedGame = MUGameSessionFlow()
    encryptedGame.beginSession()
    _ = encryptedGame.receive(entered)
    _ = encryptedGame.markLoginRequestSubmitted()
    check(encryptedGame.receive(cipher) == nil &&
          encryptedGame.phase == .encryptionUnsupported,
          "Encrypted login response must not be misread as plaintext")
    encryptedGame.reset()
    check(encryptedGame.phase == .idle, "Game session reset failed")

    print("MU protocol: framing, ConnectServer, character list and game-session tests passed.")
} catch {
    fatalError("MU Wire Protocol check failed: \(error)")
}
