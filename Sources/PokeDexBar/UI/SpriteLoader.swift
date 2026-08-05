import AppKit

/// 포켓몬 스프라이트를 런타임에 받아 로컬(Application Support)에 캐시. 레포/번들에 미포함.
actor SpriteStore {
    static let shared = SpriteStore()
    private let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon"
    private let itemBase = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items"
    /// 포켓몬 스프라이트는 Showdown — 전 세대(9세대까지)를 제공한다. 아이템·알은 대응물이 없어
    /// 계속 PokeAPI(`base`)를 쓴다.
    private static let showdownBase = "https://play.pokemonshowdown.com/sprites"
    /// 애니메이션이 없는 변형(종+shiny 조합, 9세대 일부 패러독스·전설이나 shiny 미제공 종)을 기억해
    /// 매번 재요청하지 않는다. 404/410 같은 확정적 "존재하지 않음" 응답에서만 채운다 — 오프라인·타임아웃
    /// 등 일시적 실패로 채우면 네트워크가 돌아온 뒤에도 그 변형이 프로세스 수명 내내 정적 폴백에 갇힌다
    /// (리뷰 지적). `cacheKey` 로 종별이 아니라 **변형별**로 키를 잡는다 — shiny 애니메이션 404 를 종
    /// 단위로 기억하면 그 종의 일반(non-shiny) 애니메이션 요청까지 함께 막혀버린다(리뷰 지적).
    private var missingAnimated: Set<String> = []
    private var mem: [String: Data] = [:]
    private var memOrder: [String] = []   // LRU 순서(최근 접근이 뒤). 상한 초과 시 앞(오래된 것)부터 evict
    private let memLimit = 24              // in-memory 스프라이트 캐시 상한 — 세션 중 종 변경 누적 무한증가 방지(#H1)
    private let dir: URL
    /// 네트워크 호출 지점 — 테스트가 응답 상태 코드·에러를 흉내낼 수 있게 하는 seam. 기본값은 실제
    /// URLSession, 프로덕션에서는 손대지 않는다(`shared` 는 인자 없이 생성).
    private let fetch: (URL) async throws -> (Data, URLResponse)

    init(dir: URL? = nil, fetch: @escaping (URL) async throws -> (Data, URLResponse) = { url in
        try await URLSession.shared.data(from: url)
    }) {
        let resolved = dir ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeDexBar/sprites")
        try? FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
        self.dir = resolved
        self.fetch = fetch
    }

    /// 캐시 파일명 키 — 기존 "\(id)-a"/"\(id)-s" 유지, shiny 는 "sh" 접두(구캐시 그대로 유효).
    static func cacheKey(speciesID: Int, animated: Bool, shiny: Bool) -> String {
        "\(speciesID)-\(shiny ? "sh" : "")\(animated ? "a" : "s")"
    }

    /// 슬러그 기반 스프라이트 URL. 순수 함수라 네트워크 없이 테스트한다.
    static func spriteURL(slug: String, animated: Bool, shiny: Bool) -> URL? {
        let folder = switch (animated, shiny) {
        case (true, false): "ani"
        case (true, true): "ani-shiny"
        case (false, false): "gen5"
        case (false, true): "gen5-shiny"
        }
        return URL(string: "\(showdownBase)/\(folder)/\(slug).\(animated ? "gif" : "png")")
    }

    func data(speciesID: Int, animated: Bool, shiny: Bool = false) async -> Data? {
        let key = Self.cacheKey(speciesID: speciesID, animated: animated, shiny: shiny)
        if let d = mem[key] { touch(key); return d }
        let ext = animated ? "gif" : "png"
        let file = dir.appendingPathComponent("\(key).\(ext)")
        if let d = try? Data(contentsOf: file) { remember(key, d); return d }
        // 이 변형(종+shiny)의 애니메이션이 없다고 이미 확인됐으면 정적으로 떨어지게 nil 을 돌려준다(뷰가
        // 폴백). mem/disk 캐시 조회보다 아래에 둔다 — 위에 두면 이미 디스크에 있는 파일까지 막는다(리뷰 지적).
        if animated, missingAnimated.contains(key) { return nil }
        // 슬러그는 캐시 미스일 때만 필요하다 — 여기(캐시 조회 아래)에 두면 번들 슬러그 테이블 로드 실패가
        // 디스크에 이미 있는 스프라이트까지 막지 않는다(리뷰 지적).
        guard let slug = SpeciesSlug.slug(speciesID),
              let url = Self.spriteURL(slug: slug, animated: animated, shiny: shiny) else { return nil }
        do {
            let (d, resp) = try await fetch(url)
            let status = (resp as? HTTPURLResponse)?.statusCode
            guard status == 200, !d.isEmpty else {
                // 404/410 은 "이 변형엔 애니메이션이 없다"는 확정 신호일 때만 기억한다. 그 외 상태 코드(5xx 등)는
                // 서버 쪽 일시 오류일 수 있어 기억하지 않는다 — 다음 시도에서 다시 확인한다.
                if animated, status == 404 || status == 410 { missingAnimated.insert(key) }
                return nil
            }
            try? d.write(to: file, options: .atomic)   // torn write 방지
            remember(key, d)
            return d
        } catch {
            // 오프라인·DNS 실패·타임아웃·취소 등 일시적 실패 — 기억하면 안 된다. 여기서 기억하면 앱이
            // 오프라인 상태로 뜬 순간 조회한 종이 재연결 후에도 프로세스 수명 내내 정적 폴백에 갇힌다.
            return nil
        }
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

@MainActor
enum SpriteLoader {
    static let cacheDir: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeDexBar/sprites")
    }()

    /// 디스크 캐시에 이미 있으면 동기 반환(네트워크 없음). 없으면 nil.
    /// shiny 캐시 미스는 일반 캐시로 폴백 — 오프라인에서 live mon 이 알 글리프로 보이는 것 방지.
    static func cachedImage(speciesID: Int, animated: Bool = false, shiny: Bool = false) -> NSImage? {
        let ext = animated ? "gif" : "png"
        let key = SpriteStore.cacheKey(speciesID: speciesID, animated: animated, shiny: shiny)
        let f = cacheDir.appendingPathComponent("\(key).\(ext)")
        if let d = try? Data(contentsOf: f), let img = NSImage(data: d) { return img }
        guard shiny else { return nil }
        return cachedImage(speciesID: speciesID, animated: animated, shiny: false)
    }

    /// 정적 스프라이트. animated=true 면 Gen-V 움직이는 스프라이트(없으면 정적으로 폴백).
    /// shiny=true 는 색이 다른 스프라이트 — 미제공 종이면 일반으로 폴백.
    static func image(speciesID: Int, animated: Bool = false, shiny: Bool = false) async -> NSImage? {
        if animated, let d = await SpriteStore.shared.data(speciesID: speciesID, animated: true, shiny: shiny),
           let img = NSImage(data: d) {
            return img
        }
        if let d = await SpriteStore.shared.data(speciesID: speciesID, animated: false, shiny: shiny),
           let img = NSImage(data: d) {
            return img
        }
        // shiny 미제공 → 일반 폴백
        guard shiny else { return nil }
        return await image(speciesID: speciesID, animated: animated, shiny: false)
    }

    /// 아이템 스프라이트 — 디스크 캐시 동기 조회(없으면 nil). 아이콘 즉시 표시용(재렌더 플래시 방지).
    static func cachedItemImage(name: String) -> NSImage? {
        let f = cacheDir.appendingPathComponent("item-\(name).png")
        if let d = try? Data(contentsOf: f), let img = NSImage(data: d) { return img }
        return nil
    }

    /// 아이템 스프라이트 — 런타임 로드(+캐시). 미제공/실패면 nil(뷰가 이모지로 폴백).
    static func itemImage(name: String) async -> NSImage? {
        guard let d = await SpriteStore.shared.data(itemName: name), let img = NSImage(data: d) else { return nil }
        return img
    }

    /// 알 스프라이트는 96×96 캔버스에 실제 알이 28×30(≈29%)만 차지 — 그대로 쓰면 프레임에서 아주 작게
    /// 보인다(🥚 이모지는 여백이 없어 꽉 찼음). 콘텐츠 경계로 1회 크롭해 여백을 제거하고 캐시 →
    /// 상점·홈 등 모든 크기에서 이모지처럼 프레임을 꽉 채운다.
    private static var croppedEgg: NSImage?

    /// 크롭 완료분만 동기 반환(미준비면 nil — 동기 크롭 안 함, 히치 방지). 첫 표시 때만 🥚 폴백 후 eggImage 로 교체.
    static func cachedEggImage() -> NSImage? { croppedEgg }

    /// 알 스프라이트 — 런타임 로드 + 콘텐츠 크롭(최초 1회 메모이즈). 오프라인/실패면 nil(뷰가 🥚 폴백).
    static func eggImage() async -> NSImage? {
        if let c = croppedEgg { return c }
        guard let d = await SpriteStore.shared.eggData(), let img = NSImage(data: d) else { return nil }
        croppedEgg = cropToContent(img)
        return croppedEgg
    }

    /// 비투명(alpha>0) 콘텐츠 경계로 크롭 — 큰 투명 여백 제거. 96×96 1회만 수행(메모이즈).
    private static func cropToContent(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return image }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }
        // 콘텐츠 bbox 를 정사각(긴 변 기준)으로 확장해 중앙 정렬 — 알 콘텐츠는 28×30(세로가 김)이라 그대로
        // 크롭하면 SpriteView 의 size×size 정사각 프레임에서 가로로 늘어나 뚱뚱해진다. 정사각 크롭이면 비율 보존.
        let bw = maxX - minX + 1, bh = maxY - minY + 1
        let side = min(max(bw, bh), min(w, h))
        let sx = max(0, min(minX - (side - bw) / 2, w - side))
        let sy = max(0, min(minY - (side - bh) / 2, h - side))
        guard let cg = rep.cgImage?.cropping(to: CGRect(x: sx, y: sy, width: side, height: side))
        else { return image }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
