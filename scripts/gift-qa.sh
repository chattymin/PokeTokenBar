#!/usr/bin/env bash
# Run two isolated PokeTokenBar app bundles on one Mac for Bonjour gift QA.
set -euo pipefail
cd "$(dirname "$0")/.."

QA_ROOT="$(mktemp -d /private/tmp/poketokenbar-gift-qa.XXXXXX)"
SENDER_APP="$QA_ROOT/PokeTokenBar-Sender.app"
RECEIVER_APP="$QA_ROOT/PokeTokenBar-Receiver.app"
SENDER_STATE="$QA_ROOT/sender-state"
RECEIVER_STATE="$QA_ROOT/receiver-state"
SENDER_PID=""
RECEIVER_PID=""

cleanup() {
  [[ -z "$SENDER_PID" ]] || kill "$SENDER_PID" 2>/dev/null || true
  [[ -z "$RECEIVER_PID" ]] || kill "$RECEIVER_PID" 2>/dev/null || true
  [[ -z "$QA_ROOT" ]] || rm -rf "$QA_ROOT"
}
trap cleanup EXIT INT TERM

echo "==> Building debug binary"
swift build

make_bundle() {
  local app="$1"
  local bundle_id="$2"
  local display_name="$3"
  mkdir -p "$app/Contents/MacOS"
  cp .build/debug/PokeTokenBar "$app/Contents/MacOS/PokeTokenBar"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$bundle_id</string>
    <key>CFBundleName</key><string>$display_name</string>
    <key>CFBundleDisplayName</key><string>$display_name</string>
    <key>CFBundleExecutable</key><string>PokeTokenBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSLocalNetworkUsageDescription</key><string>Find the other local gift QA instance.</string>
    <key>NSBonjourServices</key>
    <array><string>_poketokenbar._tcp</string></array>
</dict>
</plist>
PLIST
  codesign --force -s - "$app" >/dev/null
}

make_bundle "$SENDER_APP" "io.github.chattymin.poketokenbar.gift-qa.sender" "PokeTokenBar Sender"
make_bundle "$RECEIVER_APP" "io.github.chattymin.poketokenbar.gift-qa.receiver" "PokeTokenBar Receiver"

mkdir -p "$SENDER_STATE" "$RECEIVER_STATE"
cat > "$SENDER_STATE/companion-state.json" <<'JSON'
{"installBaselineSet":true,"usedSinceInstall":5000000000,"spentTokens":0,"lastDate":"qa","dex":[],"collectedFinals":[],"language":"ko"}
JSON
cat > "$RECEIVER_STATE/companion-state.json" <<'JSON'
{"installBaselineSet":true,"usedSinceInstall":0,"spentTokens":0,"lastDate":"qa","dex":[],"collectedFinals":[],"language":"ko"}
JSON

echo "==> Starting isolated sender and receiver"
PTB_STATE_DIR="$SENDER_STATE" "$SENDER_APP/Contents/MacOS/PokeTokenBar" &
SENDER_PID=$!
PTB_STATE_DIR="$RECEIVER_STATE" "$RECEIVER_APP/Contents/MacOS/PokeTokenBar" &
RECEIVER_PID=$!

echo
echo "Two menu-bar instances are running."
echo "  Sender:   5B spendable tokens"
echo "  Receiver: 0 spendable tokens"
echo "Open each Shop tab, create a gift on Sender, and enter its code on Receiver."
echo "Press Ctrl-C here to stop both instances and remove the isolated QA data."
wait
