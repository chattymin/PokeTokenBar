import Foundation

/// 페어링 코드 — 폰이 Mac 의 페이로드를 가져올 때 제시하는 공유 비밀.
///
/// 서버는 `*:7845` 로 모든 인터페이스에 바인딩되고 Bonjour(`_poketokenbar._tcp.`)로 광고까지 하므로,
/// 인증이 없으면 같은 네트워크(카페·호텔·컨퍼런스 wifi)의 누구나 사용량·한도·플랜·도감을 읽을 수 있다.
/// 로컬 바인딩으로는 못 막는다 — 폰이 LAN 에서 접속해야 하는 것이 이 기능의 목적이기 때문이다.
enum PhonePairingCode {
    /// Crockford Base32 에서 혼동 문자(I·L·O·U)를 뺀 집합 — 사람이 화면에서 옮겨 적는 코드라서.
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let length = 8

    /// 32^8 ≈ 2^40. LAN 스캐너가 맞히기엔 충분히 크고(초당 1000회로도 수십 년), 손으로 옮겨 적기엔
    /// 충분히 짧다. `SystemRandomNumberGenerator` 는 애플 플랫폼에서 암호학적으로 안전하다.
    static func generate() -> String {
        String((0..<length).map { _ in alphabet.randomElement()! })
    }
}

/// `PhonePayloadServer` 의 요청 판정 — 순수 함수로 분리해 픽스처로 테스트한다.
/// `handleRequest` 안에 두면 `NWConnection` 없이는 인증 분기를 검증할 방법이 없다
/// (`OAuthProfileData` 와 같은 이유로 분리).
enum PhoneRequestRouter {
    enum Outcome: Equatable {
        case payload
        case noPayloadYet
        case health
        case unauthorized
        case badRequest
        case notFound
    }

    static func route(requestLine: String,
                      authorization: String?,
                      pairingCode: String,
                      hasPayload: Bool) -> Outcome
    {
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return .badRequest }

        switch (parts[0], parts[1]) {
        case ("GET", "/stats"):
            guard isAuthorized(authorization, pairingCode: pairingCode) else { return .unauthorized }
            return hasPayload ? .payload : .noPayloadYet
        case ("GET", "/health"):
            // 도달 가능 여부만 답한다(포트·상태). 개인 데이터가 없어 페어링 전에도 열어 둔다 —
            // 폰이 "코드가 틀렸다"와 "Mac 이 안 보인다"를 구분할 수 있어야 한다.
            return .health
        default:
            return .notFound
        }
    }

    /// `Authorization: Bearer <code>`.
    ///
    /// **빈 페어링 코드는 무엇으로도 통과시키지 않는다.** 코드가 아직 생성되지 않았거나 저장소에서
    /// 빈 문자열로 읽혔을 때 `"" == ""` 로 인증이 열리는 것이 이 부류의 전형적인 구멍이다.
    static func isAuthorized(_ header: String?, pairingCode: String) -> Bool {
        guard !pairingCode.isEmpty, let header else { return false }
        let prefix = "Bearer "
        guard header.hasPrefix(prefix) else { return false }
        let presented = String(header.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespaces)
        return constantTimeEquals(presented, pairingCode)
    }

    /// 같은 길이면 조기 반환 없이 전체를 비교한다. LAN 코드에 타이밍 공격이 현실적이진 않지만,
    /// 비교 한 곳을 올바르게 쓰는 비용이 거의 0 이라 기본값으로 둔다.
    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }

    /// 헤더 블록에서 Authorization 값 추출. HTTP 헤더 이름은 대소문자를 구분하지 않는다.
    static func authorizationHeader(in request: String) -> String? {
        for line in request.components(separatedBy: "\r\n").dropFirst() {
            if line.isEmpty { break }   // 헤더 끝 — 본문은 보지 않는다
            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2,
                  pieces[0].trimmingCharacters(in: .whitespaces).lowercased() == "authorization"
            else { continue }
            return pieces[1].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
