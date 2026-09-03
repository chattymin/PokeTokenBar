import Foundation

/// Antigravity 의 Google OAuth 클라이언트는 **confidential client** 다 — refresh_token 그랜트에
/// `client_secret` 이 없으면 Google 이 항상 `400 {"error":"invalid_request",
/// "error_description":"client_secret is missing."}` 를 돌려준다. #44 가 넣은 자동 갱신이 단 한 번도
/// 성공하지 못하고 매시간(액세스 토큰 수명) Keychain 프롬프트로 떨어진 원인이 이것이다.
///
/// **secret 을 저장소에 커밋하지 않는다.** `antigravity-credential.json`(평문 0600)에 들어 있는
/// refresh token 은 회전하지 않고 `cloud-platform` 스코프를 포함한다. 지금 그 파일은 secret 이 없어
/// **단독으로는 아무것도 못 하는** 상태이고, 공개 레포에 secret 을 올리는 순간 그 성질이 사라진다
/// (파일 유출 = 갱신 가능한 GCP 액세스). 그 성질을 유지하는 게 이 타입의 존재 이유다.
///
/// 대신 **이미 설치된 Antigravity 바이너리에서 런타임에 읽는다.** secret 은 거기 평문으로 들어 있고,
/// Antigravity 가 설치돼 있지 않으면 애초에 이 한도를 볼 이유도 없다. 로컬 공격자 기준으로는 어차피
/// 같은 바이너리를 읽을 수 있으므로 보안 경계가 아니다 — 유출된 *파일 하나*의 가치를 낮게 유지하는
/// 조치이지, 그 이상을 주장하지 않는다.
enum AntigravityClientSecret {
    static let prefix = "GOCSPX-"

    /// Google 클라이언트 secret 본문 길이(고정 28자).
    ///
    /// 왜 고정 길이인가: 바이너리 안에서 secret 두 개가 **구분자 없이 연달아** 놓여 있다
    /// (Go 문자열 상수 블롭 — `…/authorize` + secret + secret + `https://…`). 그래서
    /// `GOCSPX-[A-Za-z0-9_-]+` 같은 탐욕적 매칭은 둘과 뒤따르는 `https` 까지 한 덩어리로 삼킨다.
    /// 접두사 위치마다 정확히 28바이트를 끊어야 후보 두 개가 그대로 나온다.
    static let bodyLength = 28

    /// secret 을 품고 있는 것으로 확인된 바이너리들. IDE 와 CLI 중 하나만 깔았어도 되게 둘 다 본다.
    static func candidateBinaryURLs(
        fileManager: FileManager = .default,
        home: URL? = nil
    ) -> [URL] {
        let home = home ?? fileManager.homeDirectoryForCurrentUser
        let paths = [
            URL(fileURLWithPath: "/Applications/Antigravity.app/Contents/Resources/bin/language_server"),
            home.appendingPathComponent("Applications/Antigravity.app/Contents/Resources/bin/language_server"),
            home.appendingPathComponent(".gemini/bin/agy"),
        ]
        return paths.filter { fileManager.fileExists(atPath: $0.path) }
    }

    /// 설치된 바이너리 전부에서 후보 secret 을 모은다(중복 제거, 발견 순서 유지).
    static func candidates(
        fileManager: FileManager = .default,
        home: URL? = nil,
        binaryURLs: [URL]? = nil
    ) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for url in binaryURLs ?? candidateBinaryURLs(fileManager: fileManager, home: home) {
            for secret in candidates(inBinaryAt: url) where seen.insert(secret).inserted {
                ordered.append(secret)
            }
        }
        return ordered
    }

    /// 바이너리 하나를 훑는다. 146MB 급이라 통째로 읽지 않고 mmap 한다(`.mappedIfSafe`) —
    /// 페이지는 스캔하면서 들어오고 곧 회수 대상이 된다. 실측 스캔 시간은 파일당 수십 ms.
    static func candidates(inBinaryAt url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        return candidates(in: data)
    }

    /// 순수 함수 — 픽스처로 테스트한다.
    static func candidates(in data: Data) -> [String] {
        let needle = Array(prefix.utf8)
        let total = needle.count + bodyLength
        var seen = Set<String>()
        var ordered: [String] = []

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard raw.count >= total else { return }
            let bytes = raw.bindMemory(to: UInt8.self)
            var index = 0
            let last = bytes.count - total
            while index <= last {
                guard bytes[index] == needle[0] else {
                    index += 1
                    continue
                }
                var matched = true
                for offset in 1..<needle.count where bytes[index + offset] != needle[offset] {
                    matched = false
                    break
                }
                guard matched else {
                    index += 1
                    continue
                }

                var body = [UInt8]()
                body.reserveCapacity(bodyLength)
                var valid = true
                for offset in 0..<bodyLength {
                    let byte = bytes[index + needle.count + offset]
                    guard isSecretBodyByte(byte) else {
                        valid = false
                        break
                    }
                    body.append(byte)
                }
                if valid, let suffix = String(bytes: body, encoding: .utf8) {
                    let secret = prefix + suffix
                    if seen.insert(secret).inserted { ordered.append(secret) }
                }
                // 매칭 성공 여부와 무관하게 접두사 길이만 전진한다 — secret 이 맞닿아 있어
                // 전체 길이를 건너뛰면 바로 뒤에 붙은 두 번째 후보를 놓친다.
                index += needle.count
            }
        }
        return ordered
    }

    /// base64url 문자셋(Google secret 본문) — `A-Za-z0-9_-`.
    private static func isSecretBodyByte(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A)      // A-Z
            || (byte >= 0x61 && byte <= 0x7A)  // a-z
            || (byte >= 0x30 && byte <= 0x39)  // 0-9
            || byte == 0x5F                    // _
            || byte == 0x2D                    // -
    }
}
