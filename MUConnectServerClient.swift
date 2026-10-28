import Combine
import Foundation

/// Optional native ConnectServer client for the documented MU Season 6 variant.
///
/// No host is hardcoded: a caller must provide an authorized server endpoint.
/// No username/password is requested or transmitted. This is NOT a ThanhThan
/// game-server login, and successful server discovery is not online gameplay.
final class MUConnectServerClient: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case waitingForHello
        case waitingForServerList
        case serversAvailable([MUListedServer])
        case waitingForServerAddress(UInt16)
        case addressResolved(host: String, port: UInt16)
        case disconnected
        case error(String)
    }

    @Published private(set) var state: State = .idle

    private var flow = MUConnectServerFlow()
    private lazy var transport = MUTransport(
        onStatus: { [weak self] status in self?.onStatus(status) },
        onPacket: { [weak self] packet in self?.onPacket(packet) }
    )

    func connect(host: String, port: UInt16) {
        flow.reset()
        state = .connecting
        transport.connect(host: host, port: port)
    }

    /// Sends the documented selection request only for a server ID advertised
    /// by the ConnectServer. It will NOT auto-connect to the game-server IP.
    @discardableResult
    func selectServer(id: UInt16) -> Bool {
        guard let request = flow.requestServer(id) else { return false }
        updateState()
        transport.send(request)
        return true
    }

    func disconnect() {
        flow.reset()
        state = .disconnected
        transport.disconnect()
    }

    private func onStatus(_ status: MUTransport.ConnectionStatus) {
        switch status {
        case .connecting:
            state = .connecting
        case .connected:
            flow.beginSession()
            updateState()
        case .disconnected:
            flow.reset()
            state = .disconnected
        case .failed(let description):
            flow.reset()
            state = .error(description)
        }
    }

    private func onPacket(_ packet: MUWirePacket) {
        let decoded = MUServerPacketDecoder.decode(packet)
        let response = flow.receive(decoded)
        updateState()
        if case .protocolError = flow.phase {
            transport.disconnect()
            state = .error("Malformed response from ConnectServer")
            return
        }
        if let response {
            // Documented unencrypted list/selection request only.
            transport.send(response)
        }
    }

    private func updateState() {
        switch flow.phase {
        case .idle:
            state = .idle
        case .waitingForHello:
            state = .waitingForHello
        case .waitingForServerList:
            state = .waitingForServerList
        case .serversAvailable(let servers):
            state = .serversAvailable(servers)
        case .waitingForServerAddress(let id):
            state = .waitingForServerAddress(id)
        case .serverAddressResolved(let host, let port):
            state = .addressResolved(host: host, port: port)
        case .protocolError:
            state = .error("Unexpected ConnectServer packet")
        }
    }
}
