#!/bin/bash
# PokeDexBar.app 번들 조립 + /Applications 설치
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="1.8.0"
BUILD_DIR="build"
# 개발 빌드는 정식 설치본과 **나란히** 깔고 쓸 수 있어야 한다: PTB_DEV=1 이면 앱 이름·번들 ID·
# 실행 파일이 갈라지고, 앱은 CFBundleName 에서 저장 공간 이름을 뽑으므로(AppEnv.storageName)
# 세이브·사용량 캐시·로그가 자동으로 따로 간다. 안 그러면 둘이 같은 세이브를 덮어써서
# 시험 삼아 한 일이 실제 진행에 그대로 섞인다.
# 개발 빌드는 **디버그 구성**으로 짓는다 — `#if DEBUG` 시드 경로(PTB_SEED_RIBBON 등)가 살아 있어야
# 세이브를 손으로 고치지 않고 시험용 상태를 만들 수 있다. 봉인(SaveSeal)은 앱이 스스로 쓴 저장이라
# 정상이고, tampered 표시가 안 붙는다. 대신 디버그 바이너리라 **에너지·CPU 실측에는 쓰지 마라**
# (그 측정은 설치된 정식 앱으로만 — CLAUDE.md 의 메뉴바 idle 규율 참고).
if [[ "${PTB_DEV:-0}" == "1" ]]; then
    APP_NAME="PokeDexBar Dev"
    BUNDLE_ID="io.github.donky-ey.pokedexbar.dev"
    SWIFT_CONFIG="debug"
else
    APP_NAME="PokeDexBar"
    BUNDLE_ID="io.github.donky-ey.pokedexbar"
    SWIFT_CONFIG="release"
fi
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> swift build -c $SWIFT_CONFIG"
swift build -c "$SWIFT_CONFIG"

echo "==> $APP 조립"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$SWIFT_CONFIG/PokeDexBar" "$APP/Contents/MacOS/$APP_NAME"
# 심볼 strip — 릴리스 바이너리 1.84MB → 0.80MB(-57%). codesign 전에 수행(서명 무효화 방지).
# 디버그 빌드는 건드리지 않는다: 크기는 어차피 배포 대상이 아니고, 심볼을 지우면 크래시 로그가 안 읽힌다.
if [[ "$SWIFT_CONFIG" == "release" ]]; then
    strip -rSTx "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || strip -rSx "$APP/Contents/MacOS/$APP_NAME"
fi
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM 리소스 번들(showdown-slugs.json 등). SwiftPM 이 생성하는 resource_bundle_accessor.swift 는
# Bundle.module 을 Bundle.main.bundleURL 의 형제(= .app 루트, Contents/ 밖)에서 찾지만, 그 자리는 쓰지
# 않는다 — macOS codesign 이 .app 루트에 Contents/ 이외 콘텐츠가 있으면 서명 자체를 거부한다
# ("unsealed contents present in the bundle root", 빈 텍스트 파일 하나로도 재현됨. 실측: macOS 26.5).
# 그래서 서명 가능한 표준 위치인 Contents/Resources/ 밑에 넣는다 — SpeciesSlug.resourceURL() 이 배포
# .app(AppEnv.isBundledApp)에서는 Bundle.module 을 건드리지 않고 바로 이 자리를 찾는다. 번들이 없으면
# 배포본은 "알 수 없는 시작 크래시"(Bundle.module 의 fatalError)로 이어지므로 여기서 큰소리로 중단한다
# (조용히 깨진 앱을 만들지 않는다).
# 번들 이름은 SwiftPM 타깃 이름에서 나온다 — 앱 이름(개발 빌드는 "PokeDexBar Dev")이 아니라
# 항상 "PokeDexBar" 다. 런타임 조회(SpeciesSlug/RibbonIcon)도 이 이름을 그대로 찾는다.
RESOURCE_BUNDLE=".build/$SWIFT_CONFIG/PokeDexBar_PokeDexBar.bundle"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
    echo "   ✗ $RESOURCE_BUNDLE 없음 — swift build -c $SWIFT_CONFIG 가 리소스 번들을 못 만들었다. 중단." >&2
    exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# 크래시/OOM(exit≠0) 시 자동 재실행 LaunchAgent(KeepAlive) — SMAppService.agent 가 등록해 launchd 가
