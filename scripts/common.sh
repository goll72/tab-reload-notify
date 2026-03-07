# shellcheck shell=sh

AUX_DIR="$REPO_ROOT/scripts/aux"

INST_OUT_DIR="$REPO_ROOT/scripts/output/installers"
VM_OUT_DIR="$REPO_ROOT/scripts/output/vms"

SHARED_DIR="$REPO_ROOT/scripts/output/shared"

[ -n "${ZIG_TARGETS+1}" ] || ZIG_TARGETS="
    x86_64-unknown-linux-gnu x86_64-unknown-linux-musl
    aarch64-unknown-linux-gnu aarch64-unknown-linux-musl
    x86_64-unknown-freebsd x86_64-unknown-netbsd
"

[ -n "${ZIG_XCODE_TARGETS+1}" ] || ZIG_XCODE_TARGETS="x86_64-apple-darwin aarch64-apple-darwin"

[ -n "${XWIN_TARGETS+1}" ] || XWIN_TARGETS="x86_64-pc-windows-msvc aarch64-pc-windows-msvc"
