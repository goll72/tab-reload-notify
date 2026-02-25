# shellcheck shell=sh

REPO_ROOT=$(git rev-parse --show-toplevel)
OUT_DIR="$REPO_ROOT/scripts/output/installers"

ZIG_TARGETS="
    x86_64-unknown-linux-gnu x86_64-unknown-linux-musl
    aarch64-unknown-linux-gnu aarch64-unknown-linux-musl
    x86_64-unknown-freebsd
"

ZIG_XCODE_TARGETS="x86_64-apple-darwin aarch64-apple-darwin"

XWIN_TARGETS="x86_64-pc-windows-msvc aarch64-pc-windows-msvc"

ALL_TARGETS="$ZIG_TARGETS $ZIG_XCODE_TARGETS $XWIN_TARGETS"
