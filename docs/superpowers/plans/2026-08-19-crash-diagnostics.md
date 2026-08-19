# 크래시 진단 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 크래시 직전의 문맥(어떤 종의 상세를 열었는가 등)을 남기고, 사용자가 GitHub 이슈로 한 번에 넘길 수 있게 한다.

**Architecture:** 시그널 핸들러는 문자열을 만들 수 없고 `AppLog` 는 비동기라, 문맥은 **죽기 전에 동기로 디스크에 있어야 한다.** 최근 20개 행동을 링에 담아 매번 작은 파일을 원자적으로 덮어쓰고, 다음 기동에 `CrashReporter` 가 비정상 종료였을 때만 메인 로그로 합친다. 진단 텍스트 조립(경로 지우기·길이 자르기)과 GitHub URL 조립은 순수 함수라 전수 테스트한다.

**Tech Stack:** Swift 6 / SwiftPM / SwiftUI / macOS 14 / 외부 의존성 없음

**설계 문서:** `docs/superpowers/specs/2026-08-19-crash-diagnostics-design.md`

## Global Constraints

- 커밋 메시지·PR 은 **영어**, 코드 주석은 **한국어** (CLAUDE.md 기여 언어 규약).
- 사용자 문구는 ko/en/ja 셋 다 — `L` 의 `t(ko, en, ja)` 패턴.
- 빌드 경고 0. 검증은 **`swift build --build-tests`**.
- 외부 의존성 추가 금지. 원격 크래시 수집 서비스를 붙이지 않는다.
- **테스트가 실제 로그·빵부스러기 파일을 건드리지 않는다.** 경로를 갈아끼워 임시 파일에 쓴다.
- **앱이 자동으로 아무것도 전송하지 않는다.** 이슈 작성 페이지를 열 뿐, 제출은 사용자가 한다.
- **개인정보:** 홈 디렉터리 경로를 지우고, 세이브 내용을 넣지 않는다.
- 순수 판정은 부수효과와 분리해 순수 함수로 테스트한다.
- 테스트는 **결함 조건을 실제로 밟아야** 한다. 게이트를 검사할 때는 **대조군**(게이트가 늘 켜져/꺼져 있지 않은지)을 짝짓는다.

---

### Task 1: 빵부스러기

**Files:**
- Create: `Sources/PokeDexBar/Core/Breadcrumbs.swift`
- Test: `Tests/PokeDexBarTests/BreadcrumbsTests.swift`

**Interfaces:**
- Consumes: `AppEnv.storageName`, `AppEnv.isBundledApp`
- Produces:
  - `enum Breadcrumbs`
  - `static var fileURL: URL` (설정 가능 — 테스트가 갈아끼운다)
  - `static let capacity = 20`
  - `static func record(_ line: String)`
  - `static func read() -> [String]`
  - `static func clear()`
  - `static func reset()` — 메모리 링과 파일을 함께 비운다(테스트 격리용)

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
import XCTest
@testable import PokeDexBar

/// 빵부스러기 — **동기로** 써야만 의미가 있다. 죽는 그 런루프에서 쓰였어야 하기 때문이다.
final class BreadcrumbsTests: XCTestCase {
    private var temp: URL!

