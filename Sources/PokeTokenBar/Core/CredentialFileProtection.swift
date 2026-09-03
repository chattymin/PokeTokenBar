import Foundation

/// 평문 자격증명 파일의 노출면을 줄이는 공통 조치.
///
/// 이 앱은 자격증명을 앱 소유 Keychain 항목이 아니라 Application Support 평문 JSON(0600)에 둔다 —
/// 앱이 만든 Keychain 항목은 코드서명(cdhash)이 바뀔 때마다 접근 허용 프롬프트를 유발하고, 그게
/// `SessionKeyStore` 와 antigravity 자격증명이 애초에 없애려던 바로 그 팝업이기 때문이다(#58).
/// 그 결정은 유지하되, **평문으로 두기 때문에 생기는 경로**는 좁힌다.
///
/// `~/Library/Application Support` 는 TCC 게이트가 없고(Desktop/Documents 와 다르다) Time Machine
/// 기본 백업 대상이다. 그래서 자격증명 파일만 백업에서 빼고, 상태 디렉터리 자체를 0700 으로 좁힌다.
/// 디렉터리 통째로 백업 제외하지는 않는다 — companion 상태·한도 히스토리는 복원돼야 할 사용자 데이터다.
enum CredentialFileProtection {
    /// 백업(Time Machine·`~/Library` 를 통째로 뜨는 도구) 대상에서 제외한다. 파일이 없으면 무시.
    static func excludeFromBackup(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    /// 상태 디렉터리 권한을 0700 으로 좁힌다(기본 생성은 0755라 다른 로컬 사용자가 나열할 수 있다).
    static func restrictDirectory(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))], ofItemAtPath: url.path)
    }
}
