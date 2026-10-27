import Foundation
import Network

/// Raw TCP transport for a potential future MU client session.
///
/// This layer intentionally does NOT implement ThanhThan authentication,
/// handshake, encryption, character selection, or game state. It only
/// delivers complete MU C1/C2/C3/C4 frames to a caller supplied onPacket.
/// Never place account passwords or encryption keys in source control.
final class MUTransport {
    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    /// Callbacks are delivered on the main queue. Keep gameplay processing
    /// lightweight, or hand packets to a dedicated world-update queue.
    typealias StatusHandler = (ConnectionStatus) -> Void
    typealias PacketHandler = (MUWirePacket) -> Void

    private let networkQueue = DispatchQueue(label: "thanhthan.mu.network")
    private let onStatus: StatusHandler
    private let onPacket: PacketHandler

    // These properties are only accessed on networkQueue.
    private var connection: NWConnection?
    private var framer = MUWireFramer()

    init(onStatus: @escaping StatusHandler, onPacket: @escaping PacketHandler) {
        self.onStatus = onStatus
        self.onPacket = onPacket
    }

    /// Starts a TCP session to a caller-provided endpoint. The endpoint must
    /// be verified and authorized independently of this transport layer.
    func connect(host: String, port: UInt16) {
        networkQueue.async { [self] in
            cancelCurrentConnection()
            guard !host.isEmpty, let remotePort = NWEndpoint.Port(rawValue: port), port != 0 else {
                notifyStatus(.failed("Invalid server endpoint"))
                return
            }

            let client = NWConnection(
                host: NWEndpoint.Host(host),
                port: remotePort,
                using: .tcp
            )
            connection = client
            framer.reset()
            notifyStatus(.connecting)

            client.stateUpdateHandler = { [weak self, weak client] state in
                guard let self, let client, self.connection === client else { return }
                switch state {
                case .ready:
                    self.notifyStatus(.connected)
                    self.receiveNext(from: client)
                case .failed(let error):
                    self.notifyStatus(.failed(error.localizedDescription))
                    self.cancelCurrentConnection()
                case .cancelled:
                    self.notifyStatus(.disconnected)
                    self.cancelCurrentConnection()
                default:
                    break
                }
            }
            client.start(queue: networkQueue)
        }
    }

    /// Call only with protocol-appropriate, already encoded bytes.
    /// The framing codec alone is not sufficient for a login handshake.
    func send(_ encodedPacket: Data) {
        networkQueue.async { [self] in
            guard let connection else {
                notifyStatus(.failed("Not connected"))
                return
            }
            connection.send(content: encodedPacket, completion: .contentProcessed { [weak self] error in
                if let error { self?.notifyStatus(.failed(error.localizedDescription)) }
            })
        }
    }

    func disconnect() {
        networkQueue.async { [self] in
            cancelCurrentConnection()
            notifyStatus(.disconnected)
        }
    }

    private func receiveNext(from client: NWConnection) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self, weak client] data, _, isComplete, error in
            guard let self, let client, self.connection === client else { return }
            if let data, !data.isEmpty {
                do {
                    let frames = try self.framer.feed(data)
                    for packet in frames {
                        DispatchQueue.main.async { [onPacket = self.onPacket] in
                            onPacket(packet)
                        }
                    }
                } catch {
                    self.notifyStatus(.failed("Malformed MU envelope: \(error)"))
                    self.cancelCurrentConnection()
                    return
                }
            }

            if let error {
                self.notifyStatus(.failed(error.localizedDescription))
                self.cancelCurrentConnection()
            } else if isComplete {
                self.cancelCurrentConnection()
                self.notifyStatus(.disconnected)
            } else {
                self.receiveNext(from: client)
            }
        }
    }

    private func notifyStatus(_ status: ConnectionStatus) {
        DispatchQueue.main.async { [onStatus] in onStatus(status) }
    }

    private func cancelCurrentConnection() {
        let old = connection
        connection = nil
        old?.stateUpdateHandler = nil
        old?.cancel()
        framer.reset()
    }
}
