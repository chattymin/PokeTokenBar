import Foundation

/// 한국어 조사 선택 — 런타임에 오는 이름(PokéAPI) 뒤에 받침에 맞는 조사를 붙인다.
/// 번역문에 "이(가)"처럼 병기하던 자리를 "피카츄가", "이상해씨가"처럼 자연스럽게 만든다.
///
/// 판정은 마지막 글자가 한글 음절(U+AC00…U+D7A3)일 때만 한다. 그 밖(안농의 "[A]", 이름 로딩 전
/// "#123" 등)은 받침을 알 수 없으므로 기존 병기 형태를 그대로 붙인다 — 틀린 조사보다 병기가 낫다.
enum KoreanParticle {
    case subject     // 이/가
    case object      // 을/를
    case direction   // 으로/로

    func attach(to word: String) -> String {
        guard let coda = Self.coda(of: word) else { return word + fallback }
        switch self {
        case .subject:   return word + (coda == 0 ? "가" : "이")
        case .object:    return word + (coda == 0 ? "를" : "을")
        // ㄹ 받침은 "으로"가 아니라 "로"(서울로·알로).
        case .direction: return word + (coda == 0 || coda == Self.rieul ? "로" : "으로")
        }
    }

    private var fallback: String {
        switch self {
        case .subject:   return "이(가)"
        case .object:    return "을(를)"
        case .direction: return "(으)로"
        }
    }

    private static let syllables: ClosedRange<UInt32> = 0xAC00...0xD7A3
    private static let rieul: UInt32 = 8

    /// 마지막 글자의 종성 인덱스(0 = 받침 없음). 한글 음절이 아니면 nil.
    private static func coda(of word: String) -> UInt32? {
        guard let last = word.unicodeScalars.last, syllables.contains(last.value) else { return nil }
        return (last.value - syllables.lowerBound) % 28
    }
}
