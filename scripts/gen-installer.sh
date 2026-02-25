#!/bin/sh
#
# Generates installer scripts for the extension's native component.
#
# To run this script, you will need to install all of the targets
# mentioned using `rustup`, as well as `zig`, `cargo-zigbuild`,
# `cargo-xwin` and a macOS Xcode SDK.

: ${MACOS_SDKROOT:=/opt/xcode/sdk}

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)

gen_installer() {
    TARGET=$1

    shift 2
    
    pushd "$REPO_ROOT/native/notify-server"
    cargo "$@" --release --target $TARGET
    popd
     
    case $TARGET in
        *-windows-*)
            cat <<EOF > install-$TARGET.bat
EOF
        ;;
        *-apple-*)
            cat <<EOF > install-$TARGET.sh
#!/bin/sh
EOF
        ;;
        *)
            cat <<EOF > install-$TARGET.sh
#!/bin/sh


EOF
        ;;
    esac
}

ZIG_TARGETS="
    x86_64-unknown-linux-gnu x86_64-unknown-linux-musl
    aarch64-unknown-linux-gnu aarch64-unknown-linux-musl
    x86_64-unknown-freebsd
"

ZIG_XCODE_TARGETS="x86_64-apple-darwin aarch64-apple-darwin"

XWIN_TARGETS="x86_64-pc-windows-msvc aarch64-pc-windows-msvc"

for target in $ZIG_TARGETS; do
    gen_installer $target -- zigbuild
done

export SDKROOT=$MACOS_SDKROOT
for target in $ZIG_XCODE_TARGETS; do
    gen_installer $target -- zigbuild
done
unset SDKROOT

for target in $XWIN_TARGETS; do
    gen_installer $target -- xwin build
done
