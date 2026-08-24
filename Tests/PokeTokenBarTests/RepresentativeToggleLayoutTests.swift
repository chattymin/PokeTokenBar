import XCTest
import SwiftUI
@testable import PokeTokenBar

/// 대표 액션은 도감 상세 머리글에서 뒤로가기·스프라이트·이름·희귀도·이로치 토글과 한 줄을 나눠 쓴다.
/// 번역문을 버튼 본문에 그리면 긴 로케일에서 옆 정보가 밀리므로, 실제 버튼 폭이 로케일과 무관한지 렌더한다.
@MainActor
final class RepresentativeToggleLayoutTests: XCTestCase {
    private func renderedWidth(language: AppLanguage, isRepresentative: Bool) -> CGFloat {
        let view = RepresentativeToggleButton(localization: L(language),
                                              isRepresentative: isRepresentative,
                                              action: {})
        return NSHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 40)).width
    }

    func testRepresentativeActionStaysIconWidthInEveryLocaleAndState() {
        for language in AppLanguage.allCases {
            for isRepresentative in [false, true] {
                let width = renderedWidth(language: language, isRepresentative: isRepresentative)
                XCTAssertLessThanOrEqual(width, 40,
                                         "\(language) representative=\(isRepresentative) action width \(width)pt")
            }
        }
    }
}
