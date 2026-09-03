import XCTest
@testable import PokeTokenBar

/// 실계정 parity 검증 — `PTB_PARITY=1 swift test --filter AntigravityRefreshParityTests`.
///
/// 스텁 테스트로는 절대 잡히지 않는 부류를 잡는다: **우리가 Google 에 보내는 요청이 실제로 통하는가.**
/// #44 는 `tokenRefresher` 스텁이 성공을 흉내내는 바람에, 갱신이 한 번도 성공한 적 없는 상태로
/// 스위트가 초록이었다(`client_secret` 누락 → 400). 기본 실행에서는 건너뛴다 —
/// 실 자격증명·네트워크가 필요하고, CI 에서 사용자 토큰을 소비하면 안 된다.
final class AntigravityRefreshParityTests: XCTestCase {
    func testDiscoveredSecretRefreshesRealCredentialWithoutKeychain() async throws {
        try XCTSkipUnless(AppEnv.isParityRun)
        // 실 자격증명은 건드리지 않는다 — 복사본으로 돈다.
        let real = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/PokeTokenBar/antigravity-credential.json")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let copy = dir.appendingPathComponent("antigravity-credential.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: real.path),
                          "antigravity 자격증명이 없다 — 이 기기에서는 검증할 게 없다")
        try FileManager.default.copyItem(at: real, to: copy)

        XCTAssertFalse(AntigravityClientSecret.candidates().isEmpty,
                       "설치된 Antigravity 바이너리에서 client_secret 후보를 찾지 못했다")
        print("### candidates found: \(AntigravityClientSecret.candidates().count)")
        let cache = AntigravityTokenCache(tokenFileURLs: [], persistentStoreURL: copy)
        KeychainReader.resetQueryCountForTesting()
        // bypassCache 로 반드시 refresh 를 타게 한다(캐시된 토큰이 아직 살아 있어도).
        let token = try await cache.accessToken(allowKeychainPrompt: false, bypassCache: true)
        print("### refreshed access token length: \(token.count)")
        print("### keychain queries: \(KeychainReader.queryCount)")

        let status = try await AntigravityRateLimitsProvider(tokenCache: cache)
            .fetch(allowKeychainPrompt: false)
        print("### limits: \(status.groups.map { "\($0.displayName) \($0.buckets.map { b in "\(b.bucketId)=\(String(format: "%.1f", b.usedPercent))%" })" })")
        XCTAssertFalse(token.isEmpty)
        XCTAssertTrue(status.hasVisibleLimit)
        // 전체 사슬(secret 발견 → refresh → 한도 조회)이 프롬프트 없이 돌아야 한다.
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }
}
