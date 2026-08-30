import Foundation
import PokeTokenBarShared

/// HTTP client that fetches the phone payload from the Mac server.
struct PhonePayloadClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(host: String, port: UInt16 = 7845, pairingCode: String) async throws -> PhonePayload {
        let url = URL(string: "http://\(host):\(port)/stats")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("Bearer \(pairingCode)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            // 401 은 "Mac 을 못 찾음"이 아니라 "코드가 없거나 틀림"이다. 뭉뚱그리면 사용자가
            // 네트워크를 의심하며 시간을 버린다.
            throw code == 401 ? PhonePayloadError.pairingRequired : PhonePayloadError.httpError(code)
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
    case pairingRequired

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return String(localized: "Server returned HTTP \(code)")
        case .connectionFailed: return String(localized: "Cannot connect to Mac")
        case .pairingRequired:
            return String(localized: "Enter the pairing code shown in PokeTokenBar Settings on your Mac")
        }
    }
}
