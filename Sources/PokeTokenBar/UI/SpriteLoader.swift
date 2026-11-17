import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 포켓몬 스프라이트를 런타임에 받아 로컬(Application Support)에 캐시. 레포/번들에 미포함.
actor SpriteStore {
    static let shared = SpriteStore()
    private static let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon"
    private let itemBase = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items"
    private var mem: [String: Data] = [:]
    private var memOrder: [String] = []   // LRU 순서(최근 접근이 뒤). 상한 초과 시 앞(오래된 것)부터 evict
    /// Keys the server answered it has no sprite for (404), so they are not requested again this session.
    /// A request that failed (offline, rate limited, server error) is not recorded: it must be retried later.
    private var failedKeys: Set<String> = []
    // Raw PNG/GIF LRU cap: the Pokédex page (24 cells), the Achievements list (31 items plus the Pokémon
    // they ask for) and the bag must not thrash each other. SpriteLoader keeps its own NSImage cache.
    private let memLimit = 256
    nonisolated let directory: URL

    init(directory: URL? = nil) {
        let d = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar/sprites")
        self.directory = d
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        Self.purgeMisattributedFormSprites(in: d)
        Self.purgeRemappedSprites(in: d)
        // Only the app's own cache holds sprites downloaded by earlier versions.
        if directory == nil {
            Self.purgePixelAnimations(in: d)
            Self.purgePixelStills(in: d)
        }
    }

    /// Gen 1-5 animations used to be Black and White's pixel GIFs; they are now Showdown's 3D renders, like Gen 6-9.
    /// Deletes the app cache's Gen 1-5 GIFs once so they download again from Showdown. Static PNGs stay. A marker
    /// file records that the purge ran. Runs from `SpriteStore.shared` and from `SpriteLoader.cacheDir`, whichever
    /// reads the cache first (the menu bar reads it synchronously at launch).
    nonisolated static func purgePixelAnimations(in directory: URL) {
        let fm = FileManager.default
        let marker = directory.appendingPathComponent(".showdown-animations-v1")
        guard !fm.fileExists(atPath: marker.path) else { return }
        for name in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? [] where name.hasSuffix("a.gif") {
            // "<id>[-<form>]-[sh]a.gif": the species id leads.
            guard let id = Int(name.prefix { $0.isNumber }), (1...649).contains(id) else { continue }
            try? fm.removeItem(at: directory.appendingPathComponent(name))
        }
        fm.createFile(atPath: marker.path, contents: nil)
    }

    /// Species whose form sprites were cached from another Pokémon's file: their catalogue entries took the form
    /// id as a variety id, so Icy Snow Vivillon loaded Hoopa Unbound's 10086 and Yellow Flabébé Alolan Vulpix's
    /// 10103. Those 40 forms have no variety of their own.
    nonisolated static let misattributedFormSpecies = [666, 669, 670, 671, 676]

    /// Deletes the cached files of those forms once, so they download again from the right file. A marker
    /// file records that the purge ran; a sprite cached afterwards stays.
    nonisolated static func purgeMisattributedFormSprites(in directory: URL) {
        let fm = FileManager.default
        let marker = directory.appendingPathComponent(".form-sprites-v1")
        guard !fm.fileExists(atPath: marker.path) else { return }
        let prefixes = misattributedFormSpecies.flatMap { id in
            PokemonForm.forms(speciesID: id).dropFirst().map { "\(PokemonForm.assetName(speciesID: id, form: $0))-" }
        }
        for name in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        where prefixes.contains(where: name.hasPrefix) {
            try? fm.removeItem(at: directory.appendingPathComponent(name))
        }
        fm.createFile(atPath: marker.path, contents: nil)
    }

    /// Showdown's file for an asset, where its name differs: Maushold's are the other way round from PokéAPI's,
    /// whose default is the Family of Four (Showdown's `925-four`) while Showdown's plain `925` is the Family of Three.
    nonisolated static let showdownNames: [String: String] = ["925": "925-four", "10257": "925"]

    /// Species whose cached sprites came from the other Showdown file: Maushold's default cached the Family of Three.
    nonisolated static let remappedSpriteSpecies = [925]

    /// Deletes those species' cached files once, so they download again from the right file. A marker file records
    /// that the purge ran.
    nonisolated static func purgeRemappedSprites(in directory: URL) {
        let fm = FileManager.default
        let marker = directory.appendingPathComponent(".form-sprites-v2")
        guard !fm.fileExists(atPath: marker.path) else { return }
        let prefixes = remappedSpriteSpecies.map { "\($0)-" }
        for name in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        where prefixes.contains(where: name.hasPrefix) {
            try? fm.removeItem(at: directory.appendingPathComponent(name))
        }
        fm.createFile(atPath: marker.path, contents: nil)
    }

    /// 기본 폼은 구캐시 키 그대로 유지. 다른 폼은 폼·이로치·애니메이션을 모두 구분한다.
    static func cacheKey(speciesID: Int, animated: Bool, shiny: Bool, form: PokemonForm? = nil) -> String {
        "\(PokemonForm.assetName(speciesID: speciesID, form: form))-\(shiny ? "sh" : "")\(animated ? "a" : "s")"
    }

    /// Stills used to be PokeAPI's pixel PNGs while the animations were 3D: a Pokémon changed style when it started
    /// moving. They are now the animation's first frame (`stillData`). Deletes the app cache's species stills once
    /// (`<id>[-<form>]-[sh]s.png`) so they are made again; items and the egg stay. Runs where the GIF purge runs.
    nonisolated static func purgePixelStills(in directory: URL) {
        let fm = FileManager.default
        let marker = directory.appendingPathComponent(".showdown-stills-v1")
        guard !fm.fileExists(atPath: marker.path) else { return }
        for name in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        where name.hasSuffix("s.png") && name.first?.isNumber == true {
            try? fm.removeItem(at: directory.appendingPathComponent(name))
        }
        fm.createFile(atPath: marker.path, contents: nil)
    }

    /// A Pokémon's still: the first frame of its animation, as a PNG, so it looks the same moving or not.
    nonisolated static func firstFrame(of gif: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(gif as CFData, nil),
              let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, frame, nil)
        return CGImageDestinationFinalize(destination) ? png as Data : nil
    }

    /// Animated GIFs are Showdown's 3D renders (`other/showdown/`) for every generation. Static PNGs of separate
    /// varieties use the variety id (`10006.png`). Cache files keep the `<id>-<form>` name either way.
    static func spriteURL(speciesID: Int, animated: Bool, shiny: Bool, form: PokemonForm? = nil) -> URL {
        spriteURLs(speciesID: speciesID, animated: animated, shiny: shiny, form: form)[0]
    }

    /// Every place the sprite may be, most likely first. Showdown has every species, under the variety id for a
    /// separate variety and without hyphens for some forms (`666-highplains`, `676-lareine`); Black and White's
    /// pixel GIFs stay last, for a Gen 1-5 form Showdown lacks (Burmy's cloaks). Its folder has no form added after
    /// Gen 5 (the white-striped Basculin is its variety `10247`).
    static func spriteURLs(speciesID: Int, animated: Bool, shiny: Bool, form: PokemonForm? = nil) -> [URL] {
        // Giovanni's armored Mewtwo: Pokémon GO's render, still, whatever is asked (issue #180).
        if ArmoredMewtwo.matches(speciesID: speciesID, form: form), let url = URL(string: ArmoredMewtwo.spriteURL) { return [url] }
        // A costumed Pokémon: Pokémon GO's render (PokeMiners), its shiny's for a shiny, still (`CostumeCatalog`).
        if let url = CostumeCatalog.spriteURL(speciesID: speciesID, display: form, shiny: shiny) { return [url] }
        let color = shiny ? "shiny/" : ""
        let isRegional = form?.rawValue.contains("alola") == true
                      || form?.rawValue.contains("galar") == true
                      || form?.rawValue.contains("hisui") == true
                      || form?.rawValue.contains("paldea") == true
        let name = PokemonForm.staticAssetName(speciesID: speciesID, form: form)
        guard animated else {
            return [URL(string: "\(base)/\(color)\(PokemonForm.pngName(speciesID: speciesID, form: form)).png")!]
        }
        var names = ["other/showdown/\(color)\(showdownNames[name] ?? name)"]
        let asset = PokemonForm.assetName(speciesID: speciesID, form: form)
        if asset == name, let form, asset != String(speciesID) {
            names.append("other/showdown/\(color)\(speciesID)-\(form.rawValue.replacingOccurrences(of: "-", with: ""))")
        }
        if speciesID <= 649, !isRegional {
            names.append("versions/generation-v/black-white/animated/\(color)\(asset)")
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }.map { URL(string: "\(base)/\($0).gif")! }
    }

    /// One still to make ahead of time.
    struct StillRequest: Hashable, Sendable {
        let speciesID: Int
        let shiny: Bool
    }

    /// Makes these Pokémon's stills ahead, `concurrency` at a time, so a Pokédex page shows at once. Stills already on
    /// disk are skipped and nothing is decoded: they only reach the cache. Stops when the task is cancelled.
    func warmStills(_ requests: [StillRequest], concurrency: Int = 4) async {
        var pending = requests.filter { request in
            let key = Self.cacheKey(speciesID: request.speciesID, animated: false, shiny: request.shiny)
            return !FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(key).png").path)
        }.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            func start() -> Bool {
                guard !Task.isCancelled, let request = pending.next() else { return false }
                group.addTask { _ = await self.data(speciesID: request.speciesID, animated: false, shiny: request.shiny) }
                return true
            }
            for _ in 0..<max(1, concurrency) {
                guard start() else { break }
            }
            while await group.next() != nil { _ = start() }
        }
    }

    func data(speciesID: Int, animated: Bool, shiny: Bool = false, form: PokemonForm? = nil) async -> Data? {
        if animated, !PokemonAssets.hasAnimatedSprite(speciesID: speciesID) { return nil }
        let key = Self.cacheKey(speciesID: speciesID, animated: animated, shiny: shiny, form: form)
        if let d = mem[key] { touch(key); return d }
        let ext = animated ? "gif" : "png"
        let file = directory.appendingPathComponent("\(key).\(ext)")
        if let d = try? Data(contentsOf: file) { remember(key, d); return d }
        if failedKeys.contains(key) { return nil }
        // A still is the animation's first frame (the GIF is cached for the animation too); PokeAPI's pixel PNG
        // only when there is no animation.
        if !animated, let gif = await data(speciesID: speciesID, animated: true, shiny: shiny, form: form),
           let still = Self.firstFrame(of: gif) {
            try? still.write(to: file, options: .atomic)
            remember(key, still)
            return still
        }
        var found: Data?
        var missing = true
        for url in Self.spriteURLs(speciesID: speciesID, animated: animated, shiny: shiny, form: form) {
            guard let (d, resp) = try? await URLSession.shared.data(from: url) else { return nil }
            let status = (resp as? HTTPURLResponse)?.statusCode
            if status == 200, !d.isEmpty { found = d; break }
            if status != 404 { missing = false }
        }
        guard let d = found else {
            if missing { failedKeys.insert(key) }
            return nil
        }
        try? d.write(to: file, options: .atomic)   // torn write 방지 — 크래시/강제종료 시 손상 캐시가 남지 않게
        remember(key, d)
        return d
    }

    // MARK: Backs (2026-11-09)

    /// The back of a Pokémon, for the player's side of a battle (the owner, 2026-11-09): Showdown's back render
    /// (`other/showdown/back/`), its first frame as the arena's fronts are. Every Pokémon with a front render has
    /// one but eight forms (Libre Pikachu, seven Gigantamax); those keep their front.
    static func backKey(speciesID: Int, shiny: Bool, form: PokemonForm? = nil) -> String {
        "\(PokemonForm.assetName(speciesID: speciesID, form: form))-\(shiny ? "sh" : "")b"
    }

    /// Where the back may be: Showdown's names of the front, in its `back/` folder (Black and White's pixel GIFs
    /// have no back here).
    static func backSpriteURLs(speciesID: Int, shiny: Bool, form: PokemonForm? = nil) -> [URL] {
        spriteURLs(speciesID: speciesID, animated: true, shiny: shiny, form: form)
            .map(\.absoluteString)
            .filter { $0.contains("/other/showdown/") }
            .compactMap { URL(string: $0.replacingOccurrences(of: "/other/showdown/", with: "/other/showdown/back/")) }
    }

    /// The back's still (`<asset>-[sh]b.png`), downloaded once; nil when Showdown has none, or offline.
    func backStill(speciesID: Int, shiny: Bool, form: PokemonForm? = nil) async -> Data? {
        guard PokemonAssets.hasAnimatedSprite(speciesID: speciesID) else { return nil }
        let key = Self.backKey(speciesID: speciesID, shiny: shiny, form: form)
        if let d = mem[key] { touch(key); return d }
        let file = directory.appendingPathComponent("\(key).png")
        if let d = try? Data(contentsOf: file) { remember(key, d); return d }
        if failedKeys.contains(key) { return nil }
        var missing = true
        for url in Self.backSpriteURLs(speciesID: speciesID, shiny: shiny, form: form) {
            guard let (d, resp) = try? await URLSession.shared.data(from: url) else { return nil }
            let status = (resp as? HTTPURLResponse)?.statusCode
            if status == 200, !d.isEmpty, let still = Self.firstFrame(of: d) {
                try? still.write(to: file, options: .atomic)
                remember(key, still)
                return still
            }
            if status != 404 { missing = false }
        }
        if missing { failedKeys.insert(key) }
        return nil
    }

    /// The server has no such sprite (it answered 404): not a request that failed and will be retried.
    func isMissing(speciesID: Int, animated: Bool, shiny: Bool, form: PokemonForm? = nil) -> Bool {
        failedKeys.contains(Self.cacheKey(speciesID: speciesID, animated: animated, shiny: shiny, form: form))
    }

    /// Prof. Oak's Pokémon Masters render, hosted by WikiDex: Showdown draws trainers in pixels only.
    nonisolated static let oakPortrait = "oak-masters"

    /// 아이템 스프라이트(정적 PNG, 이름 기반). 포켓몬과 같은 메모리/디스크 캐시 사용(키 "item-<name>",
    /// 포켓몬 파일 "<id>-..." 과 안 겹침). 미제공(404)/오프라인이면 nil → 뷰가 이모지로 폴백.
    func data(itemName: String) async -> Data? {
        let key = "item-\(itemName)"
        if let d = mem[key] { touch(key); return d }
        let file = directory.appendingPathComponent("\(key).png")
        if let d = try? Data(contentsOf: file) { remember(key, d); return d }
        if failedKeys.contains(key) { return nil }
        let urlStr: String
        if itemName.hasPrefix("badge-") {
            let badgeNum = itemName.dropFirst(6)
            urlStr = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/badges/\(badgeNum).png"
        } else if itemName == Self.oakPortrait {
            urlStr = "https://images.wikidexcdn.net/mwuploads/wikidex/b/b3/latest/20200210170142/Profesor_Oak_Masters.png"
        } else if let merchant = TravellingMerchant.portraitURLs[itemName] {
            urlStr = merchant
        } else if let villain = VillainTeam.portraitURLs[itemName] {
            urlStr = villain
        } else if itemName.hasPrefix("merchant-") {
            return nil
        } else {
            urlStr = "\(itemBase)/\(itemName).png"
        }
        guard let url = URL(string: urlStr),
              let (d, resp) = try? await URLSession.shared.data(from: url) else { return nil }
        guard (resp as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty else {
            if (resp as? HTTPURLResponse)?.statusCode == 404 { failedKeys.insert(key) }
            return nil
        }
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
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar/sprites")
        SpriteStore.purgePixelAnimations(in: directory)
        SpriteStore.purgePixelStills(in: directory)
        return directory
    }()

    /// 동기 시드와 async 로드가 NSImage 를 공유해 파일 읽기와 이미지 객체 생성을 반복하지 않는다.
    /// 키는 디렉터리를 포함한 파일 경로다. Sized to the whole Pokédex grid, by its pixels: 64 images, fewer than the
    /// grid's cells, sent each page turned back to the disk, on the main thread.
    static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 1_200
        cache.totalCostLimit = 64 << 20
        return cache
    }()

    /// What an image holds in memory once drawn, for the caches' cost.
    static func pixelBytes(_ image: NSImage) -> Int {
        let rep = image.representations.first
        let width = rep.map { $0.pixelsWide > 0 ? $0.pixelsWide : Int($0.size.width) } ?? Int(image.size.width)
        let height = rep.map { $0.pixelsHigh > 0 ? $0.pixelsHigh : Int($0.size.height) } ?? Int(image.size.height)
        return max(1, width * height * 4)
    }

    /// Kept beside the cache while a test checks that images are reused: NSCache may let entries go at any moment, as
    /// it did late in the full suite (2026-11-03), which says nothing of the reuse under test. Nil in the app.
    static var retainedForTesting: [NSString: NSImage]?

    static func remember(_ image: NSImage, forKey key: NSString) {
        imageCache.setObject(image, forKey: key, cost: pixelBytes(image))
        retainedForTesting?[key] = image
    }

    /// The image kept under `key`, if any.
    static func remembered(_ key: NSString) -> NSImage? {
        imageCache.object(forKey: key) ?? retainedForTesting?[key]
    }

    /// 메모리·디스크 캐시에 이미 있으면 동기 반환(네트워크 없음). 없으면 nil.
    /// shiny 캐시 미스는 일반 캐시로 폴백 — 오프라인에서 live mon 이 알 글리프로 보이는 것 방지.
    static func cachedImage(speciesID: Int, animated: Bool = false, shiny: Bool = false,
                            directory: URL = cacheDir, form: PokemonForm? = nil) -> NSImage? {
        let ext = animated ? "gif" : "png"
        let key = SpriteStore.cacheKey(speciesID: speciesID, animated: animated, shiny: shiny, form: form)
        let f = directory.appendingPathComponent("\(key).\(ext)")
        let imageKey = f.path as NSString
        if let img = remembered(imageKey) { return img }
        if let d = try? Data(contentsOf: f), let raw = NSImage(data: d) {
            let img = still(raw, speciesID: speciesID, form: form)
            remember(img, forKey: imageKey)
            return img
        }
        guard shiny else { return nil }
        // 폴백은 일반색 키에만 저장한다 — 나중에 받은 이로치 이미지를 가리지 않게.
        return cachedImage(speciesID: speciesID, animated: animated, shiny: false,
                           directory: directory, form: form)
    }

    private final class AnimationFrames {
        let frames: [(image: NSImage, delay: TimeInterval)]
        init(_ frames: [(image: NSImage, delay: TimeInterval)]) { self.frames = frames }
    }
    // Decoded animations are larger than PNGs; keep recent detail visits without retaining the dex. Bounded by their
    // pixels too: sixteen long GIFs were not sixteen short ones.
    private static let animationCache: NSCache<NSString, AnimationFrames> = {
        let cache = NSCache<NSString, AnimationFrames>()
        cache.countLimit = 16
        cache.totalCostLimit = 96 << 20
        return cache
    }()

    /// First render and playback share the exact GIF pixels, including its canvas and delays.
    static func cachedFrames(speciesID: Int, shiny: Bool, directory: URL = cacheDir, form: PokemonForm? = nil)
        -> [(image: NSImage, delay: TimeInterval)] {
        let key = SpriteStore.cacheKey(speciesID: speciesID, animated: true, shiny: shiny, form: form)
        let file = directory.appendingPathComponent("\(key).gif")
        if let cached = animationCache.object(forKey: file.path as NSString) { return cached.frames }
        guard let data = try? Data(contentsOf: file) else { return [] }
        return rememberFrames(data, file: file)
    }

    private static func rememberFrames(_ data: Data, file: URL) -> [(image: NSImage, delay: TimeInterval)] {
        let frames = GIFDecoder.frames(from: data)
        if !frames.isEmpty {
            animationCache.setObject(AnimationFrames(frames), forKey: file.path as NSString,
                                     cost: frames.reduce(0) { $0 + pixelBytes($1.image) })
        }
        return frames
    }

    static func animationFrames(speciesID: Int, shiny: Bool, store: SpriteStore = .shared,
                                form: PokemonForm? = nil) async
        -> [(image: NSImage, delay: TimeInterval)] {
        // A battle form Showdown has no GIF for (the Megas of Legends Z-A) stays on its still, asked for nothing.
        if BattleForms.form(speciesID: speciesID, form: form)?.isAnimated == false { return [] }
        for variant in shiny ? [true, false] : [false] {
            guard !Task.isCancelled else { return [] }
            let cached = cachedFrames(speciesID: speciesID, shiny: variant,
                                      directory: store.directory, form: form)
            if !cached.isEmpty { return cached }
            guard let data = await store.data(speciesID: speciesID, animated: true,
                                             shiny: variant, form: form) else {
                // A shiny falls back to its normal colors only when the server has no shiny file. After a failed
                // request it waits for the retry: settling on the normal animation kept a shiny in normal colors.
                if variant, !(await store.isMissing(speciesID: speciesID, animated: true, shiny: true, form: form)) {
                    return []
                }
                continue
            }
            let key = SpriteStore.cacheKey(speciesID: speciesID, animated: true,
                                            shiny: variant, form: form)
            let frames = rememberFrames(data, file: store.directory.appendingPathComponent("\(key).gif"))
            if !frames.isEmpty { return frames }
        }
        return []
    }

    /// Keep the caller's static fallback visible while a transient GIF failure recovers.
    /// The caller owns this await: cancelling its view/load task also cancels requests and backoff.
    static func recoveringAnimationFrames(
        speciesID: Int, shiny: Bool, store: SpriteStore = .shared, form: PokemonForm? = nil,
        waitBeforeRetry: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onUnavailable: () async -> Void
    ) async -> [(image: NSImage, delay: TimeInterval)] {
        guard !Task.isCancelled else { return [] }
        // Unsupported species have no GIF endpoint, nor the battle forms Showdown lacks; a static fallback is their
        // final state.
        guard PokemonAssets.hasAnimatedSprite(speciesID: speciesID),
              BattleForms.form(speciesID: speciesID, form: form)?.isAnimated != false,
              CostumeCatalog.parse(form) == nil else {
            await onUnavailable()
            return []
        }
        var retryDelay = Duration.seconds(2)
        var showedFallback = false
        while !Task.isCancelled {
            let frames = await animationFrames(speciesID: speciesID, shiny: shiny, store: store,
                                               form: form)
            guard !Task.isCancelled else { return [] }
            if frames.count > 1 { return frames }
            if !showedFallback {
                await onUnavailable()
                showedFallback = true
            }
            guard !Task.isCancelled else { return [] }
            do { try await waitBeforeRetry(retryDelay) } catch { return [] }
            // No attempt limit: cap request frequency during a long outage while keeping recovery
            // within 30 seconds of the next successful request (plus download time).
            retryDelay = min(retryDelay * 2, .seconds(30))
        }
        return []
    }

    /// The static PNG has a 96px padded canvas; animated GIFs are tightly framed.
    /// Normalize only the animated view's placeholder, leaving static dex thumbnails unchanged.
    private static let placeholderCache: NSCache<NSImage, NSImage> = {
        let cache = NSCache<NSImage, NSImage>()
        cache.countLimit = 64
        return cache
    }()
    static func animationPlaceholder(_ image: NSImage) -> NSImage {
        if let cached = placeholderCache.object(forKey: image) { return cached }
        let cropped = cropToContent(image)
        placeholderCache.setObject(cropped, forKey: image)
        return cropped
    }

    /// 정적 스프라이트. animated=true 면 Gen-V 움직이는 스프라이트(없으면 정적으로 폴백).
    /// shiny=true 는 색이 다른 스프라이트 — 미제공 종이면 일반으로 폴백.
    static func image(speciesID: Int, animated: Bool = false, shiny: Bool = false,
                      store: SpriteStore = .shared, form: PokemonForm? = nil) async -> NSImage? {
        for moving in animated ? [true, false] : [false] {
            let key = SpriteStore.cacheKey(speciesID: speciesID, animated: moving, shiny: shiny, form: form)
            let ext = moving ? "gif" : "png"
            let imageKey = store.directory.appendingPathComponent("\(key).\(ext)").path as NSString
            if let img = remembered(imageKey) { return img }
            guard let d = await store.data(speciesID: speciesID, animated: moving,
                                          shiny: shiny, form: form) else { continue }
            // await 중 같은 종의 다른 행이 로드를 끝냈으면 그 객체를 재사용한다.
            if let img = remembered(imageKey) { return img }
            guard let raw = NSImage(data: d) else { continue }
            let img = still(raw, speciesID: speciesID, form: form)
            remember(img, forKey: imageKey)
            return img
        }
        // shiny 미제공 → 일반 폴백
        guard shiny else { return nil }
        return await image(speciesID: speciesID, animated: animated, shiny: false, store: store, form: form)
    }

    /// A Pokémon's back already cached (`SpriteStore.backStill`), at once; nil otherwise.
    static func cachedBackImage(speciesID: Int, shiny: Bool, directory: URL = cacheDir,
                                form: PokemonForm? = nil) -> NSImage? {
        let f = directory.appendingPathComponent("\(SpriteStore.backKey(speciesID: speciesID, shiny: shiny, form: form)).png")
        let imageKey = f.path as NSString
        if let img = remembered(imageKey) { return img }
        guard let d = try? Data(contentsOf: f), let img = NSImage(data: d) else { return nil }
        remember(img, forKey: imageKey)
        return img
    }

    /// A Pokémon's back, downloaded if need be; nil when it has none (its front stays) or offline.
    static func backImage(speciesID: Int, shiny: Bool, store: SpriteStore = .shared,
                          form: PokemonForm? = nil) async -> NSImage? {
        if let img = cachedBackImage(speciesID: speciesID, shiny: shiny, directory: store.directory, form: form) {
            return img
        }
        guard let d = await store.backStill(speciesID: speciesID, shiny: shiny, form: form),
              let img = NSImage(data: d) else { return nil }
        let key = store.directory.appendingPathComponent(
            "\(SpriteStore.backKey(speciesID: speciesID, shiny: shiny, form: form)).png").path as NSString
        remember(img, forKey: key)
        return img
    }

    /// 아이템 스프라이트 — 메모리·디스크 캐시 동기 조회(없으면 nil). 아이콘 즉시 표시용.
    static func cachedItemImage(name: String, directory: URL = cacheDir) -> NSImage? {
        let f = directory.appendingPathComponent("item-\(name).png")
        let imageKey = f.path as NSString
        if let img = remembered(imageKey) { return img }
        if let d = try? Data(contentsOf: f), let img = NSImage(data: d) {
            remember(img, forKey: imageKey)
            return img
        }
        return nil
    }

    /// 아이템 스프라이트 — 런타임 로드(+캐시). 미제공/실패면 nil(뷰가 이모지로 폴백).
    static func itemImage(name: String, store: SpriteStore = .shared) async -> NSImage? {
        let imageKey = store.directory.appendingPathComponent("item-\(name).png").path as NSString
        if let img = remembered(imageKey) { return img }
        guard let d = await store.data(itemName: name) else { return nil }
        if let img = remembered(imageKey) { return img }
        guard let img = NSImage(data: d) else { return nil }
        remember(img, forKey: imageKey)
        return img
    }

    /// A costume's still (and the armored Mewtwo's), Pokémon GO's 256 px render, cropped to the Pokémon with a PokéAPI still's margin: GO draws
    /// each at its size on the canvas, and an Eevee took a fifth of its cell (the owner, 2026-11-16). Any other still
    /// as it is.
    static func still(_ image: NSImage, speciesID: Int = 0, form: PokemonForm?) -> NSImage {
        // Giovanni's armored Mewtwo is a Pokémon GO render too (issue #180).
        CostumeCatalog.parse(form) == nil && !ArmoredMewtwo.matches(speciesID: speciesID, form: form)
            ? image : cropToContent(image, margin: 0.12)
    }

    /// 비투명(alpha>0) 콘텐츠 경계로 크롭: 큰 투명 여백 제거. 1회만 수행(메모이즈). The alpha is read from one bitmap
    /// buffer: `colorAt` made an NSColor per pixel, on the main thread, for every placeholder.
    /// `margin`: the share of the content's long side kept clear on each side.
    static func cropToContent(_ image: NSImage, margin: Double = 0) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.width > 0, cg.height > 0
        else { return image }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return image }
        // Rows run from the image's top, as CGImage cropping counts them. Alpha over 0.01, as before.
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w * 4
            for x in 0..<w where pixels[row + x * 4 + 3] > 2 {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }
        // 콘텐츠 bbox 를 정사각(긴 변 기준)으로 확장해 중앙 정렬 — 알 콘텐츠는 28×30(세로가 김)이라 그대로
        // 크롭하면 SpriteView 의 size×size 정사각 프레임에서 가로로 늘어나 뚱뚱해진다. 정사각 크롭이면 비율 보존.
        let bw = maxX - minX + 1, bh = maxY - minY + 1
        let side = min(Int((Double(max(bw, bh)) * (1 + 2 * margin)).rounded()), min(w, h))
        let sx = max(0, min(minX - (side - bw) / 2, w - side))
        let sy = max(0, min(minY - (side - bh) / 2, h - side))
        guard let cropped = cg.cropping(to: CGRect(x: sx, y: sy, width: side, height: side)) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }
}

