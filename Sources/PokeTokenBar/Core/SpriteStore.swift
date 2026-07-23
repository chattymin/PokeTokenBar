import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession lives here on non-Darwin (Windows/Linux)
#endif

/// 포켓몬 스프라이트를 런타임에 받아 로컬(Application Support)에 캐시. 레포/번들에 미포함.
///
/// 순수 Foundation(URLSession + 파일 캐시) — macOS 메뉴바와 Windows 트레이/팝오버가 공유한다.
/// 이미지 디코딩(NSImage / WIC HICON)은 각 플랫폼 코드가 담당하고, 이 액터는 바이트만 다룬다.
actor SpriteStore {
    static let shared = SpriteStore()
    private let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon"
    private let itemBase = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items"
    private var mem: [String: Data] = [:]
    private var memOrder: [String] = []   // LRU 순서(최근 접근이 뒤). 상한 초과 시 앞(오래된 것)부터 evict
    private let memLimit = 24              // in-memory 스프라이트 캐시 상한 — 세션 중 종 변경 누적 무한증가 방지(#H1)
    private let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar/sprites")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// 캐시 파일명 키 — 기존 "\(id)-a"/"\(id)-s" 유지, shiny 는 "sh" 접두(구캐시 그대로 유효).
    static func cacheKey(speciesID: Int, animated: Bool, shiny: Bool) -> String {
        "\(speciesID)-\(shiny ? "sh" : "")\(animated ? "a" : "s")"
    }

    func data(speciesID: Int, animated: Bool, shiny: Bool = false) async -> Data? {
        let key = Self.cacheKey(speciesID: speciesID, animated: animated, shiny: shiny)
        if let d = mem[key] { touch(key); return d }
        let ext = animated ? "gif" : "png"
        let file = dir.appendingPathComponent("\(key).\(ext)")
        if let d = try? Data(contentsOf: file) { remember(key, d); return d }
        let urlStr: String
        switch (animated, shiny) {
        case (true, false):  urlStr = "\(base)/versions/generation-v/black-white/animated/\(speciesID).gif"
        case (true, true):   urlStr = "\(base)/versions/generation-v/black-white/animated/shiny/\(speciesID).gif"
        case (false, false): urlStr = "\(base)/\(speciesID).png"
        case (false, true):  urlStr = "\(base)/shiny/\(speciesID).png"
        }
        guard let url = URL(string: urlStr),
              let (d, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty else { return nil }
        try? d.write(to: file, options: .atomic)   // torn write 방지 — 크래시/강제종료 시 손상 캐시가 남지 않게
        remember(key, d)
        return d
    }

    /// 아이템 스프라이트(정적 PNG, 이름 기반). 포켓몬과 같은 메모리/디스크 캐시 사용(키 "item-<name>",
    /// 포켓몬 파일 "<id>-..." 과 안 겹침). 미제공(404)/오프라인이면 nil → 뷰가 이모지로 폴백.
    func data(itemName: String) async -> Data? {
        let key = "item-\(itemName)"
        if let d = mem[key] { touch(key); return d }
        let file = dir.appendingPathComponent("\(key).png")
        if let d = try? Data(contentsOf: file) { remember(key, d); return d }
        guard let url = URL(string: "\(itemBase)/\(itemName).png"),
              let (d, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty else { return nil }
        try? d.write(to: file, options: .atomic)
        remember(key, d)
        return d
    }

    /// 알 스프라이트(정적, pokemon/egg.png) — 애니메이션 알은 없음. 포켓몬/아이템과 같은 메모리·디스크 캐시(키 "egg").
    func eggData() async -> Data? {
        let key = "egg"
        if let d = mem[key] { touch(key); return d }
        let file = dir.appendingPathComponent("egg.png")
        if let d = try? Data(contentsOf: file) { remember(key, d); return d }
        guard let url = URL(string: "\(base)/egg.png"),
              let (d, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty else { return nil }
        try? d.write(to: file, options: .atomic)
        remember(key, d)
        return d
    }

    /// in-memory 캐시에 넣고 LRU 상한 유지(#H1) — 세션 중 종이 여러 번 바뀌어도 무한 성장 방지.
    private func remember(_ key: String, _ data: Data) {
        mem[key] = data
        touch(key)
        while memOrder.count > memLimit {
            let old = memOrder.removeFirst()
            mem.removeValue(forKey: old)
        }
    }
    /// 접근/삽입 키를 최근(뒤)으로 이동 — 활성 종이 evict 되지 않게 하는 LRU.
    private func touch(_ key: String) {
        if let i = memOrder.firstIndex(of: key) { memOrder.remove(at: i) }
        memOrder.append(key)
    }
}
