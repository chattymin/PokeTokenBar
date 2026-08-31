import Foundation

/// JSON 응답의 **키 구조만** 문자열로 요약한다 — 값은 절대 담지 않는다.
///
/// 모르는 응답의 파서를 쓰려면 필드 이름을 알아야 하는데, 본문을 통째로 로그에 남기면 계정 식별자·
/// 프로젝트 ID 같은 게 함께 남는다. 키 이름만 남기면 스키마를 파악하면서 그런 값은 남기지 않는다.
///
/// 깊이 2까지만 본다. 한 번의 왕복으로 파서를 쓸 만큼은 보이면서, 로그 회전 예산을 잡아먹지 않는 선.
enum JSONKeyShape {
    static func describe(_ data: Data, maxDepth: Int = 2) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return "<JSON 아님>"
        }
        return describe(value: object, depth: 0, maxDepth: maxDepth)
    }

    private static func describe(value: Any, depth: Int, maxDepth: Int) -> String {
        if let dictionary = value as? [String: Any] {
            guard depth < maxDepth else { return "{…}" }
            let inner = dictionary.keys.sorted().map { key -> String in
                let child = describe(value: dictionary[key] as Any, depth: depth + 1, maxDepth: maxDepth)
                return child.isEmpty ? key : "\(key)\(child)"
            }
            return "{" + inner.joined(separator: ",") + "}"
        }
        if let array = value as? [Any] {
            // 원소 수는 값이 아니라 형태다 — 버킷이 몇 개인지가 파서 설계에 필요하다.
            guard let first = array.first else { return "[0]" }
            guard depth < maxDepth else { return "[\(array.count)]" }
            return "[\(array.count)]" + describe(value: first, depth: depth + 1, maxDepth: maxDepth)
        }
        // 스칼라는 타입만 — 숫자·문자열 값 자체는 남기지 않는다.
        switch value {
        case is NSNull: return ":null"
        case is String: return ":str"
        case is Bool: return ":bool"
        case is NSNumber: return ":num"
        default: return ""
        }
    }
}
