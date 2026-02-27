#!/bin/sh
# Generates installer scripts for the extension's native component.
#
# To run this script, you will need to install all of the targets listed in
# `common.sh` using `rustup`, as well as `zig`, `cargo-zigbuild`,`cargo-xwin`,
# a macOS Xcode SDK, `gzip` and `base64`.

: "${MACOS_SDKROOT:=/opt/xcode/sdk}"

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)

. "$REPO_ROOT/scripts/common.sh"

OUT_DIR="$INST_OUT_DIR"
mkdir -p "$OUT_DIR"

gen_installer_win() {
    cat <<XEOF > "$OUT_DIR/install-$TARGET.ps1"
XEOF
}

gen_installer_nix() {
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
            NATIVE_MANIFEST_PATH="$USER_NATIVE_MANIFEST_PATH"
            SERVER_BINARY_PATH="$USER_SERVER_BINARY_PATH"
        ;;
        --system)
            UID=\$(id -u)

            if [ \$UID -ne 0 ]; then
                echo "Error: needs to be run as root when using \\\`--system'." >&2
                exit 1
            fi

            NATIVE_MANIFEST_PATH="$SYSTEM_NATIVE_MANIFEST_PATH"
            SERVER_BINARY_PATH="$SYSTEM_SERVER_BINARY_PATH"
        ;;
        *)
            cat <<EOF >&2
Usage: \$(basename "\$0") [ -h | --help | --user | --system ]

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

tail -n +\$(sed -n "/^BEGIN_BASE64_ENCODED_DATA/{ n; =; }" "\$0") "\$0" | base64 -d | gzip -d > "\$TMPDIR/notify-server"

cat <<EOF > "\$TMPDIR/native-manifest.json"
$(cat "$REPO_ROOT/native/native-manifest.json.in" | sed "s:%SERVER_BINARY_PATH%:\$SERVER_BINARY_PATH:")
EOF

install -D -m644 "\$TMPDIR/native-manifest.json" "\$NATIVE_MANIFEST_PATH"
install -D -m755 "\$TMPDIR/notify-server" "\$SERVER_BINARY_PATH"

exit

# DO NOT EDIT ANYTHING BELOW THIS LINE!
BEGIN_BASE64_ENCODED_DATA
$(cat "$BINARY" | gzip -9 | base64 | fold -s -b -w 80)
XEOF
}

gen_installer() {
    TARGET=$1

    shift 2
    
    cd "$REPO_ROOT/native/notify-server" > /dev/null
    cargo "$@" --release --target "$TARGET"
    cd - > /dev/null

BANNER=$(cat <<EOF
Install script for notify-server, the native component
of the tab-reload-notify Firefox browser extension.

Built for: $TARGET
EOF
)
     
    case $TARGET in
        *-windows-*)
            BINARY="$REPO_ROOT/native/notify-server/target/$TARGET/release/notify-server.exe"

            gen_installer_win
        ;;
        *-apple-*)
            # XXX: I have no idea if this works (probably not)
            BINARY="$REPO_ROOT/native/notify-server/target/$TARGET/release/notify-server"
            
            USER_NATIVE_MANIFEST_PATH="\$HOME/Library/Application Support/Mozilla/NativeMessagingHosts/tab_reload_notify_server.json" \
            USER_SERVER_BINARY_PATH="\$HOME/Library/Application Support/tab-reload-notify/notify-server" \
            SYSTEM_NATIVE_MANIFEST_PATH="/Library/Application Support/Mozilla/NativeMessagingHosts/tab_reload_notify_server.json" \
            SYSTEM_SERVER_BINARY_PATH="/Library/Application Support/tab-reload-notify/notify-server" \
                gen_installer_nix
        ;;
        *)
            BINARY="$REPO_ROOT/native/notify-server/target/$TARGET/release/notify-server"
            
            USER_NATIVE_MANIFEST_PATH="\$HOME/.mozilla/native-messaging-hosts/tab_reload_notify_server.json" \
            USER_SERVER_BINARY_PATH="\${XDG_BIN_HOME:-\$HOME/.local/bin}/tab-reload-notify/notify-server" \
            SYSTEM_NATIVE_MANIFEST_PATH="/usr/lib/mozilla/native-messaging-hosts/tab_reload_notify_server.json" \
            SYSTEM_SERVER_BINARY_PATH="/usr/libexec/tab-reload-notify/notify-server" \
                gen_installer_nix
        ;;
    esac
}

if [ -n "$1" ]; then
    cat <<EOF >&2
Usage: $(basename "$0")

Generates installer scripts for the extension's native component.
EOF

    exit 1
fi

for target in $ZIG_TARGETS; do
    gen_installer "$target" -- zigbuild
done

export SDKROOT="$MACOS_SDKROOT"
for target in $ZIG_XCODE_TARGETS; do
    gen_installer "$target" -- zigbuild
done
unset SDKROOT

for target in $XWIN_TARGETS; do
    gen_installer "$target" -- xwin build
done
