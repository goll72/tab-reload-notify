#!/bin/sh
# Downloads VM images and runs virtual machines with additional
# setup so they can be used as testbeds for the extension.
# 
# Dependencies: `quickget`, `quickemu`, `sshpass`, `samba`

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)
OUT_DIR="$REPO_ROOT/scripts/output/vms"
AUX_DIR="$REPO_ROOT/scripts/aux"

SHARED_DIR="$REPO_ROOT/scripts/output/shared"

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

Note: this script assumes you're using \`toor' as the main non-root user
(able to run \`sudo') on Linux, FreeBSD and macOS, as well as \`Quickemu'
on Windows (default when using quickemu's unattended ISO). The password
shpuld match the username.
EOF
    ;;
    --save)
        if [ -f "$OUT_DIR/saved.flag" ]; then
            echo "\`$(basename "$0") --save' has been run already! Delete \`$OUT_DIR/saved.flag' if you want to overwrite the images that have been saved." >&2
            exit 1
        fi

        for i in "$OUT_DIR"/*/disk.qcow2; do
            cp "$i" "$i.bak"
        done

        # Save additional information stored as files in the filesystem
        {
            [ -f "$OUT_DIR/macos-sequoia/first-time-setup.over" ] && X=touch || X="rm -f"
            echo "$X \$OUT_DIR/macos-sequoia/first-time-setup.over"
            
            [ -f "$OUT_DIR/windows-10/first-time-setup.over" ] && X=touch || X="rm -f"
            echo "$X \$OUT_DIR/windows-10/first-time-setup.over"
        } > "$OUT_DIR/saved.flag"
    ;;
    --restore)
        for i in "$OUT_DIR"/*/disk.qcow2.bak; do
            cp "$i" "${i%.bak}"
        done

        . "$OUT_DIR/saved.flag"
    ;;
    --run)
        # NOTE: commands that are run automatically inside "first time setup" guards may be
        # side-effectful, but all other commands should strive to be as idempotent as possible.
        case "$2" in
            $ARCH-unknown-linux-musl)
                quickemu --vm alpine-v3.23.conf --serial telnet --display none --public-dir "$SHARED_DIR"

                telnet localhost 6660 <<EOF
apk add nodejs npm firefox cifs-utils
EOF
            ;;
            $ARCH-unknown-freebsd)
                quickemu --vm freebsd-15.0-disc1.conf --serial telnet --display none --public-dir "$SHARED_DIR"

                telnet localhost 6660 <<EOF
pkg add node25 npm-node25 firefox
EOF
            ;;
            $ARCH-apple-darwin)
                quickemu --vm macos-sequoia.conf --serial telnet --public-dir "$SHARED_DIR"

                if ! [ -f "$OUT_DIR/macos-sequoia/first-time-setup.over" ]; theni
                    # XXX: revise this
                    cat <<EOF
:: Additional setup required!

Open a terminal window and run the following command:

\`\`\`
sudo passwd root
sudo /usr/libexec/getty - tty.serial1
\`\`\`

Set the root password to \`root'. Then, after running
the getty, press Enter/Return in the following prompt.

EOF

                    printf "...> "
                    read

                    # XXX: just use ssh
                    # "$AUX_DIR/macos-write-getty-service.sh"

                    touch "$OUT_DIR/macos-sequoia/first-time-setup.over"

                    echo "Shut down the VM and re-run it using this script to run tests."
                    exit
                fi

                # "$AUX_DIR/macos-set-up-run-tests.sh"
            ;;
            $ARCH-pc-windows-msvc)
                SSH="sshpass -p Quickemu ssh -o WarnWeakCrypto=no -o PreferredAuthentications=password -o PubkeyAuthentication=no -p 22220"
                POWERSHELL="C:\\Windows\\system32\\WindowsPowerShell\\v1.0\\powershell.exe"

                quickemu --vm windows-10.conf --public-dir "$SHARED_DIR"

                if ! [ -f "$OUT_DIR/windows-10/first-time-setup.over" ]; then
                    cat <<EOF
:: Additional setup required!

Open a PowerShell window as Administrator and run the following commands:

\`\`\`
Get-WindowsCapability -Online -Name OpenSSH.Server* | Add-WindowsCapability -Online
Start-Service sshd
net user Quickemu *
\`\`\`

Once in the password prompt, use \`Quickemu' as the password.
After doing that, press Enter/Return in the following prompt.

EOF

                    printf "...> "
                    read

                    $SSH quickemu@localhost "$POWERSHELL" -Command "Set-Service -Name sshd -StartupType Automatic"

                    touch "$OUT_DIR/windows-10/first-time-setup.over"

                    echo "Shut down the VM and re-run it using this script to run tests."
                    exit
                fi

                # These two commands are separate so that changes in the
                # PATH may be replicated in the last PowerShell session
                $SSH quickemu@localhost "$POWERSHELL" -Command "winget install -e --id OpenJS.NodeJS"
                $SSH quickemu@localhost "$POWERSHELL" -Command "winget install -e --id Mozilla.Firefox"

                $SSH quickemu@localhost "$POWERSHELL" < "$AUX_DIR/windows-set-up-run-tests.ps1"
EOF
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
