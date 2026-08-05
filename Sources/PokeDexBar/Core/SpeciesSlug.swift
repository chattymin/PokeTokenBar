import Foundation

/// 종 번호 → Showdown 스프라이트 슬러그. 업스트림 게임 로직은 숫자 종 ID로 돌고 Showdown 은
/// 이름 슬러그(`bulbasaur`·`hooh`)를 쓰므로 그 사이를 잇는다. 번들 JSON 이라 런타임 네트워크가 없다.
/// 갱신은 `scripts/generate-slugs.py` 재실행.
enum SpeciesSlug {
    private static let table: [Int: String] = loadTable()

    static func slug(_ speciesID: Int) -> String? { table[speciesID] }

    private static func loadTable() -> [Int: String] {
        guard let url = resourceURL(),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else {
            // 여기서 빈 테이블이면 이후 모든 slug(_:) 호출이 조용히 nil 을 돌려줘 "스프라이트가 아예 안
            // 뜬다" 는 증상만 남고 원인이 안 보인다 — 로그로 단서를 남긴다.
            AppLog.write("SpeciesSlug: showdown-slugs.json 을 번들에서 못 읽음 — 번들 조립 확인 필요")
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
    }

    /// 리소스 번들 위치. SwiftPM 이 생성하는 `Bundle.module` 접근자는 배포 `.app` 에서 두 경로만
    /// 본다 — `Bundle.main.bundleURL` 형제(= `.app` 루트, `Contents/` 밖)와 이 기기의 `.build`
    /// 절대경로. 실측: macOS `codesign` 은 `.app` 루트에 `Contents/` 이외 콘텐츠가 있으면 서명 자체를
    /// 거부한다(`unsealed contents present in the bundle root` — 빈 텍스트 파일 하나로도 재현됨).
    /// 즉 `Bundle.module` 이 찾는 자리에 번들을 두면 앱을 서명할 수 없고, 안 두면 `Bundle.module` 이
    /// 두 경로 모두 실패해 `Swift.fatalError` 로 죽는다(`try?`/`guard let` 이전이라 못 잡는다). 그래서
    /// 배포 `.app`(`AppEnv.isBundledApp`)에서는 `Bundle.module` 을 아예 건드리지 않고, 서명 가능한
    /// 표준 위치 `Contents/Resources/` 를 직접 찾는다(`scripts/build-app.sh` 가 그 자리에 복사).
    /// 개발/테스트(swift test·bare 바이너리)는 SwiftPM 표준 `Bundle.module` 을 그대로 쓴다.
    private static func resourceURL() -> URL? {
        guard AppEnv.isBundledApp else {
            return Bundle.module.url(forResource: "showdown-slugs", withExtension: "json")
        }
        let bundlePath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/PokeDexBar_PokeDexBar.bundle")
        return Bundle(path: bundlePath.path)?.url(forResource: "showdown-slugs", withExtension: "json")
    }
}
