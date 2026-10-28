import Combine
import Foundation

/// Read-only native game-server handshake observer.
///
/// A real ThanhThan login requires an independently verified protocol and
/// negotiated cipher. This observer NEVER sends account credentials or
/// marks a player authenticated; it only reports server hello packets.
final class MUGameServerObserver: ObservableObject {
    enum Status: Equatable {
        case idle
        case connecting
        case waitingForHello
        case serverHello(playerID: UInt16, version: Data)
        case serverRejected
        case encryptedProtocolUnsupported
        case protocolError
        case disconnected
        case error(String)
    }

    @Published private(set) var status: Status = .idle
    private var flow = MUGameSessionFlow()
    private lazy var transport = MUTransport(
        onStatus: { [weak self] state in self?.handleStatus(state) },
        onPacket: { [weak self] packet in self?.handlePacket(packet) }
    )

    /// Only connect to a game server the user owns or is authorized to access.
    /// No endpoint is hardcoded, no game traffic is fabricated.
    func observe(host: String, port: UInt16) {
        flow.reset()
        status = .connecting
        transport.connect(host: host, port: port)
    }

    func disconnect() {
        flow.reset()
        status = .disconnected
        transport.disconnect()
    }

    private func handleStatus(_ state: MUTransport.ConnectionStatus) {
        switch state {
        case .connecting:
            status = .connecting
        case .connected:
            flow.beginSession()
            status = .waitingForHello
        case .disconnected:
            flow.reset()
            status = .disconnected
        case .failed(let reason):
            flow.reset()
            status = .error(reason)
        }
    }

    private func handlePacket(_ packet: MUWirePacket) {
        // No login request is sent by this observer.
        _ = flow.receive(packet)
        switch flow.phase {
        case .loginReady(let playerID, let version):
            status = .serverHello(playerID: playerID, version: version)
        case .serverRejected:
            status = .serverRejected
        case .encryptionUnsupported:
            status = .encryptedProtocolUnsupported
        case .protocolError:
            status = .protocolError
        default:
            break
        }
    }
}
