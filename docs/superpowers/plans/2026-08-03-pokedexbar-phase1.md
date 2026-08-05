# PokeDexBar 1단계 구현 계획 (포크 · 전 세대 · 안티앨리어싱)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PokeTokenBar 포크를 PokeDexBar로 리브랜딩하고, 스프라이트를 Pokémon Showdown으로 바꿔 9세대까지 1,025종을 열고, 안티앨리어싱(EPX)을 더한다.

**Architecture:** 게임 로직(부화·진화·도감·상점)은 업스트림 그대로 둔다. 손대는 곳은 (1) 이름·식별자, (2) 스프라이트 URL 계층과 종 번호→슬러그 매핑, (3) 종 범위 상수, (4) 렌더 경로의 업스케일링. 2단계에서 `CompanionState`/`CompanionStore`를 통째로 교체할 예정이므로 그 영역은 건드리지 않는다.

**Tech Stack:** Swift 6, SwiftPM, AppKit + SwiftUI, XCTest. Python 3(슬러그 생성 스크립트, 개발 시 1회).

## Global Constraints

- `swift-tools-version: 6.0`, 플랫폼 하한 `macOS 14`. 외부 Swift 의존성 없음.
- **커밋 메시지·PR은 영어**(저장소 `CLAUDE.md` 규약). **코드 주석은 한국어**(기존 코드와 동일).
- MIT 라이선스와 chattymin 저작권 표기를 지운다/바꾼다 — 금지. 포크임을 README에 명시한다.
- 스프라이트 URL은 정확히: `https://play.pokemonshowdown.com/sprites/{ani,ani-shiny,gen5,gen5-shiny}/<slug>.{gif,png}`
- 아이템·알 스프라이트는 계속 PokeAPI를 쓴다(Showdown에 대응물이 없다).
- 데이터 폴더는 `~/Library/Application Support/PokeDexBar` — 기존 PokeTokenBar 상태를 읽거나 옮기지 않는다(두 앱 공존).
- 각 태스크는 `swift build`(경고 0)와 `swift test`(전체 통과)를 통과해야 끝난다.

---

### Task 1: PokeDexBar로 리브랜딩

**Files:**
- Modify: `Package.swift`
- Rename: `Sources/PokeTokenBar/` → `Sources/PokeDexBar/`, `Tests/PokeTokenBarTests/` → `Tests/PokeDexBarTests/`
- Rename: `Sources/PokeDexBar/PokeTokenBarApp.swift` → `Sources/PokeDexBar/PokeDexBarApp.swift`
- Modify: `Sources/PokeDexBar/Core/LoginItem.swift:15-16`, `Core/UpdateChecker.swift:15,130`, `Core/AppLog.swift:15`, `Core/ProcessRunner.swift:32,34`, `Core/SaveTransfer.swift:77`, `UI/SpriteLoader.swift:13,94`, `PokeDexBarApp.swift:295`
- Modify: `scripts/build-app.sh`
- Modify: `README.md`
- Add: `docs/superpowers/specs/2026-08-03-pokedexbar-design.md`(이미 복사됨), 이 계획 파일

**Interfaces:**
- Consumes: 없음(첫 태스크)
- Produces: 타깃명 `PokeDexBar`/`PokeDexBarTests`, 번들 ID `io.github.leedg0831.pokedexbar`, 데이터 폴더 `~/Library/Application Support/PokeDexBar`. 이후 모든 태스크의 경로는 `Sources/PokeDexBar/…`.

- [ ] **Step 1: 디렉토리·파일 이름 변경**

```bash
git mv Sources/PokeTokenBar Sources/PokeDexBar
git mv Tests/PokeTokenBarTests Tests/PokeDexBarTests
git mv Sources/PokeDexBar/PokeTokenBarApp.swift Sources/PokeDexBar/PokeDexBarApp.swift
```

- [ ] **Step 2: Package.swift 갱신**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PokeDexBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PokeDexBar",
            path: "Sources/PokeDexBar",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "PokeDexBarTests",
            dependencies: ["PokeDexBar"],
            path: "Tests/PokeDexBarTests",
            resources: [.copy("Fixtures/CodexFork")]
        ),
    ]
)
```

- [ ] **Step 3: 소스 안의 식별자 일괄 치환**

```bash
# 타입·모듈 참조와 문자열을 한 번에 — 대소문자 두 형태 모두
grep -rl "PokeTokenBar\|poketokenbar" Sources Tests scripts README.md \
  | xargs sed -i '' -e 's/PokeTokenBar/PokeDexBar/g' -e 's/poketokenbar/pokedexbar/g'
