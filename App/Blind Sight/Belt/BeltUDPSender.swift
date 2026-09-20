//
//  BeltUDPSender.swift
//  Blind Sight
//
//  Fire-and-forget UDP link from the phone to the ESP32 (PRD "Data Flow"). A dropped packet is
//  simply superseded by the next update, so nothing is retried and nothing here can block the
//  belt loop: send() only queues a datagram.
//

import Combine
import Foundation
import Network

final class BeltUDPSender: ObservableObject {
    @Published private(set) var status = "not started"
    @Published private(set) var packetsSent = 0
    @Published private(set) var host: String

    private var connection: NWConnection?
    private var isReady = false
    private let sequence = BeltSequenceCounter()
    private let queue = DispatchQueue(label: "belt.udp", qos: .userInitiated)

    init(host: String = AppConfig.esp32Host) {
        self.host = host
    }

    /// (Re)opens the socket, optionally pointing at a different host (e.g. a Mac running
    /// tools/belt_packet_listener.py while the ESP32 isn't available).
    func connect(host newHost: String? = nil) {
        if let newHost { host = newHost }
        connection?.cancel()
        isReady = false
        guard let port = NWEndpoint.Port(rawValue: AppConfig.esp32Port) else { return }

        let parameters = NWParameters.udp
        // The ESP32 joins the phone's Personal Hotspot; this link must never go out over cellular.
        // (Not "require wifi": clients of the phone's own hotspot are reached over a bridge interface.)
        parameters.prohibitedInterfaceTypes = [.cellular]
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor in
                guard let self, let connection, connection === self.connection else { return }
                self.handle(state)
            }
        }
        self.connection = connection
        status = "connecting to \(host):\(AppConfig.esp32Port)"
        connection.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isReady = false
        status = "stopped"
    }

    /// Sends one belt update. Dropped silently while the link isn't ready, so packets built
    /// before the belt was reachable can't arrive late as stale data.
    func send(_ command: BeltCommand) {
        guard isReady, let connection else { return }
        let data = command.packet(seq: sequence.next())
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            Task { @MainActor in self?.status = "send error: \(error)" }
        })
        packetsSent += 1
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            isReady = true
            status = "ready: \(host):\(AppConfig.esp32Port)"
        case .waiting(let error):
            isReady = false
            status = "waiting for a route to the belt (is Personal Hotspot on and the belt joined?): \(error)"
        case .failed(let error):
            isReady = false
            status = "failed: \(error) (retrying)"
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                self.connect()
            }
        case .cancelled:
            isReady = false
        case .setup, .preparing:
            isReady = false
        @unknown default:
            isReady = false
        }
    }
}
