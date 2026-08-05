import Foundation

/// 첫 실행에 고르는 스타터. 각 세대의 1단계(진화 전) 3마리씩 — 전 세대 27마리.
enum StarterCatalog {
    static let byGeneration: [(generation: Int, speciesIDs: [Int])] = [
        (1, [1, 4, 7]),          // 이상해씨 · 파이리 · 꼬부기
        (2, [152, 155, 158]),    // 치코리타 · 브케인 · 리아코
        (3, [252, 255, 258]),    // 나무지기 · 아차모 · 물짱이
        (4, [387, 390, 393]),    // 모부기 · 불꽃숭이 · 팽도리
        (5, [495, 498, 501]),    // 주리비얀 · 뚜꾸리 · 수댕이
        (6, [650, 653, 656]),    // 도치마론 · 푸호꼬 · 개구마르
        (7, [722, 725, 728]),    // 나몰빼미 · 냐오불 · 누리공
        (8, [810, 813, 816]),    // 흥나숭 · 염버니 · 울머기
        (9, [906, 909, 912]),    // 나오하 · 뜨아거 · 꾸왁스
    ]

    static let all: [Int] = byGeneration.flatMap(\.speciesIDs)

    static func contains(_ speciesID: Int) -> Bool { all.contains(speciesID) }
}
