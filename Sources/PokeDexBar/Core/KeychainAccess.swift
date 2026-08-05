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
