import Foundation

/// 한국어 조사 선택 — 런타임에 오는 이름(PokéAPI) 뒤에 받침에 맞는 조사를 붙인다.
/// 번역문에 "이(가)"처럼 병기하던 자리를 "피카츄가", "이상해씨가"처럼 자연스럽게 만든다.
///
/// 판정은 마지막 글자가 한글 음절(U+AC00…U+D7A3)이거나 숫자일 때만 한다. 그 밖(안농의 "[A]", 라틴
/// 문자 등)은 받침을 알 수 없으므로 기존 병기 형태를 그대로 붙인다 — 틀린 조사보다 병기가 낫다.
enum KoreanParticle {
    case subject     // 이/가
    case object      // 을/를
    case direction   // 으로/로
    case topic       // 은/는
    case comitative  // 과/와

    func attach(to word: String) -> String {
        guard let coda = Self.coda(of: word) else { return word + fallback }
        switch self {
        case .subject:    return word + (coda == 0 ? "가" : "이")
        case .object:     return word + (coda == 0 ? "를" : "을")
        // ㄹ 받침은 "으로"가 아니라 "로"(서울로·알로).
        case .direction:  return word + (coda == 0 || coda == Self.rieul ? "로" : "으로")
        case .topic:      return word + (coda == 0 ? "는" : "은")
        case .comitative: return word + (coda == 0 ? "와" : "과")
        }
    }

    private var fallback: String {
        switch self {
        case .subject:    return "이(가)"
        case .object:     return "을(를)"
        case .direction:  return "(으)로"
        case .topic:      return "은(는)"
        case .comitative: return "와(과)"
        }
    }

    private static let syllables: ClosedRange<UInt32> = 0xAC00...0xD7A3
    private static let rieul: UInt32 = 8

    /// 마지막 글자의 종성 인덱스(0 = 받침 없음). 한글 음절도 숫자도 아니면 nil.
    private static func coda(of word: String) -> UInt32? {
        guard let last = word.unicodeScalars.last else { return nil }
        if syllables.contains(last.value) { return (last.value - syllables.lowerBound) % 28 }
        return numberCoda(of: word)
    }

    /// 숫자는 읽는 소리로 판정한다 — "2로"(이), "3으로"(삼), "10으로"(십), "v2.5.4를"(사).
    /// 끝의 숫자 덩어리만 본다: 소수점·버전 구분자 뒤는 한 자리씩 읽기 때문이다.
    /// "#123"은 아직 로딩되지 않은 이름의 자리표시라 숫자로 읽지 않는다(이름에 맞는 조사를 모른다).
    private static func numberCoda(of word: String) -> UInt32? {
        let digits = String(word.reversed().prefix { $0.isASCII && $0.isNumber }.reversed())
        guard let value = Int(digits), !word.dropLast(digits.count).hasSuffix("#") else { return nil }
        // 영 일 이 삼 사 오 육 칠 팔 구 의 받침: ㅇ ㄹ - ㅁ - - ㄱ ㄹ ㄹ -
        let ones: [UInt32] = [21, 8, 0, 16, 0, 0, 1, 8, 8, 0]
        if value == 0 { return ones[0] }
        var rest = value
        var zeros = 0
        while rest % 10 == 0 { rest /= 10; zeros += 1 }
        switch zeros {
        case 0: return ones[rest % 10]
        case 1: return 17   // 십(ㅂ)
        case 2: return 1    // 백(ㄱ)
        default: return 4   // 천·만(ㄴ)
        }
    }
}
