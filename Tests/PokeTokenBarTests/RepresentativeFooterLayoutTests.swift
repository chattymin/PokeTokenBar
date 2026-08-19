import XCTest
import SwiftUI
@testable import PokeTokenBar

/// 도감 하단은 332pt 한 줄에서 종 이름·희귀도·대표 액션을 함께 보여준다. 대표 액션의 번역문을
/// 버튼 본문에 그리면 en/es 에서 그 앞의 종 정보가 잘리므로, 실제 버튼 폭이 로케일과 무관한지 렌더한다.
@MainActor
final class RepresentativeFooterLayoutTests: XCTestCase {
    private func renderedWidth(language: AppLanguage, isRepresentative: Bool) -> CGFloat {
        let view = RepresentativeFooterButton(localization: L(language),
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