/// 스프라이트를 정사각 프레임에 넣을 때의 **비율 유지** 기하 — 팝오버(SpriteView)와 메뉴바가 공유한다.
///
/// Gen-V 움직이는 스프라이트(GIF)는 캔버스가 종마다 다르고 정사각이 아니다 — 잭키(#325) 36×66,
/// 피카츄(#25) 50×46, 팬텀(#143) 74×75. 반면 정적 스프라이트는 96×96, 아이템은 30×30 으로 전부
/// 정사각이라 "size×size 로 늘려 채우기"가 정적 경로에서는 아무 증상이 없다가 GIF 경로에서만
/// 왜곡으로 드러났다(잭키 = 가로 1.83배). 두 호출부가 같은 식을 쓰게 여기로 모은다.
enum SpriteFit {
    /// `box`×`box` 정사각 안에 원본 비율을 유지해 맞춘 크기(contentMode .fit — 긴 변이 box 에 닿는다).
    /// 원본 크기가 비었으면(디코드 실패 등) 정사각 폴백 — 0 나눗셈 방지.
    static func size(for pixelSize: CGSize, box: CGFloat) -> CGSize {
        size(for: pixelSize, width: box, height: box)
    }

    /// Pixels of a Showdown render that fill a box when Pokémon are drawn at one scale (`sameScaleSize`). Showdown
    /// renders every Pokémon at one scale (Charmander 48×57, Charizard 133×140), so one points-per-pixel keeps their
    /// sizes: Charizard and Venusaur fill the box, Charmander takes under half of it.
    static let sameScaleReference: CGFloat = 120

