import SwiftUI

/// 리본 배지 그림. 단계마다 다른 이미지를 쓴다 — 1 인연(원형) · 2 신뢰(마름모) ·
/// 3 유대(별+날개 2) · 4 반려(별+날개 4). 모양이 커질수록 단계가 올라간 게 보인다.
///
/// 리소스 접근은 `SpeciesSlug` 와 같은 규율을 따른다: 배포 `.app` 에서는 `Bundle.module` 을
/// 건드리지 않는다(그 접근자는 못 찾으면 `fatalError` 로 죽고, 그게 찾는 자리에 번들을 두면
/// codesign 이 앱 서명을 거부한다). 못 찾으면 그림 없이 비운다 — 배지 하나 때문에 앱이 죽는 건
/// 어떤 이득보다 나쁘다.
struct RibbonIcon: View {
    let ribbon: Ribbon
    var size: CGFloat = 14

    var body: some View {
        if let image = Self.image(for: ribbon) {
            Image(nsImage: image)
                .resizable().interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }

    /// 단계별 그림. 한 번 읽으면 캐시한다 — 박스 그리드가 칸마다 디스크를 때리지 않게.
    @MainActor private static var cache: [Ribbon: NSImage] = [:]

    @MainActor static func image(for ribbon: Ribbon) -> NSImage? {
        if let cached = cache[ribbon] { return cached }
        guard let url = resourceURL(for: ribbon), let image = NSImage(contentsOf: url) else {
            return nil
        }
        cache[ribbon] = image
        return image
    }

    nonisolated static func resourceURL(for ribbon: Ribbon) -> URL? {
        let name = "ribbon-\(ribbon.rawValue)"
        guard AppEnv.isBundledApp else {
            return Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "ribbons")
                ?? Bundle.module.url(forResource: name, withExtension: "png")
        }
        let bundlePath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/PokeDexBar_PokeDexBar.bundle")
        guard let bundle = Bundle(path: bundlePath.path) else { return nil }
        return bundle.url(forResource: name, withExtension: "png", subdirectory: "ribbons")
            ?? bundle.url(forResource: name, withExtension: "png")
    }
}
