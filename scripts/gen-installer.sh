#!/usr/bin/env bash
# Generates install scripts for the extension's native component.
#
# To run this script, you will need to install the targets listed in
# `common.sh` using `rustup`, as well as `zig`, `cargo-zigbuild`
# (from https://github.com/goll72/cargo-zigbuild-netbsd), `cargo-xwin`,
# a macOS Xcode SDK, `zip`, `gzip` and `base64`.

: "${MACOS_SDKROOT:=/opt/xcode/sdk}"

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)

. "$REPO_ROOT/scripts/common.sh"

OUT_DIR="$INST_OUT_DIR"
mkdir -p "$OUT_DIR"

. "$REPO_ROOT/.env"

gen_installer_win() {
    NATIVE_MANIFEST=$(< "$REPO_ROOT/native/native-manifest.json.in")
    NATIVE_MANIFEST="${NATIVE_MANIFEST/"%SERVER_BINARY_PATH%"/notify-server.exe}"

    INSTALL_SCRIPT=$(< "$AUX_DIR/install-win.ps1")
    INSTALL_SCRIPT="${INSTALL_SCRIPT/"%B64_ZIP_DATA%"/$(zip -9 -j - "$BINARY" | base64)}"
    INSTALL_SCRIPT="${INSTALL_SCRIPT/"%NATIVE_MANIFEST%"/$NATIVE_MANIFEST}"
    INSTALL_SCRIPT="${INSTALL_SCRIPT/"%FF_EXT_ID%"/$FF_EXT_ID}"
    INSTALL_SCRIPT="${INSTALL_SCRIPT/"%CHROME_EXT_ID%"/"chrome-extension://$CHROME_EXT_ID/"}"

    cat <<< "$INSTALL_SCRIPT" > "$OUT_DIR/install-$TARGET.ps1"
}

gen_installer_nix() {
    NATIVE_MANIFEST_NAME=tab_reload_notify_server.json

    cat <<XEOF > "$OUT_DIR/install-$TARGET.sh"
#!/bin/sh
$(sed "s/^/# /" <<< "$BANNER")

[ -z "\${FIREFOX+1}\${CHROME+1}\${CHROME_FOR_TESTING+1}\${CHROMIUM+1}" ] && ALL=1

set -e

set -- --user "\$@"

install_or_uninstall() {
    MODE=\$1
    SRC=\$2
    DEST=\$3
    
    if [ -n "\$UNINSTALL" ]; then
        rm -f "\$DEST"
    else
        mkdir -p "\$(dirname "\$DEST")"
        install -m "\$MODE" "\$SRC" "\$DESTDIR\$DEST"
    fi
}

$(
    case "$TARGET" in
        *-freebsd|*-netbsd)
            cat <<EOF
: "\${PREFIX:=/usr/local}"
EOF
        ;;
        *-linux-*)
            cat <<EOF
: "\${PREFIX:=/usr/local}"

FIREFOX_LIB_PREFIX=/usr/lib
[ -n "\$LIB64" ] || [ -d "\$DESTDIR/usr/lib64" ] && FIREFOX_LIB_PREFIX=/usr/lib64
EOF
        ;;
    esac
)

while [ \$# -ne 0 ]; do
    case "\$1" in
        --user)
            NATIVE_MANIFEST_DIR_FIREFOX="$USER_NATIVE_MANIFEST_DIR_FF"
            NATIVE_MANIFEST_DIR_CHROME="${USER_NATIVE_MANIFEST_DIR_CHROME/"%CHROME%"/$USER_CHROME_PLACEHOLDER}"
            NATIVE_MANIFEST_DIR_CHROME_FOR_TESTING="${USER_NATIVE_MANIFEST_DIR_CHROME/"%CHROME%"/$USER_CHROME_FOR_TESTING_PLACEHOLDER}"
            NATIVE_MANIFEST_DIR_CHROMIUM="${USER_NATIVE_MANIFEST_DIR_CHROME/"%CHROME%"/$USER_CHROMIUM_PLACEHOLDER}"
            
            SERVER_BINARY_PATH="$USER_SERVER_BINARY_PATH"
        ;;
        --system)
            if [ \$(id -u) -ne 0 ]; then
                echo "Error: needs to be run as root when using \\\`--system'." >&2
                exit 1
            fi

            NATIVE_MANIFEST_DIR_FIREFOX="$SYSTEM_NATIVE_MANIFEST_DIR_FF"
            NATIVE_MANIFEST_DIR_CHROME="${SYSTEM_NATIVE_MANIFEST_DIR_CHROME/"%CHROME%"/$SYSTEM_CHROME_PLACEHOLDER}"
            NATIVE_MANIFEST_DIR_CHROME_FOR_TESTING="${SYSTEM_NATIVE_MANIFEST_DIR_CHROME/"%CHROME%"/$SYSTEM_CHROME_FOR_TESTING_PLACEHOLDER}"
            NATIVE_MANIFEST_DIR_CHROMIUM="${SYSTEM_NATIVE_MANIFEST_DIR_CHROME/"%CHROME%"/$SYSTEM_CHROMIUM_PLACEHOLDER}"
            
            SERVER_BINARY_PATH="$SYSTEM_SERVER_BINARY_PATH"
        ;;
        --uninstall)
            UNINSTALL=1
        ;;
        *)
            cat <<EOF >&2