# 번들 ID 소유자도 우리 것으로
grep -rl "io.github.chattymin.pokedexbar" Sources scripts \
  | xargs sed -i '' 's/io\.github\.chattymin\.pokedexbar/io.github.leedg0831.pokedexbar/g'
```

- [ ] **Step 4: 치환 결과 확인 — 남은 것이 없어야 한다**

Run: `grep -rn "PokeTokenBar\|poketokenbar\|chattymin" Sources Tests scripts Package.swift`
Expected: 출력 없음. (README·LICENSE·CLAUDE.md의 chattymin 저작권·포크 출처 표기는 **남겨야 하므로** 이 grep 대상에서 제외한다.)

- [ ] **Step 5: UpdateChecker 저장소를 우리 것으로**

`Sources/PokeDexBar/Core/UpdateChecker.swift:15` 가 치환으로 `chattymin/PokeDexBar` 가 되었을 수 있다. 다음 값이어야 한다.

```swift
    private let repo = "leedg0831/PokeDexBar"
```

- [ ] **Step 6: 빌드·테스트**

Run: `swift build && swift test`
Expected: 빌드 경고 0, 테스트 452개 전부 통과(실패 0).

- [ ] **Step 7: 앱 번들 생성 확인**

Run: `./scripts/build-app.sh`
Expected: `build/PokeDexBar.app` 생성. 다음으로 내용 확인:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' build/PokeDexBar.app/Contents/Info.plist
```
Expected: `io.github.leedg0831.pokedexbar`

- [ ] **Step 8: README에 포크 표기 추가**

`README.md` 최상단 제목 바로 아래에 다음 문단을 넣는다(영어 README 기준).

```markdown
> **A fork of [PokeTokenBar](https://github.com/chattymin/PokeTokenBar)** (MIT, © chattymin).
> PokeDexBar swaps the sprite source to [Pokémon Showdown](https://play.pokemonshowdown.com/sprites/)
> so every generation through Gen 9 is available, and adds EPX anti-aliasing for the sprites.
```

- [ ] **Step 9: 커밋**

```bash
git add -A
git commit -m "chore: rebrand the fork to PokeDexBar

Renames the target, bundle identifier, login item labels, log queue, and
Application Support directory so this fork runs side by side with an
installed PokeTokenBar instead of sharing its state. Upstream attribution
and the MIT license stay as they are."
```

---

### Task 2: 종 번호 → Showdown 슬러그 매핑

**Files:**
- Create: `scripts/generate-slugs.py`
- Create: `Sources/PokeDexBar/Resources/showdown-slugs.json` (스크립트 산출물, 커밋한다)
- Create: `Sources/PokeDexBar/Core/SpeciesSlug.swift`
- Modify: `Package.swift` (실행 타깃에 리소스 추가)
- Test: `Tests/PokeDexBarTests/SpeciesSlugTests.swift`

**Interfaces:**
- Consumes: Task 1의 `Sources/PokeDexBar/` 경로
- Produces: `enum SpeciesSlug { static func slug(_ speciesID: Int) -> String? }` — 없는 번호는 nil.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PokeDexBarTests/SpeciesSlugTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

/// 번들 매핑이 실제로 Showdown 철자와 맞는지 잠근다. 문장부호가 사라지는 종
/// (Nidoran♀·Farfetch'd·Mr. Mime·Ho-Oh·Porygon-Z·Type: Null)이 사고가 잦다.
final class SpeciesSlugTests: XCTestCase {
    func testKnownSlugs() {
        XCTAssertEqual(SpeciesSlug.slug(1), "bulbasaur")
        XCTAssertEqual(SpeciesSlug.slug(6), "charizard")
        XCTAssertEqual(SpeciesSlug.slug(29), "nidoranf")
        XCTAssertEqual(SpeciesSlug.slug(32), "nidoranm")
        XCTAssertEqual(SpeciesSlug.slug(83), "farfetchd")
        XCTAssertEqual(SpeciesSlug.slug(122), "mrmime")
        XCTAssertEqual(SpeciesSlug.slug(250), "hooh")
        XCTAssertEqual(SpeciesSlug.slug(474), "porygonz")
        XCTAssertEqual(SpeciesSlug.slug(772), "typenull")
    }

