import Foundation

/// 설정의 "문제점 알리기" — 기본 메일 클라이언트로 사전 작성된 리포트 메일을 연다.
/// 앱은 메일을 직접 전송하지 않는다(SMTP/계정 불필요) — mailto URL 조립까지만 담당.
enum SupportMail {
    /// 수신 주소 — 개발자 공개 연락처(GitHub 프로필 공개 이메일과 동일).
    static let address = "parkdongmin123@gmail.com"

    /// mailto URL 조립 — subject/body 는 URLComponents 가 percent-encode (개행·한글 포함).
    static func mailtoURL(to: String = address, subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        // URLComponents 는 query 의 '+' 를 percent-encode 하지 않아, 다수 메일 클라이언트가 공백으로
        // 디코드한다(제목/본문의 'C++'·경로 등 왜곡). query 부분의 '+' 만 %2B 로 치환.
        guard let raw = components.url?.absoluteString else { return nil }
        guard let q = raw.firstIndex(of: "?") else { return URL(string: raw) }
        let head = raw[...q]
        let query = raw[raw.index(after: q)...].replacingOccurrences(of: "+", with: "%2B")
        return URL(string: head + query)
    }
}