# 워치독으로 동작. 정상 종료(exit 0: 사용자 종료·업데이트)엔 재실행 안 함(SuccessfulExit=false).
# ProgramArguments 는 brew 설치 경로(/Applications) 고정. codesign 전에 생성해 서명 seal 에 포함.
mkdir -p "$APP/Contents/Library/LaunchAgents"
cat > "$APP/Contents/Library/LaunchAgents/$BUNDLE_ID.login.plist" <<AGENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$BUNDLE_ID.login</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key><false/>
    </dict>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
AGENT

echo "==> codesign"
SIGN_IDENTITY="${CODESIGN_IDENTITY:-PokeDexBar Local}"
# 안정적 Keychain ACL 을 위해서는 인증서 존재가 아니라 유효한 codesigning identity 가 필요하다.
if security find-identity -v -p codesigning | grep -F "\"$SIGN_IDENTITY\"" >/dev/null; then
    # 안정적 자체 서명 신원 → 재빌드해도 Keychain "항상 허용" 유지
    codesign --force -s "$SIGN_IDENTITY" "$APP"
else
    # 인증서 없음 → ad-hoc (빌드마다 cdhash 변경 = Keychain 재프롬프트 가능)
    if [[ "${PTB_REQUIRE_STABLE_SIGN:-0}" == "1" ]]; then
        # 릴리스 경로(release.sh 가 세팅). ad-hoc 릴리스는 사용자 Keychain 승인을 깨므로 절대 금지.
        echo "   ✗ PTB_REQUIRE_STABLE_SIGN=1 인데 '$SIGN_IDENTITY' 유효 identity 없음 → ad-hoc 금지, 중단." >&2
        echo "     ./scripts/create-signing-cert.sh 실행 후 다시 시도하세요." >&2
        exit 1
    fi
    echo "   ('$SIGN_IDENTITY' 유효 codesigning identity 없음 → ad-hoc 서명 — 로컬 개발용)"
    echo "   반복 Keychain 허용 프롬프트를 줄이려면 ./scripts/create-signing-cert.sh 실행 후 다시 빌드하세요."
    codesign --force -s - "$APP"
fi

# 설치는 **기본으로 하지 않는다.** 예전엔 늘 /Applications 에 복사했는데, 그러면 개발 빌드까지
# 정식 앱 자리에 쌓이고(중복 5개까지 갔다) Homebrew 로 받은 배포본을 로컬 빌드가 조용히 덮어써서
# "실사용 검증"이 성립하지 않는다. 정식 앱은 릴리스와 brew 로만 바뀌어야 한다.
#   PTB_INSTALL=1  → 개발 빌드는 ~/Applications, 정식 빌드는 /Applications 에 설치
if [[ "${PTB_INSTALL:-0}" == "1" ]]; then
    if [[ "${PTB_DEV:-0}" == "1" ]]; then
        DEST="$HOME/Applications"
    else
        DEST="/Applications"
    fi
    mkdir -p "$DEST"
    pkill -x "$APP_NAME" 2>/dev/null || true
    echo "==> $DEST 설치"
    if rm -rf "$DEST/$APP_NAME.app" 2>/dev/null && cp -R "$APP" "$DEST/" 2>/dev/null; then
        :
    elif ditto "$APP" "$DEST/$APP_NAME.app" 2>/dev/null; then
        # 빈 껍데기만 남은 경우 — 번들을 지우진 못해도 그 안에 쓰는 건 통과한다.
        codesign --force --deep --sign "${CODESIGN_IDENTITY:-PokeDexBar Local}" \
            "$DEST/$APP_NAME.app" >/dev/null 2>&1 || true
    else
        echo "   ⚠ $DEST 설치 실패(App Management 권한). 빌드 산출물은 정상: $APP"
    fi
    echo "완료: open \"$DEST/$APP_NAME.app\""
else
    echo "완료(설치 안 함): $APP"
    echo "   설치하려면: PTB_INSTALL=1 $0"
fi
