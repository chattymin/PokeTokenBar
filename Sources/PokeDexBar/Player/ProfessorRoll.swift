import Foundation

/// 박사의 제안을 뽑는 **결정적** 굴림.
///
/// 왜 난수기가 아니라 이것인가: 제안 생성은 `baseSpeciesIndex()`(네트워크)를 요구해서, 그날 처음
/// 열었을 때 인덱스가 아직 안 왔으면 생성이 미뤄지고 나중에 다시 불린다. 난수기를 쓰면 재시도할
/// 때마다 다른 3마리가 나와 "인덱스가 오기 전에 껐다 켜면 리롤" 이라는 길이 생긴다. 날짜에서
/// 값을 만들면 몇 번을 다시 굴려도 같은 3마리다.
///
/// (`SeededRNG` 는 `Tests/PokeDexBarTests/TestSupport.swift` 에만 있어 프로덕션에서 못 쓴다.)
enum ProfessorRoll {
    /// 굴림의 용도. 같은 자리에서 등급·종·이로치가 같은 값을 쓰면 서로 붙어 움직인다.
    enum Salt {
        static let grade: UInt64 = 0x01
        static let species: UInt64 = 0x02
        static let shiny: UInt64 = 0x03
        static let nature: UInt64 = 0x04
        static let region: UInt64 = 0x05
        static let regionPick: UInt64 = 0x06
        static let birthForm: UInt64 = 0x07
        static let birthFormPick: UInt64 = 0x08
    }

    /// FNV-1a 64비트.
    ///
    /// **`String.hashValue` 를 쓰면 안 된다** — Swift 기본 해시는 프로세스마다 무작위로 시딩되므로
    /// 앱을 껐다 켤 때마다 다른 값이 나온다. 그러면 이 함수가 존재하는 이유 자체가 없어진다.
    static func hash(_ text: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }

    /// 0…1 굴림(1 미포함). 같은 (날짜·자리·용도) 면 언제나 같은 값이다.
    static func unit(date: String, slot: Int, salt: UInt64) -> Double {
        // SplitMix64 믹싱 — FNV 는 비트가 고르게 안 퍼져서 하위 비트만 쓰면 편향이 남는다.
        var z = hash(date) &+ (UInt64(bitPattern: Int64(slot)) &* 0x9E37_79B9_7F4A_7C15) &+ salt
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= (z >> 31)
        return Double(z % 1_000_000) / 1_000_000
    }
}