    /// `size(for:box:)` for Pokémon shown side by side: drawn at `box / sameScaleReference` points per pixel, and
    /// fitted down only when larger than the box. Fitting each one instead made a Charmander as big as a Charizard.
    static func sameScaleSize(for pixelSize: CGSize, box: CGFloat) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return size(for: pixelSize, box: box) }
        let scale = min(box / sameScaleReference, box / pixelSize.width, box / pixelSize.height)
        return CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }

    /// The share of an image's height below its lowest visible pixel: 0 when the Pokémon touches the bottom, or when
    /// the image cannot be read. Sprites sit on transparent canvases whose margin under the Pokémon varies from one to
    /// the next, so a view that stands them on the bottom of their box moves each down by its own margin.
    @MainActor static func bottomMargin(of image: NSImage) -> CGFloat {
        if let known = bottomMargins.object(forKey: image) { return CGFloat(known.doubleValue) }
        let margin = measureBottomMargin(image)
        bottomMargins.setObject(NSNumber(value: Double(margin)), forKey: image)
        return margin
    }

    /// Bounded: keyed by image, it kept every decoded GIF frame met alive.
    @MainActor private static let bottomMargins: NSCache<NSImage, NSNumber> = {
        let cache = NSCache<NSImage, NSNumber>()
        cache.countLimit = 512
        return cache
    }()

    private static func measureBottomMargin(_ image: NSImage) -> CGFloat {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.width > 0, cg.height > 0
        else { return 0 }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        // The buffer's first row is the image's top: scan up from the last one. A faint edge pixel is not the ground.
        for row in stride(from: height - 1, through: 0, by: -1) {
            let start = row * width * 4
            for column in 0..<width where pixels[start + column * 4 + 3] > 24 {
                return CGFloat(height - 1 - row) / CGFloat(height)
            }
        }
        return 0
    }

    /// Same fit inside a `width`×`height` box. An empty source falls back to a square on the shorter side.
    static func size(for pixelSize: CGSize, width: CGFloat, height: CGFloat) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            let side = min(width, height)
            return CGSize(width: side, height: side)
        }
        let scale = min(width / pixelSize.width, height / pixelSize.height)
        return CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }
}
