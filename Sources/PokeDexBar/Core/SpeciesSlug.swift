import Foundation

/// 종 번호 → Showdown 스프라이트 슬러그. 업스트림 게임 로직은 숫자 종 ID로 돌고 Showdown 은
/// 이름 슬러그(`bulbasaur`·`hooh`)를 쓰므로 그 사이를 잇는다. 번들 JSON 이라 런타임 네트워크가 없다.
/// 갱신은 `scripts/generate-slugs.py` 재실행.
enum SpeciesSlug {
    private static let table: [Int: String] = loadTable()

    static func slug(_ speciesID: Int) -> String? { table[speciesID] }

    private static func loadTable() -> [Int: String] {
        guard let url = Bundle.module.url(forResource: "showdown-slugs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
    }
}
