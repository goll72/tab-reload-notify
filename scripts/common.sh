# shellcheck shell=sh

VERSION=$(jq --raw-output '.version' < "$REPO_ROOT/src/manifest.json")

AUX_DIR="$REPO_ROOT/scripts/aux"

INST_OUT_DIR="$REPO_ROOT/scripts/output/installers"
VM_OUT_DIR="$REPO_ROOT/scripts/output/vms"

SHARED_DIR="$REPO_ROOT/scripts/output/shared"

ZIG_TARGETS="
    x86_64-unknown-linux-gnu x86_64-unknown-linux-musl
    aarch64-unknown-linux-gnu aarch64-unknown-linux-musl
    x86_64-unknown-freebsd
"

ZIG_XCODE_TARGETS="x86_64-apple-darwin aarch64-apple-darwin"

XWIN_TARGETS="x86_64-pc-windows-msvc aarch64-pc-windows-msvc"

ALL_TARGETS="$ZIG_TARGETS $ZIG_XCODE_TARGETS $XWIN_TARGETS"
