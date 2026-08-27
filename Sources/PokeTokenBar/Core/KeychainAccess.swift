import Foundation

#if os(macOS)
import Darwin
import LocalAuthentication
import Security

enum KeychainAccessGate {
    /// 프로세스 전역 게이트(메모리) — 기동 시 저장값으로 1회 시드하고, 영속은
    /// UsageStore.disableKeychainAccess(didSet)가 전담한다. UserDefaults.standard 에
    /// 직접 쓰던 이전 구현은 테스트 실행이 실제 사용자 설정을 오염시켰다.
    /// (Bool 단일 플래그 — MainActor 쓰기/actor 읽기의 경합은 무해)
    nonisolated(unsafe) static var isDisabled: Bool =
        UserDefaults.standard.bool(forKey: "disableKeychainAccess")
}

/// 모든 Keychain 조회의 단일 통로.
///
/// `allowKeychainPrompt: false` 는 "프롬프트를 띄우지 않는다"가 아니라 **"Keychain 을 아예
/// 조회하지 않는다"** 는 계약이다 — no-UI 쿼리로도 잠긴·미승인 login 키체인의 암호 다이얼로그는
/// 억제되지 않기 때문이다(`OAuthLimitsProvider` 의 실측: 13초 블록 + 팝업).
///
/// 그 계약을 규약이 아니라 가드로 만들려면 조회 횟수를 셀 수 있어야 한다. 프로바이더가
/// `SecItemCopyMatching` 을 각자 직접 부르면 "자동 경로는 0회" 를 행동으로 검증할 방법이 없고,
/// 실제로 그 틈으로 자동 폴링이 키체인을 읽는 구현이 스위트 초록인 채 들어왔다(#210).
enum KeychainReader {
    nonisolated(unsafe) private(set) static var queryCount = 0

    static func resetQueryCountForTesting() { queryCount = 0 }

    static func copyMatching(_ query: [String: Any], _ result: inout CFTypeRef?) -> OSStatus {
        queryCount += 1
        return SecItemCopyMatching(query as CFDictionary, &result)
    }
}

enum KeychainNoUIQuery {
    private static let uiFailPolicy = resolveUIFailPolicy()

    static func apply(to query: inout [String: Any]) {
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context

        // Some legacy Keychain ACL states can still prompt unless the old UI-fail
        // policy is present. Resolve it dynamically to avoid deprecated API usage.
        query[kSecUseAuthenticationUI as String] = uiFailPolicy as CFString
    }

    static func uiFailPolicyForTesting() -> String {
        uiFailPolicy
    }

    private static func resolveUIFailPolicy() -> String {
        let securityPath = "/System/Library/Frameworks/Security.framework/Security"
        guard let handle = dlopen(securityPath, RTLD_NOW) else {
            return "u_AuthUIF"
        }
        defer { dlclose(handle) }

        guard let symbol = dlsym(handle, "kSecUseAuthenticationUIFail") else {
            return "u_AuthUIF"
        }
        let valuePointer = symbol.assumingMemoryBound(to: CFString?.self)
        return (valuePointer.pointee as String?) ?? "u_AuthUIF"
    }
}
#endif
