#!/bin/bash
# Rebuild the side-by-side "PokeTokenBar v3" app (1% economy + upstream merges, isolated save).
# Does not replace /Applications/PokeTokenBar.app or "PokeTokenBar v2.0.app".
#
#   ./scripts/rebuild-v3.sh                 # build current tree → v3
#   ./scripts/rebuild-v3.sh --pull-upstream # fetch+merge chattymin/PokeTokenBar, then build
#   ./scripts/rebuild-v3.sh --seed-from-v2  # copy v2.0 save into the v3 folder (refuses if v3 already has a save)
set -euo pipefail
cd "$(dirname "$0")/.."

PULL=0
SEED_FROM_V2=0
for arg in "$@"; do
    case "$arg" in
        --pull-upstream) PULL=1 ;;
        --seed-from-v2) SEED_FROM_V2=1 ;;
        -h|--help)
            sed -n '2,10p' "$0"
            exit 0
            ;;
        *)
            echo "unknown arg: $arg (try --help)" >&2
            exit 1
            ;;
    esac
done

if [[ "$PULL" == "1" ]]; then
    echo "==> fetch+merge upstream/main (official PokeTokenBar)"
    git fetch upstream
    git merge --no-edit upstream/main
fi

seed_from_v2() {
    local src="$HOME/Library/Application Support/PokeTokenBar v2.0"
    local dst="$HOME/Library/Application Support/PokeTokenBar v3"
    local original="$HOME/Library/Application Support/PokeTokenBar"

    if [[ ! -d "$src" ]]; then
        echo "no v2.0 save at $src — not seeding (refusing official save at $original)" >&2
        return 1
    fi
    if [[ -f "$dst/companion-state.json" ]]; then
        echo "v3 save already exists at $dst — leaving it alone (pass only on first install)"
        return 0
    fi
    echo "==> seed v3 save from v2.0 (not from official PokeTokenBar)"
    mkdir -p "$dst"
    rsync -a "$src/" "$dst/"
}

if [[ "$SEED_FROM_V2" == "1" ]]; then
    seed_from_v2
fi

if [[ -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
    export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH"
elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

export PTB_APP_NAME="PokeTokenBar v3"
export PTB_BUNDLE_ID="io.github.chattymin.poketokenbar.v3"
./scripts/build-app.sh

# First launch: copy v2.0 progress before the app creates an empty save.
if [[ ! -f "$HOME/Library/Application Support/PokeTokenBar v3/companion-state.json" ]]; then
    seed_from_v2 || true
fi

open "/Applications/PokeTokenBar v3.app"
echo "v3 save stays in ~/Library/Application Support/PokeTokenBar v3"
