import Foundation

// 여러 테스트 파일이 공유하는 결정적 RNG 헬퍼. 원래 CompanionTests.swift 에 있었으나(Task 8 에서
// 삭제), 구 컴패니언 시스템과 무관하게 여러 테스트가 재사용하므로 이 파일로 옮겼다.

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class CountingRNG: RandomNumberGenerator {
    private var base: SeededRNG
    private(set) var callCount = 0

    init(seed: UInt64) { base = SeededRNG(seed: seed) }

    func next() -> UInt64 {
        callCount += 1
        return base.next()
    }
}
