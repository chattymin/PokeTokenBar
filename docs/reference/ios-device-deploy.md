---
summary: "iOS 앱을 실기기(아이폰)에 빌드·설치·실행하는 절차와 함정."
read_when:
  - 사용자가 "폰에 푸시해줘", "폰에 올려줘", "내 아이폰에 배포" 따위로 iOS 실기기 배포를 요청할 때
  - 기기 빌드 서명·프로비저닝 오류를 만났을 때
---

# iOS 실기기 배포 (아이폰)

사용자가 아이폰에 앱을 올려달라고 하면 한 줄 명령을 시키지 말고 직접 수행한다.
대상은 항상 **main** 워킹카피 (머지 완료된 코드만 기기에 올린다).

## 절차

1. **기기 확인** — USB 연결 + 신뢰됨 상태인지:

   ```bash
   xcrun devicectl list devices
   ```

   `connected` 인 기기의 `Identifier`(UUID) 를 다음 단계에 쓴다. 없으면 사용자에게 연결 요청.

2. **main 동기화** — `git checkout main && git pull --ff-only origin main`

3. **빌드** (자동 서명, 프로비저닝 갱신 허용):

   ```bash
   xcodebuild -project PokeTokenBar.xcodeproj -scheme PokeTokenBariOS \
     -destination 'id=<기기 UUID>' -derivedDataPath build/ios-device \
     -allowProvisioningUpdates build
   ```

   산출물: `build/ios-device/Build/Products/Debug-iphoneos/PokeTokenBar.app`
   (위젯 익스텐션은 .app 안에 포함된다 — PokeTokenBariOS 스킴이 의존 포함.)

4. **설치 · 실행**:

   ```bash
   xcrun devicectl device install app --device <기기 UUID> \
     "build/ios-device/Build/Products/Debug-iphoneos/PokeTokenBar.app"
   xcrun devicectl device process launch --device <기기 UUID> com.poketokenbar.ios
   ```

## 함정

- **서명은 xcodebuild 자동 서명(팀 B2G47QWXN7)으로.** iCloud 동기화는 iCloud container
  자격증명이 필요한데 `build-app.sh` 류의 수동 codesign 에는 그 자격증명이 없다 — 폰에서
  HTTP 는 되고 iCloud 만 조용히 죽는 빌드가 나온다 (defect-log §외부 동기화 같은 부류).
- 첫 기기 빌드는 기기가 개발자 팀에 등록돼 있어야 한다 (`-allowProvisioningUpdates` 가
  등록까지 처리). 아이폰의 개발자 모드(Developer Mode) 가 꺼져 있으면 기기에서 켜야 한다.
- `-destination 'generic/platform=iOS'` 로 빌드하면 서명 없는 산출물이 나와 설치가
  실패한다 — 실기기 UUID 를 지정한다.