    override func setUp() {
        super.setUp()
        temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("bc-\(UUID().uuidString).txt")
        Breadcrumbs.fileURL = temp
        Breadcrumbs.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temp)
        super.tearDown()
    }

    /// **이 기능이 존재하는 이유.** `record` 가 돌아온 직후 파일에 이미 있어야 한다 —
    /// 비동기로 넘기면 크래시가 그 사이에 일어나 아무것도 안 남는다.
    func testRecordIsOnDiskBeforeItReturns() {
        Breadcrumbs.record("detail open: species=133")
        // 기다리지 않는다. 여기서 파일을 바로 읽는다.
        let text = try? String(contentsOf: temp, encoding: .utf8)
        XCTAssertNotNil(text, "record 가 돌아왔는데 파일이 없다 — 비동기로 쓰고 있다")
        XCTAssertTrue(text?.contains("species=133") == true, "\(text ?? "nil")")
    }

    /// 링은 최근 `capacity` 개만 남긴다.
    func testTheRingKeepsOnlyTheMostRecent() {
        for i in 0..<(Breadcrumbs.capacity + 5) { Breadcrumbs.record("line \(i)") }
        let lines = Breadcrumbs.read()
        XCTAssertEqual(lines.count, Breadcrumbs.capacity)
        XCTAssertFalse(lines.contains { $0.contains("line 0") }, "오래된 줄이 안 빠졌다")
        XCTAssertTrue(lines.contains { $0.contains("line \(Breadcrumbs.capacity + 4)") },
                      "가장 최근 줄이 없다")
    }

    /// 순서가 유지된다 — 시간순으로 읽혀야 무슨 일이 있었는지 재구성할 수 있다.
    func testOrderIsOldestFirst() {
        Breadcrumbs.record("first")
        Breadcrumbs.record("second")
        let lines = Breadcrumbs.read()
        XCTAssertTrue(lines[0].contains("first"))
        XCTAssertTrue(lines[1].contains("second"))
    }

    /// 각 줄에 시각이 붙는다 — 언제 열었는지가 있어야 로그의 다른 줄과 맞춰 볼 수 있다.
    func testEachLineIsTimestamped() {
        Breadcrumbs.record("detail open: species=1")
        XCTAssertTrue(Breadcrumbs.read()[0].hasPrefix("["), "시각 접두가 없다")
    }

    func testClearEmptiesBothTheRingAndTheFile() {
        Breadcrumbs.record("x")
        Breadcrumbs.clear()
        XCTAssertTrue(Breadcrumbs.read().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
    }

    /// 파일이 없어도 안 죽는다(첫 실행).
    func testReadingWithNoFileIsEmpty() {
        XCTAssertTrue(Breadcrumbs.read().isEmpty)
    }

    /// 개행이 든 줄을 넣어도 링이 안 망가진다 — 파일이 줄 단위로 읽히므로.
    func testNewlinesInAMessageDoNotBreakTheRing() {
        Breadcrumbs.record("a\nb")
        Breadcrumbs.record("c")
        XCTAssertEqual(Breadcrumbs.read().count, 2, "한 줄이 두 줄로 쪼개졌다")
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `swift build --build-tests` → 컴파일 실패(`Breadcrumbs` 없음).

- [ ] **Step 3: 구현한다**

```swift
import Foundation

/// 크래시 직전에 무엇을 하고 있었는지. **동기로 쓴다** — 이것이 이 타입의 존재 이유다.
///
/// `AppLog.write` 는 `queue.async` 라 못 쓴다. 상세 화면을 여는 바로 그 런루프에서 죽으면
/// 비동기 기록은 도착하기 전이고, 진단이 필요한 정확히 그 순간에 없어진다.
/// 시그널 핸들러 쪽에서 만들 수도 없다 — async-signal-safe 라 문자열 조립이 금지다.
/// 그래서 **미리, 동기로** 디스크에 둔다.
///
/// 덮어쓰기라 파일이 안 자란다(회전 없음). 원자적 write 라 쓰는 도중에 죽어도 안 찢어진다.
enum Breadcrumbs {
    static let capacity = 20

    /// 기본 자리는 `AppEnv` 로 가른다 — 배포 앱만 실제 Logs 디렉터리에 쓴다.
    /// `AppLog` 처럼 `isBundledApp` 가드를 걸면 **동기 write 성질 자체를 테스트할 수 없다.**
    nonisolated(unsafe) static var fileURL: URL = defaultURL()

    private nonisolated(unsafe) static var ring: [String] = []
    private static let lock = NSLock()

    static func record(_ line: String) {
        // 개행을 지운다 — 파일을 줄 단위로 읽으므로 한 항목이 여러 줄이 되면 링이 어긋난다.
        let flat = line.replacingOccurrences(of: "\n", with: " ")
        let stamped = "[\(ISO8601DateFormatter().string(from: Date()))] \(flat)"
        lock.lock()
        ring.append(stamped)
        if ring.count > capacity { ring.removeFirst(ring.count - capacity) }
        let snapshot = ring.joined(separator: "\n")
        lock.unlock()
        // 동기·원자적. 실패해도 조용히 넘어간다 — 진단이 앱을 죽이면 안 된다.
        try? Data(snapshot.utf8).write(to: fileURL, options: .atomic)
    }

    static func read() -> [String] { /* 파일이 있으면 파일, 없으면 빈 배열 */ }
    static func clear() { /* 링 비우고 파일 삭제 */ }
    static func reset() { clear() }

    private static func defaultURL() -> URL { /* 배포 앱이면 Logs/, 아니면 임시 디렉터리 */ }
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `swift test --filter BreadcrumbsTests`
Expected: PASS

- [ ] **Step 5: 돌연변이로 확인한다 (건너뛰지 말 것)**

`record` 의 write 를 `DispatchQueue.global().async { … }` 로 감싸 보고 `testRecordIsOnDiskBeforeItReturns` 가 **실패하는지** 확인한다. 실패하지 않으면 그 테스트는 이 기능의 유일한 load-bearing 성질을 안 지키고 있다. 확인 뒤 되돌린다.

- [ ] **Step 6: 커밋**

```bash
git add Sources/PokeDexBar/Core/Breadcrumbs.swift Tests/PokeDexBarTests/BreadcrumbsTests.swift
git commit -m "feat: record breadcrumbs synchronously so a crash keeps its context"
```

---

### Task 2: 크래시 리포터와 합치기

**Files:**
- Modify: `Sources/PokeDexBar/Core/CrashReporter.swift`
- Test: `Tests/PokeDexBarTests/CrashReporterBreadcrumbTests.swift`

**Interfaces:**
- Consumes: `Breadcrumbs`
- Produces: `CrashReporter.drainBreadcrumbs(afterUncleanShutdown: Bool) -> String?` — 순수하게 만들 수 있는 부분을 분리해 테스트 가능하게 한다

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
import XCTest
@testable import PokeDexBar

final class CrashReporterBreadcrumbTests: XCTestCase {
    private var temp: URL!

    override func setUp() {
        super.setUp()
        temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("bc-\(UUID().uuidString).txt")
        Breadcrumbs.fileURL = temp
        Breadcrumbs.reset()
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: temp)
        super.tearDown()
    }

    /// 비정상 종료였으면 빵부스러기를 합쳐 낸다.
    func testUncleanShutdownYieldsTheBreadcrumbs() {
        Breadcrumbs.record("detail open: species=133 shiny=true")
        let drained = CrashReporter.drainBreadcrumbs(afterUncleanShutdown: true)
        XCTAssertTrue(drained?.contains("species=133") == true, "\(drained ?? "nil")")
    }

    /// **대조군 — 정상 종료였으면 안 합친다.** 매번 합치면 메인 로그가 잡음으로 차서
    /// 2MB 회전이 빨라지고 정작 필요한 이력이 밀려난다.
    func testCleanShutdownYieldsNothing() {
        Breadcrumbs.record("detail open: species=133")
        XCTAssertNil(CrashReporter.drainBreadcrumbs(afterUncleanShutdown: false))
    }

    /// 어느 쪽이든 **파일은 비워진다** — 이번 세션의 빵부스러기가 다음 세션에 섞이면 안 된다.
    func testTheFileIsClearedEitherWay() {
        for unclean in [true, false] {
            Breadcrumbs.record("x")
            _ = CrashReporter.drainBreadcrumbs(afterUncleanShutdown: unclean)
            XCTAssertTrue(Breadcrumbs.read().isEmpty, "unclean=\(unclean)")
        }
    }

    /// 빵부스러기가 없으면 nil — 빈 줄을 로그에 안 남긴다.
    func testNoBreadcrumbsYieldsNothing() {
        XCTAssertNil(CrashReporter.drainBreadcrumbs(afterUncleanShutdown: true))
    }
}
```

- [ ] **Step 2~4: 실패 확인 → 구현 → 통과 확인**

`install(version:)` 의 마커 검사 결과를 `drainBreadcrumbs(afterUncleanShutdown:)` 에 넘기고, 돌려받은 문자열이 있으면 `AppLog.write` 한다. **마커를 지우기 전에** 부른다 — 순서가 뒤집히면 항상 "정상 종료"로 보여 아무것도 안 합쳐진다.

- [ ] **Step 5: 커밋**

```bash
git add -A
git commit -m "feat: fold breadcrumbs into the log after an unclean shutdown"
```

---

### Task 3: 진단 텍스트 — 경로 지우기와 길이 자르기

**Files:**
- Create: `Sources/PokeDexBar/Core/Diagnostics.swift`
- Test: `Tests/PokeDexBarTests/DiagnosticsTests.swift`

**Interfaces:**
- Consumes: `Breadcrumbs`, `AppLog`
- Produces:
  - `Diagnostics.redact(_ text: String, home: String) -> String`
  - `Diagnostics.report(version:os:uncleanShutdown:breadcrumbs:boxCount:dexCount:) -> String`
  - `Diagnostics.issueURL(repo:title:body:limit:) -> (url: URL, truncated: Bool)?`
  - `Diagnostics.urlLimit = 6000`
  - `Diagnostics.repo = "donky-ey/PokeDexBar"`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
import XCTest
@testable import PokeDexBar

final class DiagnosticsTests: XCTestCase {

    // MARK: 경로 지우기

    /// **홈 경로가 지워진다.** 공개 이슈에 실명이 새면 안 된다.
    func testHomePathIsRedacted() {
        let text = "cache at /Users/dongmin/Library/Caches/PokeDexBar/x.gif"
        let out = Diagnostics.redact(text, home: "/Users/dongmin")
        XCTAssertFalse(out.contains("dongmin"), out)
        XCTAssertTrue(out.contains("~/Library/Caches/PokeDexBar/x.gif"), out)
    }

    /// 여러 번 나와도 전부 지운다.
    func testEveryOccurrenceIsRedacted() {
        let out = Diagnostics.redact("/Users/a/x and /Users/a/y", home: "/Users/a")
        XCTAssertFalse(out.contains("/Users/a"), out)
    }

    /// **대조군 — 경로가 아닌 것은 그대로 남는다.** 지우기가 너무 넓게 잡히면
    /// 진단이 통째로 뭉개져 이슈가 쓸모없어진다.
    func testNonPathTextSurvivesRedaction() {
        let text = "detail open: species=133 shiny=true level=42"
        XCTAssertEqual(Diagnostics.redact(text, home: "/Users/dongmin"), text)
    }

    // MARK: URL 조립

    private func longBody(_ n: Int) -> String {
        (0..<n).map { "[2026-08-19T00:00:00Z] detail open: species=\($0) 상세 화면 진입" }
            .joined(separator: "\n")
    }

    /// 짧은 본문은 안 잘린다.
    func testAShortBodyIsNotTruncated() {
        let made = Diagnostics.issueURL(repo: Diagnostics.repo, title: "crash",
                                        body: "short", limit: Diagnostics.urlLimit)
        XCTAssertEqual(made?.truncated, false)
    }

    /// **긴 본문은 잘리되 URL 이 한도 안에 들어오고 여전히 유효하다.**
    /// 한글은 percent-encoding 으로 세 배가 되므로 인코딩 *후* 길이로 재야 한다.
    func testALongBodyIsTruncatedUnderTheLimit() {
        let made = Diagnostics.issueURL(repo: Diagnostics.repo, title: "crash",
                                        body: longBody(400), limit: Diagnostics.urlLimit)
        XCTAssertNotNil(made)
        XCTAssertTrue(made!.truncated)
        XCTAssertLessThanOrEqual(made!.url.absoluteString.count, Diagnostics.urlLimit)
    }

    /// **자르기는 뒤에서부터다 — 앞의 버전 정보는 반드시 남는다.**
    /// 앞을 먹으면 이슈에 버전이 없어 아무 쓸모가 없다.
    func testTruncationKeepsTheHead() {
        let body = "PokeDexBar 1.8.0 / macOS 26.5\n" + longBody(400)
        let made = Diagnostics.issueURL(repo: Diagnostics.repo, title: "crash",
                                        body: body, limit: Diagnostics.urlLimit)
        XCTAssertTrue(made!.url.absoluteString.contains("1.8.0"),
                      "버전이 잘려 나갔다 — 자르기가 앞을 먹고 있다")
    }

    /// 저장소 경로가 맞는 자리로 간다.
    func testTheURLPointsAtTheNewIssueForm() {
        let made = Diagnostics.issueURL(repo: Diagnostics.repo, title: "t", body: "b", limit: 6000)
        XCTAssertTrue(made!.url.absoluteString
            .hasPrefix("https://github.com/donky-ey/PokeDexBar/issues/new"), made!.url.absoluteString)
    }

    // MARK: 리포트 본문

    /// 리포트에 진단에 필요한 것이 들어 있다.
    func testTheReportCarriesVersionOsAndBreadcrumbs() {
        let text = Diagnostics.report(version: "1.8.0", os: "Version 26.5",
                                      uncleanShutdown: true,
                                      breadcrumbs: ["[t] detail open: species=133"],
                                      boxCount: 12, dexCount: 40)
        for needle in ["1.8.0", "26.5", "species=133"] {
            XCTAssertTrue(text.contains(needle), "\(needle) 가 없다:\n\(text)")
        }
    }

    /// **비정상 종료 여부가 양쪽 다 표시된다** — "정상"이 조용히 생략되면
    /// 그 이슈가 크래시인지 아닌지 읽는 사람이 알 수 없다.
    func testUncleanShutdownIsStatedEitherWay() {
        let crashed = Diagnostics.report(version: "1", os: "o", uncleanShutdown: true,
                                         breadcrumbs: [], boxCount: 0, dexCount: 0)
        let clean = Diagnostics.report(version: "1", os: "o", uncleanShutdown: false,
                                       breadcrumbs: [], boxCount: 0, dexCount: 0)
        XCTAssertNotEqual(crashed, clean)
    }

    /// **세이브 내용은 안 들어간다.** 규모(개수)만 넣는다.
    func testTheReportDoesNotCarrySaveContents() {
        let text = Diagnostics.report(version: "1", os: "o", uncleanShutdown: false,
                                      breadcrumbs: [], boxCount: 12, dexCount: 40)
        XCTAssertTrue(text.contains("12"))
        XCTAssertFalse(text.lowercased().contains("earnedtokens"))
        XCTAssertFalse(text.lowercased().contains("partnerid"))
    }
}
```

- [ ] **Step 2~4: 실패 확인 → 구현 → 통과 확인**

`issueURL` 은 인코딩한 뒤 길이를 재고, 넘치면 **본문 뒤에서부터** 줄 단위로 덜어내며 다시 인코딩한다. 잘렸으면 본문 끝에 안내 한 줄(설정 → 로그 파일 보기)을 붙인다. 안내를 붙이면 길이가 다시 늘어나므로 **안내를 붙인 상태로 한도를 만족할 때까지** 줄인다 — 붙이기 전 길이로 판정하면 한도를 넘는다.

- [ ] **Step 5: 커밋**

```bash
git add -A
git commit -m "feat: assemble a redacted diagnostics report and a GitHub issue URL"
```

---

### Task 4: 문구

**Files:**
- Modify: `Sources/PokeDexBar/Core/Localization.swift`
- Delete: `L.reportMailSubject`, `L.reportMailBody`, `L.reportMailFallback`

**Interfaces:**
- Produces: `L.reportOnGitHub`, `L.copyDiagnostics`, `L.diagnosticsCopied`, `L.reportBrowserFallback(_:)`, `L.reportIssueTitle(_:)`, `L.diagnosticsTruncatedHint`

- [ ] **Step 1~3:** 기존 `t(ko, en, ja)` 패턴대로 추가하고, 지워지는 세 개를 참조하는 곳이 없는지 `swift build --build-tests` 로 확인한다.

- [ ] **Step 4: 커밋**

```bash
git add -A
git commit -m "feat: add GitHub report strings and drop the mail ones"
```

---

### Task 5: 설정 화면 — GitHub 과 복사

**Files:**
- Modify: `Sources/PokeDexBar/UI/SettingsView.swift`
- Delete: `Sources/PokeDexBar/Core/SupportMail.swift`
- Test: `Tests/PokeDexBarTests/SettingsReportTests.swift`
- Modify: 기존 `SupportMail` 테스트가 있으면 삭제

**Interfaces:**
- Produces: `struct SupportActionRow: View` — `SettingsToggleRow` 와 같은 이유로 별도 타입 + `#if DEBUG` 레코더 `constructed: [(label: String, action: () -> Void)]`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
import XCTest
import SwiftUI
@testable import PokeDexBar

/// 버튼이 **화면에 실제로 있고 눌렀을 때 동작하는지.**
/// (`SettingsToggleRow` 가 별도 타입으로 뽑힌 것과 같은 이유 — 설정이 섹션을 옮기다 통째로
///  사라져 어느 화면에서도 못 켜는 상태로 남았던 적이 있다.)
@MainActor
final class SettingsReportTests: XCTestCase {

    /// 두 버튼이 다 붙어 있다.
    func testBothSupportButtonsAreOnScreen() {
        // 설정 화면을 NSHostingView 로 호스팅하고 `SupportActionRow.constructed` 를 확인한다.
    }

    /// **메일 경로가 사라졌다.** 지웠는데 화면에 남아 있으면 죽은 버튼이 된다.
    func testTheMailButtonIsGone() {}

    /// **복사를 실제로 눌러 클립보드에 진단이 들어가는지.**
    /// 뷰만 만들고 안 누르면 배선이 끊겨 있어도 통과한다.
    func testTappingCopyPutsTheDiagnosticsOnThePasteboard() {}

    /// 브라우저 열기에 실패하면 URL 을 선택 가능한 텍스트로 띄운다.
    func testABrowserFailureShowsTheURLAsSelectableText() {}
}
```

**구현자에게:** 위 본문을 전부 채운다. 기존 설정 테스트의 호스팅 헬퍼(`SettingsToggleRow` 를 확인하는 테스트)를 그대로 재사용한다. 클립보드 테스트는 `NSPasteboard.general` 을 쓰되, 테스트 전후로 내용을 복원하지 않아도 되는지 확인하고 필요하면 별도 `NSPasteboard(name:)` 를 주입 가능하게 만든다.

- [ ] **Step 2~4: 실패 확인 → 구현 → 통과 확인**

`aboutSupportGroup` 을 설계 문서 §4 의 표대로 고친다. `reportProblem()` 을 지우고 GitHub 열기·복사 두 동작으로 대체한다. `SupportMail.swift` 를 삭제한다.

- [ ] **Step 5: 렌더해서 확인한다**

한 줄에 버튼 두 개가 들어가고 **세 언어**(ko/en/ja)에서 안 깨지는지 오프스크린 렌더로 본다. 일본어가 대개 가장 길다.

- [ ] **Step 6: 커밋**

```bash
git add -A
git commit -m "feat: report problems through GitHub issues instead of mail"
```

---

### Task 6: 빵부스러기를 실제로 남기는 자리들

**Files:**
- Modify: `Sources/PokeDexBar/UI/IndividualDetailView.swift` (상세 진입)
- Modify: `Sources/PokeDexBar/UI/PopoverView.swift` (탭 전환)
- Modify: `Sources/PokeDexBar/Player/PlayerStore+Hatching.swift`, `PlayerStore+Evolution.swift` (상태 전이)
- Test: `Tests/PokeDexBarTests/BreadcrumbWiringTests.swift`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
/// **배선 테스트** — 기록 함수를 직접 부르는 테스트는 배선이 끊겨 있어도 통과한다.
/// 화면을 실제로 열어서 확인한다.
@MainActor
final class BreadcrumbWiringTests: XCTestCase {
    /// 상세 화면을 열면 **종 번호**가 찍힌다. 이 제보를 푸는 것이 정확히 이 줄이다.
    func testOpeningADetailViewRecordsTheSpecies() {}

    /// 위장한 메타몽은 **진짜 종과 표시 종을 둘 다** 남긴다 — 진단은 진실이 필요하고,
    /// 이 파일은 사용자에게 안 보이는 자리다.
    func testADisguisedIndividualRecordsBothIDs() {}

    /// 이로치·폼·지방·레벨·등급이 함께 남는다.
    func testTheDetailBreadcrumbCarriesTheFullIdentity() {}

    /// 탭을 옮기면 남는다.
    func testSwitchingTabsIsRecorded() {}

    /// **매 초 도는 자리에는 안 건다** — 사용량 틱이 빵부스러기를 채우면
    /// 링 20칸이 즉시 밀려 정작 필요한 행동이 사라진다.
    func testTheUsageTickDoesNotRecordBreadcrumbs() {}
}
```

- [ ] **Step 2~4: 실패 확인 → 구현 → 통과 확인**

상세 진입은 `.onAppear` 가 아니라 **뷰가 만들어지는 자리**에 건다 — 크래시가 `body` 평가 중에 나면 `.onAppear` 는 영영 안 온다. 개체를 받아 즉시 기록하고 그 다음에 화면을 짓는다.

- [ ] **Step 5: 커밋**

```bash
git add -A
git commit -m "feat: leave breadcrumbs when opening a detail view and switching tabs"
```

---

### Task 7: `[0]` 부류 스윕

**Files:**
- Modify: `Sources/PokeDexBar/UI/SpriteLoader.swift:146` 외 스윕 결과
- Test: 해당 함수의 기존 테스트 파일

- [ ] **Step 1: 전수로 훑는다**

```bash
grep -rn 'urls(for:.*)\[0\]\|\.first!\|\.last!\|try!\| as! ' Sources/PokeDexBar/
```

`FileManager.urls(for:in:)` 는 배열을 돌려주고 **빈 배열이면 `[0]` 이 죽는다.** 나온 자리를 전부 `.first` + 폴백으로 바꾼다.

- [ ] **Step 2: 회귀 테스트를 쓴다**

빈 배열 상황을 직접 만들 수는 없으므로, **경로를 만드는 함수를 순수하게 분리해** 빈 후보 목록을 넣었을 때 죽지 않고 폴백을 돌려주는지 검증한다.

- [ ] **Step 3: 커밋**

```bash
git add -A
git commit -m "fix: stop indexing possibly-empty directory lookups"
```

---

### Task 8: README·스크린샷

**Files:**
- Modify: `Tests/PokeDexBarTests/ScreenshotGenerator.swift`
- Create: `assets/report.png` (생성됨)
- Modify: `README.md`, `README.ko.md`, `README.ja.md`

- [ ] **Step 1~3**

설정 스크린샷이 이미 세 언어로 생성된다. **새 줄이 그 캡처 범위에 실제로 들어오는지 확인한다** — 화면이 길면 잘려서 안 찍힌다. 안 들어오면 픽스처나 캡처 범위를 고친다(플로팅 펫 토글이 픽스처가 꺼져 있어 영영 안 찍히던 함정과 같은 부류).

릴리스 하드 게이트가 UI `feat:` 커밋에 대해 `assets/` **신규** 파일을 요구하므로, 설정 스크린샷을 다시 그리는 것만으로는 안 된다 — 제보 화면 캡처를 **새 파일**로 추가한다.

README 세 개에 문제 제보 방법을 적는다. **일본어도 반드시** — 과거에 가드 테스트가 영어·한국어 문구만 봐서 `README.ja.md` 만 되돌려도 초록이었다.

- [ ] **Step 4: 커밋**

```bash
git add -A
git commit -m "docs: document GitHub issue reporting with a new screenshot"
```

---

## 자체 점검 결과

**스펙 커버리지:** §1 빵부스러기 → Task 1·6 / §2 진단·경로지우기 → Task 3 / §3 GitHub URL → Task 3·5 / §4 화면·메일 삭제 → Task 4·5 / §5 `[0]` 스윕 → Task 7 / §6 테스트 → 각 태스크. 빠진 절 없음.

**타입 정합:** `Breadcrumbs.fileURL`/`read()`/`clear()` 가 Task 1 에서 정의되고 Task 2·3·6 이 같은 이름으로 쓴다. `Diagnostics.repo`·`urlLimit` 이 Task 3 에서 정의되고 Task 5 가 쓴다.

**알려진 위험 — 구현자가 먼저 볼 것:**

1. **Task 1 Step 5(돌연변이 확인)를 건너뛰지 말 것.** 동기 write 가 이 기능의 유일한 load-bearing 성질이고, 그것만 지키면 나머지는 부수적이다.
2. **Task 6 의 기록 위치.** `.onAppear` 에 걸면 `body` 평가 중 크래시를 못 잡는다 — 이 제보가 정확히 그 부류일 가능성이 높다.
3. **Task 3 의 자르기 순서.** 안내 문구를 붙인 *뒤* 길이를 재야 한다. 붙이기 전 길이로 판정하면 한도를 넘는다.
4. **Task 5 의 클립보드 테스트가 사용자의 실제 클립보드를 덮어쓸 수 있다.** 주입 가능한 pasteboard 를 쓰는 편이 안전하다.
