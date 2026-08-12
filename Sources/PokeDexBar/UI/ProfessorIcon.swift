import SwiftUI

/// 박사 얼굴. "박사의 제안" 이 **누구의** 제안인지 한눈에 말해 준다 — 제목만 있으면 상점의
/// 다른 섹션들과 같은 무게로 읽히고, 이 자리가 사람과 거래하는 자리라는 게 안 보인다.
///
/// 리소스 접근은 `RibbonIcon`·`EggIcon` 과 같은 규율을 따른다: 배포 `.app` 에서는 `Bundle.module`
/// 을 건드리지 않는다(그 접근자는 못 찾으면 `fatalError` 로 죽고, 그게 찾는 자리에 번들을 두면
/// codesign 이 앱 서명을 거부한다). 못 찾으면 그림 없이 비운다 — 얼굴 하나 때문에 앱이 죽는 건
/// 어떤 이득보다 나쁘다.
struct ProfessorIcon: View {
    var size: CGFloat = 22

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable().interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }

    /// 한 번 읽으면 캐시한다 — 상점을 열 때마다 디스크를 때리지 않게.
    @MainActor private static var cached: NSImage?

    @MainActor static var image: NSImage? {
        if let cached { return cached }
        guard let url = resourceURL, let image = NSImage(contentsOf: url) else { return nil }
        cached = image
        return image
    }

    nonisolated static var resourceURL: URL? {
        guard AppEnv.isBundledApp else {
            return Bundle.module.url(forResource: "oak", withExtension: "png", subdirectory: "professor")
                ?? Bundle.module.url(forResource: "oak", withExtension: "png")
        }
        let bundlePath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/PokeDexBar_PokeDexBar.bundle")
        guard let bundle = Bundle(path: bundlePath.path) else { return nil }
        return bundle.url(forResource: "oak", withExtension: "png", subdirectory: "professor")
            ?? bundle.url(forResource: "oak", withExtension: "png")
    }
}
