#!/bin/bash
# 코드서명용 자체 서명(self-signed) 인증서를 login keychain 에 1회 생성한다.
# 목적: 안정적 서명 신원 → 재빌드해도 Keychain "항상 허용"이 유지됨 (ad-hoc 은 빌드마다 무효화).
# 개인키/인증서는 keychain 에만 저장되며 레포에 절대 커밋하지 않는다.
set -euo pipefail

IDENTITY="PokeDexBar Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

identity_is_valid() {
    security find-identity -v -p codesigning | grep -F "\"$IDENTITY\"" >/dev/null
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if identity_is_valid; then
    echo "이미 유효함: '$IDENTITY' — 재생성하지 않음 (재생성 시 기존 서명과 불일치)"
    exit 0
fi

# 인증서가 있지만 trust 설정만 빠진 상태면 재생성하지 않고 기존 인증서를 codesign 용도로 trust 한다.
if security find-certificate -c "$IDENTITY" -p "$KEYCHAIN" > "$TMP/existing-cert.pem" 2>/dev/null \
    && [ -s "$TMP/existing-cert.pem" ]; then
    echo "==> 기존 '$IDENTITY' 인증서를 code signing 용도로 trust"
    security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/existing-cert.pem" 2>/dev/null || true
    if identity_is_valid; then
        echo "'$IDENTITY' 유효 codesigning identity 확인됨"
        exit 0
    fi
    echo "기존 '$IDENTITY' 인증서가 있지만 유효한 codesigning identity 가 아닙니다."
    echo "Keychain Access 에서 '$IDENTITY' 인증서/개인키를 삭제한 뒤 이 스크립트를 다시 실행하세요."
    exit 1
fi

# macOS 기본 LibreSSL 사용 — Homebrew OpenSSL 3 의 p12 는 -legacy 없이는 security 가 못 읽음
OPENSSL=/usr/bin/openssl
# p12 전송용 임시 암호 (즉시 import 후 파일 삭제 — 보안 의미 없음, 빈 암호는 MAC 검증 실패 회피용)
P12PW="pokedexbar"

cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

echo "==> self-signed 코드서명 인증서 생성"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -config "$TMP/openssl.cnf" 2>/dev/null

"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$IDENTITY" -out "$TMP/identity.p12" -passout pass:"$P12PW" 2>/dev/null

echo "==> login keychain 에 import (codesign 사용 허용)"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12PW" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" 2>/dev/null || true

echo "완료."
identity_is_valid \
    && echo "'$IDENTITY' 유효 codesigning identity 확인됨" \
    || echo "경고: 유효 codesigning identity 확인 실패"
echo
echo "다음: ./scripts/build-app.sh 가 이 신원으로 서명합니다."
echo "첫 빌드 시 'codesign 이 키를 사용하려 함' 프롬프트가 1회 뜨면 '항상 허용'을 누르세요."
