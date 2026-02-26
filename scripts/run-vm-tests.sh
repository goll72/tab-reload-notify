#!/bin/sh
# Downloads VM images and runs virtual machines with additional
# setup so they can be used as testbeds for the extension.
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
        [ -f freebsd-15.0-disc1.conf ] || quickget freebsd 15.0 disc1
        [ -f macos-sequoia.conf ] || quickget macos sequoia
        [ -f windows-10.conf ] || quickget windows 10

        cat <<EOF
The following VM images have been installed to \`$OUT_DIR':

    alpine-v3.23.conf         ->   $ARCH-unknown-linux-musl
    freebsd-15.0-disc1.conf   ->   $ARCH-unknown-freebsd
    macos-sequoia.conf        ->   $ARCH-apple-darwin
    windows-10.conf           ->   $ARCH-pc-windows-msvc

You will need to run each one of them individually using \`quickemu --vm', go
through the installation process and then comment out the \`iso=' line in the
respective \`.conf' file before running \`$(basename "$0") --run'.

You should also run \`$(basename "$0") --save' so you
can restore the VM images in case something goes wrong.
EOF
    ;;
    --save)
        if [ -f "$OUT_DIR/saved.flag" ]; then
            echo "\`$(basename "$0") --save' has been run already! Delete \`$OUT_DIR/saved.flag' if you want to overwrite the images that have been saved." >&2
            exit 1
        fi

        for i in "$OUT_DIR"/*/disk.qcow2; do
            cp --reflink=always "$i" "$i.bak"
        done

        touch "$OUT_DIR/saved.flag"
    ;;
    --restore)
        for i in "$OUT_DIR"/*/disk.qcow2.bak; do
            cp "$i" "${i%.bak}"
        done
    ;;
    --run)
        case "$2" in
            $ARCH-unknown-linux-musl)
                quickemu --vm alpine-v3.23.conf --serial telnet --display none
            ;;
            $ARCH-unknown-freebsd)
                quickemu --vm freebsd-15.0-disc1.conf --serial telnet --display none
            ;;
            $ARCH-apple-darwin)
                quickemu --vm macos-sequoia.conf --serial telnet
                # NOTE: `sudo /usr/libexec/getty - tty.serial1`
            ;;
            $ARCH-pc-windows-msvc)
                quickemu --vm windows-10.conf --serial telnet
                # NOTE: `ssh -p 22220 user@localhost`
            ;;
            "")
                echo "You need to specify a target to run." >&2
                exit 1
            ;;
            *)
                echo "Unsupported target: $2" >&2
                exit 1
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

    --save
        Save the VM images in their current state

    --restore
        Restore the VM images to their last saved state

    --run <TARGET>
        Run a virtual machine appropriate for testing TARGET

        Supported targets:
            $ARCH-unknown-linux-musl
            $ARCH-unknown-freebsd
            $ARCH-apple-darwin
            $ARCH-pc-windows-msvc
EOF
        [ "$1" = "-h" ] || [ "$1" = "--help" ]
        exit $?
    ;;
esac
