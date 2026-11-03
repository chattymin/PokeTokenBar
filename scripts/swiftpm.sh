#!/usr/bin/env bash
# Use SwiftPM with the selected Apple toolchain.
# CLT's macOS 27 SDK makes SwiftUI @State a macro but omits its SwiftUIMacros plugin;
# the CLT macOS 26 SDK keeps @State as a property wrapper and builds without Xcode.
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <build|test|run> [SwiftPM options...]" >&2
    exit 2
fi

ACTION="$1"
shift
case "$ACTION" in
    build|test|run) ;;
    *) echo "Unsupported SwiftPM action: $ACTION (use build, test, or run)" >&2; exit 2 ;;
esac

HAS_EXPLICIT_SDK=0
for argument in "$@"; do
    if [[ "$argument" == "--sdk" || "$argument" == --sdk=* ]]; then
        HAS_EXPLICIT_SDK=1
        break
    fi
done

SDK_ARGS=()
ACTIVE_DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select --print-path 2>/dev/null || true)}"
if [[ "$HAS_EXPLICIT_SDK" == "0" && "$ACTIVE_DEVELOPER_DIR" == "/Library/Developer/CommandLineTools" ]]; then
    CLT_MACOS26_SDK="$ACTIVE_DEVELOPER_DIR/SDKs/MacOSX26.sdk"
    if [[ ! -d "$CLT_MACOS26_SDK" ]]; then
        echo "The selected Command Line Tools have no macOS 26 SDK." >&2
        echo "The macOS 27 SDK needs SwiftUIMacros from Xcode; install a CLT package with macOS 26 SDK or select full Xcode." >&2
        exit 1
    fi
    SDK_ARGS=(--sdk "$CLT_MACOS26_SDK")
fi

exec swift "$ACTION" "${SDK_ARGS[@]}" "$@"
