import Foundation
import PokeTokenBarShared

/// HTTP client that fetches the phone payload from the Mac server.
struct PhonePayloadClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(host: String, port: UInt16 = 7845) async throws -> PhonePayload {
        let url = URL(string: "http://\(host):\(port)/stats")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PhonePayloadError.httpError(code)
        }
        return try JSONDecoder().decode(PhonePayload.self, from: data)
    }

    func checkHealth(host: String, port: UInt16 = 7845) async throws -> Bool {
        let url = URL(string: "http://\(host):\(port)/health")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}

enum PhonePayloadError: LocalizedError {
    case httpError(Int)
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return String(localized: "Server returned HTTP \(code)")
        case .connectionFailed: return String(localized: "Cannot connect to Mac")
        }
    }
}
