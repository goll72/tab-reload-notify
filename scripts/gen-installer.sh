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
OUT_DIR="$REPO_ROOT/scripts/output/installers"

gen_installer() {
    TARGET=$1

    shift 2
    
    cd "$REPO_ROOT/native/notify-server" > /dev/null
    cargo "$@" --release --target $TARGET
    cd - > /dev/null

BANNER=$(cat <<EOF
Install script for notify-server, the native component
of the tab-reload-notify Firefox browser extension.

Built for: $TARGET
EOF
)
     
    case $TARGET in
        *-windows-*)
            cat <<XEOF > "$OUT_DIR/install-$TARGET.bat"
XEOF
        ;;
        *-apple-*)
            BINARY="$REPO_ROOT/native/notify-server/target/$TARGET/release/notify-server"

            cat <<XEOF > "$OUT_DIR/install-$TARGET.sh"
#!/bin/sh
XEOF
        ;;
        *)
            BINARY="$REPO_ROOT/native/notify-server/target/$TARGET/release/notify-server"
            
            cat <<XEOF > "$OUT_DIR/install-$TARGET.sh"
#!/bin/sh
$(echo "$BANNER" | sed "s/^/# /")

set -e

if [ \$# -eq 0 ]; then
    set -- --user
fi

while [ \$# -ne 0 ]; do
    case "\$1" in
        --user)
            NATIVE_MANIFEST_PATH="\$HOME/.mozilla/native-messaging-hosts/tab_reload_notify_server.json"
            SERVER_BINARY_PATH="\${XDG_BIN_HOME:-\$HOME/.local/bin}/tab-reload-notify/notify-server"
        ;;
        --system)
            UID=\$(id -u)

            if [ \$UID -ne 0 ]; then
                echo "Error: needs to be run as root when using \\\`--system'." >&2
                exit 1
            fi

            NATIVE_MANIFEST_PATH="/usr/lib/mozilla/native-messaging-hosts/tab_reload_notify_server.json"
            SERVER_BINARY_PATH="/usr/libexec/tab-reload-notify/notify-server"
        ;;
        *)
            cat <<EOF >&2
\$(basename "\$0") [ -h | --help | --user | --system ]

$BANNER

    -h | --help
        Show this help menu
    --user (default)
        Install for the current user profile only
    --system
        Install system-wide (needs to be run as root)
EOF

            [ "\$1" = "-h" ] || [ "\$1" = "--help" ]
            exit \$?
        ;;
    esac

    shift
done

TMPDIR=\$(mktemp -d)

trap 'rm -f "\$TMPDIR/notify-server" "\$TMPDIR/native-manifest.json"; rmdir "\$TMPDIR"' EXIT

tail -n +\$(sed -n "/^begin-base64/{ n; =; }" "\$0") "\$0" | uudecode | gzip -d > "\$TMPDIR/notify-server"

cat <<EOF > "\$TMPDIR/native-manifest.json"
$(cat "$REPO_ROOT/native/native-manifest.json.in" | sed "s:%SERVER_BINARY_PATH%:\$SERVER_BINARY_PATH:")
EOF

install -D -m644 "\$TMPDIR/native-manifest.json" "\$NATIVE_MANIFEST_PATH"
install -D -m755 "\$TMPDIR/notify-server" "\$SERVER_BINARY_PATH"

exit

# DO NOT EDIT ANYTHING BELOW THIS LINE!
# shellcheck disable=SC2317
$(cat "$BINARY" | gzip -9 | uuencode -m -)
XEOF
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