Usage: \$(basename "\$0") [ -h | --help ] [ --user | --system ] [ --uninstall ]

$BANNER

    -h, --help
        Show this help menu
    --user (default)
        Perform the operation for the current user profile only
    --system
        Perform the operation system-wide (needs to be run as root)
    --uninstall
        Rather than installing the component (default), uninstall it

Environment Variables

    FIREFOX, CHROME, CHROME_FOR_TESTING, CHROMIUM
        By default, the native component will be installed for all supported
        browsers. If you want to install it only for some browsers, set the
        corresponding variable for each browser upon running the script, e.g.

            \\\`FIREFOX=1 \$(basename "\$0")'

    DESTDIR
        (\\\`--system' only) Used for staged installs.

        Current value: DESTDIR="\$DESTDIR"

    PREFIX
        (\\\`--system' only) Set the installation prefix.

        Current value: PREFIX="\$PREFIX"
$(
    case "$TARGET" in
        *-linux-*)
            cat <<EOF

    LIB64 
        (Linux targets only) Force the Firefox prefix path used
        for native manifest installation to be \\\`/usr/lib64',
        skipping auto-detection logic.

        Current value: \${LIB64+LIB64=}\${LIB64-"(LIB64 is unset)"}
EOF
        ;;
    esac
)
EOF

            [ "\$1" = "-h" ] || [ "\$1" = "--help" ]
            exit \$?
        ;;
    esac

    shift
done

TMPDIR=\$(mktemp -d)

trap 'rm -f "\$TMPDIR"/notify-server "\$TMPDIR"/*.json "\$TMPDIR"/*.json.in; rmdir "\$TMPDIR"' EXIT

tail -n +\$(sed -n "/^BEGIN_BASE64_ENCODED_DATA/{ n; =; }" "\$0") "\$0" | base64 -d | gzip -d > "\$TMPDIR/notify-server"

cat <<EOF > "\$TMPDIR/native-manifest.json.in"
$(sed "s:%SERVER_BINARY_PATH%:\$SERVER_BINARY_PATH:" < "$REPO_ROOT/native/native-manifest.json.in")
EOF

sed "s;%ALLOWED%;\"allowed_extensions\": [\"$FF_EXT_ID\"];" < "\$TMPDIR/native-manifest.json.in" > "\$TMPDIR/native-manifest.firefox.json"
sed "s;%ALLOWED%;\"allowed_origins\": [\"chrome-extension://$CHROME_EXT_ID/\"];" < "\$TMPDIR/native-manifest.json.in" > "\$TMPDIR/native-manifest.chrome.json"

[ -n "\${FIREFOX:-\$ALL}" ] && install_or_uninstall 644 "\$TMPDIR/native-manifest.firefox.json" "\$NATIVE_MANIFEST_DIR_FIREFOX/$NATIVE_MANIFEST_NAME"
[ -n "\${CHROME:-\$ALL}" ] && install_or_uninstall 644 "\$TMPDIR/native-manifest.chrome.json" "\$NATIVE_MANIFEST_DIR_CHROME/$NATIVE_MANIFEST_NAME"
[ -n "\${CHROME_FOR_TESTING:-\$ALL}" ] && install_or_uninstall 644 "\$TMPDIR/native-manifest.chrome.json" "\$NATIVE_MANIFEST_DIR_CHROME_FOR_TESTING/$NATIVE_MANIFEST_NAME"
[ -n "\${CHROMIUM:-\$ALL}" ] && install_or_uninstall 644 "\$TMPDIR/native-manifest.chrome.json" "\$NATIVE_MANIFEST_DIR_CHROMIUM/$NATIVE_MANIFEST_NAME"

install_or_uninstall 755 "\$TMPDIR/notify-server" "\$SERVER_BINARY_PATH"

exit

# DO NOT EDIT ANYTHING BELOW THIS LINE!
BEGIN_BASE64_ENCODED_DATA
$(cat "$BINARY" | gzip -9 | base64 | fold -s -b -w 80)
XEOF

    chmod +x "$OUT_DIR/install-$TARGET.sh"
}

gen_installer() {
    TARGET=$1

    shift 2
    
    cd "$REPO_ROOT/native/notify-server" > /dev/null
    cargo "$@" --release --target "$TARGET"
    cd - > /dev/null

    BANNER=$(cat <<EOF
Install script for notify-server (tab-reload-notify)

Built for: $TARGET
EOF
)

     
    case "$TARGET" in
        *-windows-*)
            BINARY="$REPO_ROOT/native/notify-server/target/$TARGET/release/notify-server.exe"

            gen_installer_win
        ;;
        *-apple-*)
            BINARY="$REPO_ROOT/native/notify-server/target/$TARGET/release/notify-server"

            USER_CHROME_PLACEHOLDER="Google/Chrome" \
            USER_CHROME_FOR_TESTING_PLACEHOLDER="Google/ChromeForTesting" \
            USER_CHROMIUM_PLACEHOLDER="Chromium" \
            SYSTEM_CHROME_PLACEHOLDER="Google/Chrome" \
            SYSTEM_CHROME_FOR_TESTING_PLACEHOLDER="Google/ChromeForTesting" \
            SYSTEM_CHROMIUM_PLACEHOLDER="Application Support/Chromium" \
            USER_NATIVE_MANIFEST_DIR_CHROME="\$HOME/Library/Application Support/%CHROME%/NativeMessagingHosts" \
            SYSTEM_NATIVE_MANIFEST_DIR_CHROME="/Library/%CHROME%/NativeMessagingHosts" \
            USER_NATIVE_MANIFEST_DIR_FF="\$HOME/Library/Application Support/Mozilla/NativeMessagingHosts" \
            SYSTEM_NATIVE_MANIFEST_DIR_FF="/Library/Application Support/Mozilla/NativeMessagingHosts" \
            USER_SERVER_BINARY_PATH="\$HOME/Library/Application Support/tab-reload-notify/notify-server" \
            SYSTEM_SERVER_BINARY_PATH="/Library/Application Support/tab-reload-notify/notify-server" \
                gen_installer_nix
        ;;
        *)
            case "$TARGET" in
                *-freebsd)
                    PREFIX_FF=/usr/local/lib
                    PREFIX_CHROME=/usr/local
                ;;
                *-netbsd)
                    PREFIX_FF=/usr/lib
                    PREFIX_CHROME=/usr/pkg
                ;;
                *-linux-*)
                    PREFIX_FF="\$FIREFOX_LIB_PREFIX"
                    PREFIX_CHROME=""
                ;;
            esac

            BINARY="$REPO_ROOT/native/notify-server/target/$TARGET/release/notify-server"

            USER_CHROME_PLACEHOLDER="google-chrome" \
            USER_CHROME_FOR_TESTING_PLACEHOLDER="google-chrome-for-testing" \
            USER_CHROMIUM_PLACEHOLDER="chromium" \
            SYSTEM_CHROME_PLACEHOLDER="opt/chrome" \
            SYSTEM_CHROME_FOR_TESTING_PLACEHOLDER="opt/chrome_for_testing" \
            SYSTEM_CHROMIUM_PLACEHOLDER="chromium" \
            USER_NATIVE_MANIFEST_DIR_FF="\$HOME/.mozilla/native-messaging-hosts" \
            SYSTEM_NATIVE_MANIFEST_DIR_FF="$PREFIX_FF/mozilla/native-messaging-hosts" \
            USER_NATIVE_MANIFEST_DIR_CHROME="\${XDG_CONFIG_HOME:-\$HOME/.config}/%CHROME%/NativeMessagingHosts" \
            SYSTEM_NATIVE_MANIFEST_DIR_CHROME="$PREFIX_CHROME/etc/%CHROME%/native-messaging-hosts" \
            USER_SERVER_BINARY_PATH="\${XDG_BIN_HOME:-\$HOME/.local/bin}/tab-reload-notify/notify-server" \
            SYSTEM_SERVER_BINARY_PATH="\$PREFIX/libexec/tab-reload-notify/notify-server" \
                gen_installer_nix
        ;;
    esac
}

while [ $# -ne 0 ]; do
    case "$1" in
        --current-target-only)
            CURRENT_TARGET_ONLY=1
        ;;
        *)
            cat <<EOF >&2
Usage: $(basename "$0")

Generates install scripts for the extension's native component.

    -h, --help
        Show this help menu

    --current-target-only
        Build the native component and generate the install script
        for the current target only

        (removes the dependency on \`zig' and \`cargo-zigbuild')

Environment Variables

    MACOS_SDKROOT
        Path to the macOS Xcode SDK root, passed to \`cargo-zigbuild'
        when building the native component for *-apple-darwin targets.

        Current value:
            MACOS_SDKROOT="${MACOS_SDKROOT}"

    ZIG_TARGETS, ZIG_XCODE_TARGETS
        Targets for which the native component will be built using
        \`zig' and \`cargo-zigbuild'.

        Current value:
            ZIG_TARGETS="$(echo "$ZIG_TARGETS" | tr '\n\t'   '  ' | tr -s ' ')"
            ZIG_XCODE_TARGETS="$ZIG_XCODE_TARGETS"

    XWIN_TARGETS
        Targets that will be built using \`cargo-xwin'.

        Current value
            XWIN_TARGETS="$XWIN_TARGETS"

    The target variables may be overridden or set to empty strings to skip
    building the native component and install scripts for some targets.
EOF

            [ "$1" = "-h" ] || [ "$1" = "--help" ]
            exit $?
        ;;
    esac

    shift 1
done

if [ -n "$CURRENT_TARGET_ONLY" ]; then
    gen_installer "$(rustc -vV | sed -n "s/host: //p")" -- build
    exit
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
