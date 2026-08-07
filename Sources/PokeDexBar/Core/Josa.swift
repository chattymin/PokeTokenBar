import Foundation

/// 한국어 조사 — 앞말의 받침에 따라 골라 붙인다.
///
/// 문구에 `이(가)` 처럼 두 개를 다 적어 두면 화면에 그대로 나온다. 포켓몬 이름은 데이터에서
/// 오므로(피카츄·이브이·리자몽) 미리 정할 수가 없고, 이름 하나 때문에 문장을 어색하게 비틀 수도
/// 없다. 그래서 받침을 직접 본다.
enum Josa {
    /// 이/가.
    static func iGa(_ word: String) -> String { hasFinalConsonant(word) ? "이" : "가" }
    /// 을/를.
    static func eulReul(_ word: String) -> String { hasFinalConsonant(word) ? "을" : "를" }
    /// 은/는.
    static func eunNeun(_ word: String) -> String { hasFinalConsonant(word) ? "은" : "는" }

    /// 마지막 글자에 받침이 있나.
    ///
    /// 한글은 유니코드에서 (초성, 중성, 종성)으로 조합돼 있어 종성 인덱스가 0 이 아니면 받침이 있다.
    /// **숫자로 끝나면 읽는 소리로 판단한다** — 이 앱은 이름을 못 받았을 때 `#25` 처럼 번호를
    /// 그대로 쓰므로 숫자가 실제로 문장 앞에 온다("#25가 물어 왔어요").
    /// 한글도 숫자도 아니면(영어 이름 등) 받침 없음으로 본다 — 한국어 화면에서는 드문 경우다.
    static func hasFinalConsonant(_ word: String) -> Bool {
        guard let last = word.unicodeScalars.last else { return false }
        if (0xAC00...0xD7A3).contains(last.value) { return (last.value - 0xAC00) % 28 != 0 }
        // 0 영, 1 일(ㄹ), 2 이, 3 삼(ㅁ), 4 사, 5 오, 6 육(ㄱ), 7 칠(ㄹ), 8 팔(ㄹ), 9 구
        if let digit = last.properties.numericValue, (0...9).contains(digit) {
            return [1, 3, 6, 7, 8].contains(Int(digit))
        }
        return false
    }
}
