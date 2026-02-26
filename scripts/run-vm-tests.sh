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
        # NOTE: on Linux and FreeBSD, a serial interface is set up and used to run
        # commands without user intervention. On macOS, a serial interface is also
        # used but that requires initial user intervention. Windows doesn't support
        # running terminal applications over a serial interface, so SSH is used,
        # also requiring initial user intervention.
        # 
        # NOTE: commands that are run automatically inside "first time setup" guards may be
        # side-effectful, but all other commands should strive to be as idempotent as possible.
        case "$2" in
            $ARCH-unknown-linux-musl)
                quickemu --vm alpine-v3.23.conf --serial telnet --display none

                telnet localhost 6660 <<EOF
EOF
            ;;
            $ARCH-unknown-freebsd)
                quickemu --vm freebsd-15.0-disc1.conf --serial telnet --display none

                telnet localhost 6660 <<EOF
EOF
            ;;
            $ARCH-apple-darwin)
                quickemu --vm macos-sequoia.conf --serial telnet

                if ! [ -f "$OUT_DIR/macos-sequoia/first-time-setup.over" ]; then
                    cat <<EOF
:: Additional setup required!

Open a terminal window and run the following command:

```
sudo /usr/libexec/getty - tty.serial1
```

After typing in your user's password, press Enter/Return in the following prompt.

EOF

                    printf "...> "
                    read

                    telnet localhost 6660 <<XEOF
cat <<EOF > /Library/LaunchDaemons/getty.tty.serial1.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>getty.tty.serial1</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/libexec/getty</string>
        <string>-</string>
        <string>tty.serial1</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>
</plist>
XEOF
                fi
                
            ;;
            $ARCH-pc-windows-msvc)
                quickemu --vm windows-10.conf

                if ! [ -f "$OUT_DIR/windows-10/first-time-setup.over" ]; then
                    cat <<EOF
:: Additional setup required!

Open a PowerShell window as Administrator and run the following commands:

```
Get-WindowsCapability -Online -Name OpenSSH.Server* | Add-WindowsCapability -Online
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
New-ItemProperty -Path HKLM:\\SOFTWARE\\OpenSSH -Name DefaultShell -Value C:\\Windows\\system32\\WindowsPowerShell\\v1.0\\powershell.exe -PropertyType String -Force
net user Quickemu *
```

Once in the password prompt, use \`Quickemu' as the password.
After doing that, press Enter/Return in the following prompt.

EOF

                    printf "...> "
                    read
                fi
                
                ssh -o WarnWeakCrypto=no -o PreferredAuthentications=password -o PubkeyAuthentication=no -p 22220 Quickemu@localhost <<EOF
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
