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

    print("MU Wire Protocol: all 7 framing checks passed.")
} catch {
    fatalError("MU Wire Protocol check failed: \(error)")
}
