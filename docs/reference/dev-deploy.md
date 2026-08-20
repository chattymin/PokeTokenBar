---
summary: "개발 빌드를 Mac·iPhone 실기기에 올리는 절차 — build-app.sh 함정(자격증명 없는 번들 = 크래시 루프), 디바이스 설치 명령, 검증 방법."
read_when:
  - "Mac에 올려줘", "폰에 올려줘", "실기기에 배포" 등 개발 빌드 실기기 설치를 요청받았을 때
  - 설치 후 앱이 크래시 루프(수 초마다 재시작)를 돌 때
  - Mac 설치본과 iPhone 설치본의 데이터 흐름(CloudKit/HTTP)을 검증할 때
  - 테스트가 기대와 다르게 실패했을 때(기지의 선례 목록)
---

# 개발 빌드 실기기 배포

릴리스 배포는 `release-workflow.md` 참조. 이 문서는 **개발 중 코드를 내 Mac과 iPhone에 올려
확인하는** 절차다. 두 설치본은 쌍으로 움직인다 — iPhone 앱은 Mac 이 올린 페이로드를 소비하므로
Mac 을 먼저 올리고 폰을 나중에 올린다.

## 1. Mac 설치 — build-app.sh 를 쓰지 않는다 (최우선 함정)

`scripts/build-app.sh` 는 SPM 산출물로 번들을 조립하는데 **codesign 에 자격증명(entitlements)을
주지 않는다.** iCloud container 자격증명이 없는 프로세스에서 `CloudKitSync.save()` 의
`CKContainer(identifier:)` 초기화가 SIGTRAP 으로 프로세스를 죽인다(2026-08-20 실측). launchd
KeepAlive 에이전트가 이를 계속 재실행하므로 **~8초 주기 크래시 루프**가 된다 — 루프의 잠깐
사이에 폰 서버(HTTP)가 살아 있어 "서버는 되는데 iCloud만 죽는다"로 오진하기 쉽다
(defect-log 동일 항목 참조). 개발 설치는 항상 Xcode 프로젝트 빌드:

```bash
xcodebuild -project PokeTokenBar.xcodeproj -scheme PokeTokenBar \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData build
```

- 종료는 `osascript -e 'quit app "PokeTokenBar"'` — `pkill` 을 쓰면 KeepAlive 에이전트가
  설치 도중에 앱을 재실행해 새 번들 복사와 경쟁한다.
- 설치: `rm -rf /Applications/PokeTokenBar.app && cp -R build/DerivedData/Build/Products/Release/PokeTokenBar.app /Applications/` 후 `open`.
- DerivedData 경로에서 그냥 실행하지 않는다 — 실행 중 번들이 Xcode rebuild 로 교체되면 cloudd가
  그 클라이언트를 영구히 파기한다(defect-log "번들 교체 → CloudKit 파기" 항목).
- 프로젝트에 파일을 추가했다면 먼저 `xcodegen generate`.

### 검증

```bash
pgrep -x PokeTokenBar                                   # 살아있는가 (10초 뒤에 재확인 — 크래시 루프 구분)
curl -s http://localhost:7845/stats | python3 -m json.tool   # 페이로드가 새 필드를 담는가
tail -20 ~/Library/Logs/PokeTokenBar.log                # "CloudKit sync failed" · "[CRASH]" 확인
```

페이로드 스키마를 바꿨다면(Bag/Collection 추가 때처럼) `curl` 로 해당 필드가 실제로 오는지
본다 — UI 가 비어 보이는 원인이 폰 코드인지 Mac 미전송인지 이 단계에서 갈린다.

## 2. iPhone 설치

```bash
xcrun devicectl list devices                            # 연결 확인 → Identifier 확보
xcodebuild -project PokeTokenBar.xcodeproj -scheme PokeTokenBariOS \
  -configuration Release -destination 'id=<DEVICE-UUID>' \
  -derivedDataPath build/DerivedDataiOS -allowProvisioningUpdates build
xcrun devicectl device install app --device <DEVICE-UUID> \
  build/DerivedDataiOS/Build/Products/Release-iphoneos/PokeTokenBar.app
xcrun devicectl device process launch --device <DEVICE-UUID> com.poketokenbar.ios
```

- `-allowProvisioningUpdates` 필수 — Apple Development 자동 서명 + 프로비저닝을 xcodebuild 가
  해결한다.
- `process launch` 는 **폰이 잠겨 있으면 실패한다**(FBSOpenApplicationErrorDomain 7). 설치는
  되므로 잠금 해제 후 아이콘 탭으로 충분하다.
- 폰 앱 데이터 소스 우선순위: iCloud(동일 Apple ID) → 로컬 HTTP(`store.host` 설정 시). Mac
  설치본이 CloudKit 게시를 하고 있으므로 보통 iCloud 로 도달한다.

## 3. 기지의 선례 (원인 추적 전에 확인)

실패가 *이번 변경* 때문인지 환경/선례인지 먼저 가른다 — 새로 고친 결함의 5-whys 에서
"내 변경 vs 환경" 구분에 시간이 가장 많이 든다.

- **Hermes 타임존 테스트.** `testHermesAcceptsMillisecondStartedAt` 은 UTC 자정 시각의
  local-day 문자열을 기대해 UTC 보다 느린 시간대에서 실패한다. `main` 에서도 실패하는 기지
  결함 — 무시하고 진행해도 된다(수정은 별도 과제).
- **`build-app.sh`/`release.sh` 경로의 잠복 결함.** 두 스크립트 산출물은 자격증명이 없어
  CloudKit 시대의 릴리스가 나가면 전 사용자 크래시 루프가 된다. 다음 릴리스 전에 스크립트에
  entitlements 서명을 추가해야 한다(릴리스 게이트와 무관하게 존재하는 빚).
- **`PokeTokenBar Local` 서명 인증서 소실 시** `security find-identity -v -p codesigning` 으로
  확인 → `./scripts/create-signing-cert.sh` 재생성 → `release.sh` 의 `EXPECTED_LEAF` 갱신.
