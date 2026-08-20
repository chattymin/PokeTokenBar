import Foundation
import Network
import PokeTokenBarShared

/// Lightweight HTTP server that serves the phone payload for iPhone companion app.
/// Uses Network.framework (NWListener) — no external dependencies.
@MainActor
final class PhonePayloadServer {
    private var listener: NWListener?
    private var payload: Data?
    private var connections: [NWConnection] = []
    private var netService: NetService?

    /// Server state for UI binding.
    private(set) var isRunning = false
    private(set) var port: UInt16 = 0
    private(set) var errorMessage: String?

    /// advertised port for UI display.
    var displayPort: String { isRunning ? "\(port)" : "—" }

    func start(port: UInt16 = 7845) {
        guard !isRunning else { return }
        self.port = port
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.errorMessage = nil
                        self.startBonjour()
                        AppLog.write("phone server started port=\(self.port)")
                    case .failed(let error):
                        self.isRunning = false
                        self.errorMessage = "\(error)"
                        AppLog.write("phone server failed: \(error)")
                    case .cancelled:
                        self.isRunning = false
                        AppLog.write("phone server stopped")
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleConnection(connection)
                }
            }

            listener.start(queue: .main)
            self.listener = listener
        } catch {
            errorMessage = "\(error)"
            AppLog.write("phone server start failed: \(error)")
        }
    }

    func stop() {
        netService?.stop()
        netService = nil
        listener?.cancel()
        listener = nil
        for conn in connections { conn.cancel() }
        connections.removeAll()
        isRunning = false
        port = 0
        payload = nil
        AppLog.write("phone server stopped")
    }

    func updatePayload(_ data: Data) {
        payload = data
    }

    // MARK: - Bonjour

    private func startBonjour() {
        let service = NetService(domain: "local.", type: "_poketokenbar._tcp.", name: "PokeTokenBar", port: Int32(port))
        service.publish()
        netService = service
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)
        receiveRequest(connection)
    }

    private func receiveRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data, !data.isEmpty {
                    self.handleRequest(data, connection: connection)
                } else if isComplete || error != nil {
                    connection.cancel()
                    self.connections.removeAll { $0 === connection }
                }
            }
        }
    }

    private func handleRequest(_ data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else {
            let body = Data("Bad Request".utf8)
            sendResponse(connection: connection, status: 400, body: body)
            return
        }

        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            let body = Data("Bad Request".utf8)
            sendResponse(connection: connection, status: 400, body: body)
            return
        }

        let method = parts[0]
        let path = parts[1]

        switch (method, path) {
        case ("GET", "/stats"):
            if let payload {
                sendResponse(connection: connection, status: 200, body: payload,
                             contentType: "application/json")
            } else {
                let body = Data("{\"error\":\"no data\"}".utf8)
                sendResponse(connection: connection, status: 503, body: body,
                             contentType: "application/json")
            }
        case ("GET", "/health"):
            let health = Data("{\"status\":\"ok\",\"port\":\(port)}".utf8)
            sendResponse(connection: connection, status: 200, body: health,
                         contentType: "application/json")
        default:
            let body = Data("{\"error\":\"not found\"}".utf8)
            sendResponse(connection: connection, status: 404, body: body,
                         contentType: "application/json")
        }
    }

    private func sendResponse(connection: NWConnection, status: Int, body: Data,
                              contentType: String = "text/plain") {
        var header = "HTTP/1.1 \(status) \(statusText(status))\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"
        guard let headerData = header.data(using: .utf8) else { return }
        var response = headerData
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak connection] _ in
            Task { @MainActor [weak self] in
                connection?.cancel()
                self?.connections.removeAll { $0 === connection }
            }
        })
    }

    private func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 503: return "Service Unavailable"
        default: return "Unknown"
        }
    }
}
