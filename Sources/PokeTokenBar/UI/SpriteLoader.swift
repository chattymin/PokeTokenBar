#if os(macOS)
import AppKit

@MainActor
enum SpriteLoader {
    static let cacheDir: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar/sprites")
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
        // The geometry lives in `SpriteCrop` so the Linux tray computes the identical rectangle.
        guard let rect = SpriteCrop.squareContentRect(
            width: rep.pixelsWide, height: rep.pixelsHigh,
            isOpaque: { x, y in
                (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > SpriteCrop.opaqueAlphaThreshold
            })
        else { return image }
        guard let cg = rep.cgImage?.cropping(
            to: CGRect(x: rect.x, y: rect.y, width: rect.side, height: rect.side))
        else { return image }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
#endif   // os(macOS)
