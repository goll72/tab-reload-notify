#!/bin/sh
# Downloads VM images and runs virtual machines with additional set up
# so they can be used as testbeds for the extension.
# 
# Dependencies: `quickget`, `quickemu`

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)
OUT_DIR="$REPO_ROOT/scripts/output/vms"

mkdir -p "$OUT_DIR"

. "$REPO_ROOT/scripts/common.sh"

ARCH=$(uname -m)

case "$ARCH" in
    x86_64|aarch64)
    ;;
    *)
        echo "Unsupported architecture: $ARCH" >&2
        exit 1
    ;;
esac

cd "$OUT_DIR"

case "$1" in
    --download)
        [ -f alpine-v3.23.conf ] || quickget alpine v3.23
        [ -f macos-tahoe.conf ] || quickget macos tahoe
        [ -f freebsd-15.0-disc1.conf ] || quickget freebsd 15.0 disc1
        [ -f windows-10.conf ] || quickget windows 10
    ;;
    --run)
        case "$2" in
            $ARCH-unknown-linux-musl)
                quickemu --vm alpine-v3.23.conf --serial telnet --display none --viewer none
            ;;
            $ARCH-unknwon-freebsd)
                quickemu --vm freebsd-15.0-disc1.conf --serial telnet --display none --viewer none
            ;;
            $ARCH-apple-darwin)
                quickemu --vm macos-tahoe.conf --serial telnet
            ;;
            $ARCH-pc-windows-msvc)
                quickemu --vm windows-10.conf --serial telnet
            ;;
            *)
                echo "Unsupported target: $2" >&2
            ;;
        esac 
    ;;
    *)
        cat <<EOF >&2
Usage: $(basename "$0") [ -h | --help | --download | --run <TARGET> ]

Downloads VM images and runs virtual machines with additional set up
so they can be used as testbeds for the extension.

    -h | --help
        Show this help menu

    --download
        Download the VM images

    --run <TARGET>
        Run a virtual machine appropriate for testing TARGET.

        Supported targets:
            $ARCH-unknown-linux-musl
            $ARCH-unknwon-freebsd
            $ARCH-apple-darwin
            $ARCH-pc-windows-msvc
EOF
        [ "$1" = "-h" ] || [ "$1" = "--help" ]
        exit $?
    ;;
esac