    /// 9세대까지 빠짐없이 들어 있어야 한다 — 이게 이번 포크의 목적이다.
    func testCoversEveryGeneration() {
        XCTAssertEqual(SpeciesSlug.slug(908), "meowscarada")
        XCTAssertEqual(SpeciesSlug.slug(1025), "pecharunt")
        for id in 1...1025 {
            XCTAssertNotNil(SpeciesSlug.slug(id), "종 \(id) 슬러그 없음")
        }
    }

    /// 폼(메가·리전폼)이 기본 폼 자리를 덮으면 안 된다 — 리자몽이 charizard-gmax가 되던 사고.
    func testBaseFormsOnly() {
        for id in 1...1025 {
            XCTAssertFalse(SpeciesSlug.slug(id)!.contains("-"),
                           "종 \(id) 이 폼 슬러그다: \(SpeciesSlug.slug(id)!)")
        }
    }

    func testUnknownIDIsNil() {
        XCTAssertNil(SpeciesSlug.slug(0))
        XCTAssertNil(SpeciesSlug.slug(9999))
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter SpeciesSlugTests`
Expected: FAIL — `cannot find 'SpeciesSlug' in scope`

- [ ] **Step 3: 생성 스크립트 작성**

`scripts/generate-slugs.py`:

```python
#!/usr/bin/env python3
"""Showdown pokedex → 종 번호 → 슬러그 매핑(기본 폼만). 개발 시 1회 실행해 산출물을 커밋한다."""
import json
import urllib.request

URL = "https://play.pokemonshowdown.com/data/pokedex.json"
OUT = "Sources/PokeDexBar/Resources/showdown-slugs.json"
LAST_SPECIES = 1025

req = urllib.request.Request(URL, headers={"User-Agent": "PokeDexBar-slugs/1.0"})
with urllib.request.urlopen(req, timeout=30) as response:
    dex = json.load(response)

table = {}
for slug, entry in dex.items():
    num = entry.get("num", 0)
    # 폼(메가·리전폼·거다이맥스)은 baseSpecies/forme 를 들고 있다 — 기본 폼만 남긴다.
    if num <= 0 or "forme" in entry or "baseSpecies" in entry:
        continue
    table.setdefault(num, slug)

missing = [n for n in range(1, LAST_SPECIES + 1) if n not in table]
if missing:
    raise SystemExit(f"빠진 종 {len(missing)}개: {missing[:20]}")

with open(OUT, "w") as f:
    json.dump({str(n): table[n] for n in sorted(table)}, f,
              ensure_ascii=False, separators=(",", ":"))
print(f"{len(table)} species -> {OUT}")
```

- [ ] **Step 4: 스크립트 실행**

```bash
mkdir -p Sources/PokeDexBar/Resources
python3 scripts/generate-slugs.py
```
Expected: `1025 species -> Sources/PokeDexBar/Resources/showdown-slugs.json` (또는 그 이상 — Showdown이 새 세대를 추가했을 수 있다. 1025 미만이면 중단하고 원인을 확인한다.)

- [ ] **Step 5: Package.swift에 리소스 등록**

`Package.swift` 의 실행 타깃에 `resources` 를 더한다.

```swift
        .executableTarget(
            name: "PokeDexBar",
            path: "Sources/PokeDexBar",
            resources: [.process("Resources")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
```

- [ ] **Step 6: SpeciesSlug 구현**

`Sources/PokeDexBar/Core/SpeciesSlug.swift`:

```swift
import Foundation

/// 종 번호 → Showdown 스프라이트 슬러그. 업스트림 게임 로직은 숫자 종 ID로 돌고 Showdown 은
/// 이름 슬러그(`bulbasaur`·`hooh`)를 쓰므로 그 사이를 잇는다. 번들 JSON 이라 런타임 네트워크가 없다.
/// 갱신은 `scripts/generate-slugs.py` 재실행.
enum SpeciesSlug {
    private static let table: [Int: String] = loadTable()

    static func slug(_ speciesID: Int) -> String? { table[speciesID] }

    private static func loadTable() -> [Int: String] {
        guard let url = Bundle.module.url(forResource: "showdown-slugs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
    }
}
```

- [ ] **Step 7: 테스트 통과 확인**

Run: `swift test --filter SpeciesSlugTests`
Expected: 4개 전부 통과

- [ ] **Step 8: 전체 테스트 + 커밋**

Run: `swift test`
Expected: 전부 통과(456개 내외)

```bash
git add -A
git commit -m "feat: map species numbers to Showdown sprite slugs

Upstream addresses Pokemon by number while Showdown names its sprite files
(bulbasaur, hooh, typenull). Generate that mapping once from Showdown's
pokedex, keeping base forms only so a Gigantamax entry can never take a
species' slot, and bundle it so lookups need no network."
```

---

### Task 3: 스프라이트 소스를 Showdown으로 교체

**Files:**
- Modify: `Sources/PokeDexBar/UI/SpriteLoader.swift`
- Test: `Tests/PokeDexBarTests/SpriteSourceTests.swift`

**Interfaces:**
- Consumes: `SpeciesSlug.slug(_:) -> String?` (Task 2)
- Produces: `SpriteStore.spriteURL(slug:animated:shiny:) -> URL?` (순수 함수, 테스트 대상). `SpriteStore.data(speciesID:animated:shiny:)` 의 시그니처는 그대로 유지 — 호출부를 바꾸지 않는다.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PokeDexBarTests/SpriteSourceTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

final class SpriteSourceTests: XCTestCase {
    func testAnimatedURLs() {
        XCTAssertEqual(SpriteStore.spriteURL(slug: "pikachu", animated: true, shiny: false)?.absoluteString,
                       "https://play.pokemonshowdown.com/sprites/ani/pikachu.gif")
        XCTAssertEqual(SpriteStore.spriteURL(slug: "pikachu", animated: true, shiny: true)?.absoluteString,
                       "https://play.pokemonshowdown.com/sprites/ani-shiny/pikachu.gif")
    }

    func testStaticURLs() {
        XCTAssertEqual(SpriteStore.spriteURL(slug: "mew", animated: false, shiny: false)?.absoluteString,
                       "https://play.pokemonshowdown.com/sprites/gen5/mew.png")
        XCTAssertEqual(SpriteStore.spriteURL(slug: "mew", animated: false, shiny: true)?.absoluteString,
                       "https://play.pokemonshowdown.com/sprites/gen5-shiny/mew.png")
    }

    /// 캐시 키는 종 번호 기반을 유지한다 — 슬러그가 바뀌어도 기존 캐시가 무효화되지 않게.
    func testCacheKeyStaysNumeric() {
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: true, shiny: false), "25-a")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: true, shiny: true), "25-sha")
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter SpriteSourceTests`
Expected: FAIL — `type 'SpriteStore' has no member 'spriteURL'`

- [ ] **Step 3: SpriteLoader 교체**

`Sources/PokeDexBar/UI/SpriteLoader.swift` 에서 **포켓몬 스프라이트 경로만** 바꾼다. 아이템·알은 PokeAPI 그대로 둔다(Showdown에 대응물이 없다).

`private let base = …` 줄 **아래에** 다음을 추가한다.

```swift
    /// 포켓몬 스프라이트는 Showdown — 전 세대(9세대까지)를 제공한다. 아이템·알은 대응물이 없어
    /// 계속 PokeAPI(`base`)를 쓴다.
    private static let showdownBase = "https://play.pokemonshowdown.com/sprites"
    /// 애니메이션이 없는 종(9세대 일부 패러독스·전설)을 기억해 매번 404를 받지 않는다.
    private var missingAnimated: Set<Int> = []
```

그리고 순수 URL 조립 함수를 `cacheKey` 아래에 추가한다.

```swift
    /// 슬러그 기반 스프라이트 URL. 순수 함수라 네트워크 없이 테스트한다.
    static func spriteURL(slug: String, animated: Bool, shiny: Bool) -> URL? {
        let folder = switch (animated, shiny) {
        case (true, false): "ani"
        case (true, true): "ani-shiny"
        case (false, false): "gen5"
        case (false, true): "gen5-shiny"
        }
        return URL(string: "\(showdownBase)/\(folder)/\(slug).\(animated ? "gif" : "png")")
    }
```

`func data(speciesID:animated:shiny:)` **함수 전체**를 다음으로 교체한다(기존 `urlStr` switch 문은 위 `spriteURL` 이 대신하므로 함께 사라진다).

```swift
    func data(speciesID: Int, animated: Bool, shiny: Bool = false) async -> Data? {
        // 애니메이션이 없다고 이미 확인된 종은 정적으로 떨어지게 nil 을 돌려준다(뷰가 폴백).
        if animated, missingAnimated.contains(speciesID) { return nil }
        guard let slug = SpeciesSlug.slug(speciesID) else { return nil }
        let key = Self.cacheKey(speciesID: speciesID, animated: animated, shiny: shiny)
        if let d = mem[key] { touch(key); return d }
        let ext = animated ? "gif" : "png"
        let file = dir.appendingPathComponent("\(key).\(ext)")
        if let d = try? Data(contentsOf: file) { remember(key, d); return d }
        guard let url = Self.spriteURL(slug: slug, animated: animated, shiny: shiny),
              let (d, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty else {
            if animated { missingAnimated.insert(speciesID) }
            return nil
        }
        try? d.write(to: file, options: .atomic)   // torn write 방지
        remember(key, d)
        return d
    }
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter SpriteSourceTests`
Expected: 3개 통과

- [ ] **Step 5: 실제 네트워크로 확인 (수동 1회)**

```bash
curl -s -o /dev/null -w "gen1 %{http_code}\n" https://play.pokemonshowdown.com/sprites/ani/bulbasaur.gif
curl -s -o /dev/null -w "gen9 %{http_code}\n" https://play.pokemonshowdown.com/sprites/ani/meowscarada.gif
curl -s -o /dev/null -w "gen9-static %{http_code}\n" https://play.pokemonshowdown.com/sprites/gen5/terapagos.png
```
Expected: `gen1 200`, `gen9 200`, `gen9-static 200`

- [ ] **Step 6: 전체 테스트 + 커밋**

Run: `swift test`
Expected: 전부 통과

```bash
git add -A
git commit -m "feat: load Pokemon sprites from Showdown instead of PokeAPI

PokeAPI's animated sprites stop at species 649, which is the only reason
this app was capped at five generations. Showdown serves animated and
shiny sprites through Gen 9, with a static sprite for the handful that
have no animation yet, so point species sprites there. Items and the egg
keep using PokeAPI, which Showdown has no counterpart for. Species that
turn out to have no animation are remembered so the 404 is paid once."
```

---

### Task 4: 전 세대 개방

**Files:**
- Modify: `Sources/PokeDexBar/Core/CompanionModel.swift:197-203`(PokemonAssets), `:222-226`(keepingAnimatedSprites)
- Modify: `Sources/PokeDexBar/Core/PokeAPIClient.swift:117,150`
- Modify: `Sources/PokeDexBar/Core/CompanionStore.swift:869`
- Test: `Tests/PokeDexBarTests/SpeciesRangeTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces: `PokemonAssets.speciesIDs: ClosedRange<Int>`(= `1...1025`), `PokemonAssets.hasSprite(speciesID:) -> Bool`, `EvoNode.keepingSupportedSpecies() -> EvoNode?`. 기존 이름(`animatedSpeciesIDs`·`hasAnimatedSprite`·`keepingAnimatedSprites`)은 사라진다.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PokeDexBarTests/SpeciesRangeTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

final class SpeciesRangeTests: XCTestCase {
    /// 9세대까지가 부화 풀에 들어와야 한다.
    func testRangeCoversGenNine() {
        XCTAssertEqual(PokemonAssets.speciesIDs, 1...1025)
        XCTAssertTrue(PokemonAssets.hasSprite(speciesID: 906))
        XCTAssertTrue(PokemonAssets.hasSprite(speciesID: 1025))
    }

    func testOutOfRangeIsRejected() {
        XCTAssertFalse(PokemonAssets.hasSprite(speciesID: 0))
        XCTAssertFalse(PokemonAssets.hasSprite(speciesID: 1026))
    }

    /// 진화 트리 필터는 범위 밖 종만 잘라낸다 — 9세대 체인은 온전히 남아야 한다.
    func testEvolutionTreeKeepsGenNineChain() {
        let tree = EvoNode(speciesID: 906, children: [
            EvoNode(speciesID: 907, children: [EvoNode(speciesID: 908, children: [])]),
        ])
        let kept = tree.keepingSupportedSpecies()
        XCTAssertEqual(kept?.speciesID, 906)
        XCTAssertEqual(kept?.finalIDs, [908])
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter SpeciesRangeTests`
Expected: FAIL — `type 'PokemonAssets' has no member 'speciesIDs'`

- [ ] **Step 3: PokemonAssets 교체**

`Sources/PokeDexBar/Core/CompanionModel.swift` 의 `enum PokemonAssets { … }` 를 통째로 다음으로 바꾼다.

```swift
enum PokemonAssets {
    /// 다루는 종 번호 범위. 과거엔 Gen-V 애니메이션 스프라이트가 649까지뿐이라 거기 묶여 있었지만,
    /// Showdown 은 9세대까지 제공한다. 애니메이션이 없는 소수 종은 정적 스프라이트로 떨어진다.
    static let speciesIDs = 1...1025

    static func hasSprite(speciesID: Int) -> Bool {
        speciesIDs.contains(speciesID)
    }
}
```

- [ ] **Step 4: 진화 트리 필터 이름·의미 갱신**

`Sources/PokeDexBar/Core/CompanionModel.swift` 의 `keepingAnimatedSprites()` 를 다음으로 바꾼다.

```swift
    /// 다루는 범위 밖 종을 잘라낸 진화 트리(잘린 종의 하위 체인도 함께 제외).
    func keepingSupportedSpecies() -> EvoNode? {
        guard PokemonAssets.hasSprite(speciesID: speciesID) else { return nil }
        return EvoNode(speciesID: speciesID, children: children.compactMap { $0.keepingSupportedSpecies() })
    }
```

- [ ] **Step 5: 남은 호출부 갱신**

```bash
grep -rn "animatedSpeciesIDs\|hasAnimatedSprite\|keepingAnimatedSprites" Sources Tests
```
나오는 곳을 모두 새 이름으로 바꾼다: `animatedSpeciesIDs` → `speciesIDs`, `hasAnimatedSprite(speciesID:)` → `hasSprite(speciesID:)`, `keepingAnimatedSprites()` → `keepingSupportedSpecies()`. (`PokeAPIClient.swift` 의 `maxID` 두 곳과 `CompanionStore.swift` 의 REST 폴백이 여기 해당한다.)

- [ ] **Step 6: GraphQL 주석 갱신**

`Sources/PokeDexBar/Core/PokeAPIClient.swift` 의 다음 주석을 사실에 맞게 고친다.

```swift
        // 공식 GraphQL — evolves_from IS NULL(=base) + id ≤ 1025(다루는 종 범위 상한)
```

- [ ] **Step 7: 테스트 통과 확인**

Run: `swift test --filter SpeciesRangeTests`
Expected: 3개 통과

- [ ] **Step 8: 전체 테스트 + 커밋**

Run: `swift test`
Expected: 전부 통과. 실패가 나면 649를 전제로 쓴 기존 테스트이므로, 그 테스트의 기대값을 새 범위로 고친다(테스트를 지우지 말 것).

```bash
git add -A
git commit -m "feat: open hatching to every generation through Gen 9

The 649 ceiling existed only because PokeAPI's animated sprites ended
there; now that sprites come from Showdown it can go. Rename the constant
and the evolution-tree filter to say what they actually gate — the range
of species this app handles — and widen it to 1025."
```

---

### Task 5: 안티앨리어싱(EPX) 이식

**Files:**
- Create: `Sources/PokeDexBar/UI/PixelUpscaler.swift` (PokeRunBar에서 복사)
- Create: `Sources/PokeDexBar/UI/PixelScale.swift` (PokeRunBar에서 복사)
- Modify: `Sources/PokeDexBar/Core/UsageStore.swift` (설정 토글)
- Modify: `Sources/PokeDexBar/UI/CompanionView.swift` (SpriteView에 적용)
- Modify: `Sources/PokeDexBar/UI/SettingsView.swift` (토글 UI)
- Test: `Tests/PokeDexBarTests/PixelUpscalerTests.swift` (PokeRunBar에서 복사)

**Interfaces:**
- Consumes: 없음
- Produces: `PixelUpscaler.epx(_ image: NSImage, passes: Int) -> NSImage`, `PixelScale.epxPasses(source:in:displayScale:)`, `UsageStore.antialiasSprites: Bool`, `SpriteView(… antialias: Bool = false)`

- [ ] **Step 1: PokeRunBar에서 파일 복사**

```bash
cp ~/Desktop/PokeRunBar/Sources/PokeRunBar/Sprites/PixelUpscaler.swift Sources/PokeDexBar/UI/PixelUpscaler.swift
cp ~/Desktop/PokeRunBar/Sources/PokeRunBar/UI/PixelScale.swift Sources/PokeDexBar/UI/PixelScale.swift
cp ~/Desktop/PokeRunBar/Tests/PokeRunBarTests/PixelUpscalerTests.swift Tests/PokeDexBarTests/PixelUpscalerTests.swift
cp ~/Desktop/PokeRunBar/Tests/PokeRunBarTests/PixelScaleTests.swift Tests/PokeDexBarTests/PixelScaleTests.swift
sed -i '' 's/@testable import PokeRunBar/@testable import PokeDexBar/' \
  Tests/PokeDexBarTests/PixelUpscalerTests.swift Tests/PokeDexBarTests/PixelScaleTests.swift
```

- [ ] **Step 2: 복사한 테스트가 통과하는지 확인**

Run: `swift test --filter "PixelUpscalerTests|PixelScaleTests"`
Expected: 전부 통과. 컴파일 에러가 나면 PokeRunBar 전용 참조(예: `SpriteThumbnail`)가 섞인 것이니 그 부분만 제거한다.

- [ ] **Step 3: 설정 토글 추가**

`Sources/PokeDexBar/Core/UsageStore.swift` 의 `floatingPetEnabled` 선언 옆에 다음을 추가한다.

```swift
    /// 스프라이트 안티앨리어싱(EPX 업스케일) — 저해상도 GIF 를 크게 띄울 때 계단이 덜 보이게 한다.
    var antialiasSprites: Bool {
        didSet { defaults.set(antialiasSprites, forKey: "antialiasSprites") }
    }
```

같은 파일 `init` 안의 `floatingPetEnabled = …` 줄 옆에 복원 코드를 추가한다.

```swift
        antialiasSprites = d.object(forKey: "antialiasSprites") as? Bool ?? true
```

- [ ] **Step 4: SpriteView에 적용**

`Sources/PokeDexBar/UI/CompanionView.swift` 의 `struct SpriteView` 에 파라미터를 추가한다(기존 `minFrameDelay` 와 같은 방식).

```swift
    /// 켜면 표시 크기에 맞춰 EPX 로 확대한 뒤 그린다. 기본은 끔 — 도감 썸네일처럼 작은 표시는
    /// 원본 픽셀이 더 또렷하다.
    var antialias: Bool = false
```

`init` 에 `antialias: Bool = false` 를 더하고 `self.antialias = antialias` 를 넣는다. 그리고 이미지를 그리는 두 지점(`frames` 경로와 `img` 경로)에서 이미지를 업스케일해 쓴다.

```swift
    /// 표시 크기에 맞는 EPX 패스 수만큼 확대한 이미지. 토글이 꺼져 있으면 원본 그대로.
    private func upscaled(_ image: NSImage) -> NSImage {
        guard antialias else { return image }
        let passes = PixelScale.epxPasses(source: image.size,
                                          in: CGSize(width: size, height: size),
                                          displayScale: NSScreen.main?.backingScaleFactor ?? 2)
        return passes > 0 ? PixelUpscaler.epx(image, passes: passes) : image
    }
```

`Image(nsImage: frames[frameIndex % frames.count].image)` → `Image(nsImage: upscaled(frames[frameIndex % frames.count].image))`,
`Image(nsImage: img)` → `Image(nsImage: upscaled(img))` 로 바꾼다.

- [ ] **Step 5: 큰 표시 지점에서 토글 값 전달**

`grep -rn "SpriteView(" Sources/PokeDexBar/UI` 로 호출부를 찾아, **팝오버 컴패니언 헤더**와 **플로팅 펫** 두 곳에 `antialias: store.antialiasSprites` 를 넘긴다(도감 썸네일·진화 라인 같은 작은 표시는 기본값 false 유지).

- [ ] **Step 6: 설정 UI에 토글 추가**

`Sources/PokeDexBar/UI/SettingsView.swift` 의 플로팅 펫 섹션(`floatingPetGroup`) 안, `floatingPetBubbleAlertsLabel` 토글 아래에 다음을 추가한다.

```swift
                Divider()
                toggleRow(l.antialiasLabel, $store.antialiasSprites)
```

`Sources/PokeDexBar/Core/Localization.swift` 의 플로팅 펫 문자열 근처에 라벨을 추가한다.

```swift
    var antialiasLabel: String {
        t("스프라이트 부드럽게", "Smooth sprites", "スプライトを滑らかに")
    }
```

- [ ] **Step 7: 빌드·전체 테스트**

Run: `swift build && swift test`
Expected: 경고 0, 전부 통과

- [ ] **Step 8: 커밋**

```bash
git add -A
git commit -m "feat: add EPX anti-aliasing for sprites

Showdown sprites are small, and blowing them up for the popover companion
and the floating pet leaves visible stair-stepping. Upscale with EPX by as
many passes as the display size warrants, behind a setting that defaults
on. Small surfaces such as dex thumbnails keep the raw pixels."
```

---

### Task 6: 실사용 검증

**Files:**
- Modify: `README.md` (스프라이트 출처 표기)

**Interfaces:**
- Consumes: Task 1~5 전부
- Produces: 없음(검증 태스크)

- [ ] **Step 1: 앱 번들 생성**

Run: `swift build && swift test && ./scripts/build-app.sh`
Expected: 전부 성공, `build/PokeDexBar.app` 생성

- [ ] **Step 2: 상태를 비우고 실행 (9세대가 실제로 부화하는지 보려면 새 상태가 필요하다)**

```bash
rm -rf ~/Library/Application\ Support/PokeDexBar
open build/PokeDexBar.app
```

- [ ] **Step 3: 수동 확인 목록** (사용자와 함께)

1. 메뉴바에 아이콘이 뜨고, 홈브루로 설치된 PokeTokenBar와 **동시에** 떠 있다(아이콘 2개).
2. 팝오버 → 설정에 **"스프라이트 부드럽게"** 토글이 있고, 켜고 끌 때 컴패니언 스프라이트의 계단이 눈에 띄게 달라진다.
3. 도감/컴패니언 스프라이트가 실제로 그려진다(Showdown에서 받아온다).
4. `ls ~/Library/Application\ Support/PokeDexBar/sprites` 에 캐시 파일이 쌓인다.
5. 기존 PokeTokenBar의 상태(`~/Library/Application Support/PokeTokenBar`)는 **변하지 않았다**.

- [ ] **Step 4: 9세대 스프라이트 실물 확인**

앱이 9세대를 뽑을 때까지 기다릴 수 없으므로 캐시에 직접 받아 눈으로 본다.

```bash
cd ~/Library/Application\ Support/PokeDexBar/sprites 2>/dev/null || mkdir -p ~/Library/Application\ Support/PokeDexBar/sprites && cd ~/Library/Application\ Support/PokeDexBar/sprites
curl -s -o 908-a.gif https://play.pokemonshowdown.com/sprites/ani/meowscarada.gif
open 908-a.gif
```
Expected: 마스카나(9세대)가 움직인다.

- [ ] **Step 5: README에 스프라이트 출처 추가**

`README.md` 의 크레딧/감사 부분에 다음 줄을 넣는다.

```markdown
- Sprites: [Pokémon Showdown](https://play.pokemonshowdown.com/sprites/) (animated and shiny, all generations)
```

- [ ] **Step 6: 커밋 · 푸시**

```bash
git add -A
git commit -m "docs: credit Showdown as the sprite source"
git push -u origin main
```

---

## 다음 사이클 (이 계획의 범위 밖)

2단계 — 경제 교체(재화 · 알 뽑기 · 시간 부화 · 슬롯 · 경험치 진화 · 중복 수집)는
`docs/superpowers/specs/2026-08-03-pokedexbar-design.md` 의 "2단계" 절에 설계가 있다.
그 작업이 `CompanionState`/`CompanionStore` 를 통째로 바꾸므로, 이번 계획에서는 그 두 파일을
리팩터링하지 않고 이름·상수·스프라이트 경로만 건드렸다.
