#!/bin/sh
# Downloads VM images and runs virtual machines with additional
# setup so they can be used as testbeds for the extension.
# 
# Dependencies: `quickget`, `quickemu`, `smbd` (samba)

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)

. "$REPO_ROOT/scripts/common.sh"

OUT_DIR="$VM_OUT_DIR"
mkdir -p "$OUT_DIR"

ARCH=$(uname -m)

# Source: https://unix.stackexchange.com/a/655825
pnrelpath() {
    set -- "${1%/}/" "${2%/}/" ''               ## '/'-end to avoid mismatch
    while [ "$1" ] && [ "$2" = "${2#"$1"}" ]    ## reduce $1 to shared path
    do  set -- "${1%/?*/}/"  "$2" "../$3"       ## source/.. target ../relpath
    done
    REPLY="${3}${2#"$1"}"                       ## build result
    # unless root chomp trailing '/', replace '' with '.'
    [ "${REPLY#/}" ] && REPLY="${REPLY%/}" || REPLY="${REPLY:-.}"
}

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
            cp "$i" "$i.bak"
        done
    ;;
    --restore)
        for i in "$OUT_DIR"/*/disk.qcow2.bak; do
            cp "$i" "${i%.bak}"
        done
    ;;
    --run)
        case "$2" in
            $ARCH-unknown-linux-musl)
                if ! [ -f "$INST_OUT_DIR/install-$ARCH-unknown-linux-musl.sh" ]; then
                    echo "You need to run \`gen-installer.sh' first." >&2
                    exit 1
                fi

                quickemu --vm alpine-v3.23.conf --serial telnet --display none --public-dir "$SHARED_DIR"

                cat <<EOF
Run the following commands to run the tests:

\`\`\`
sudo apk add nodejs npm firefox cifs-utils

rm -R /tmp/trn
mkdir -p /tmp/trn

sudo mount -t cifs //10.0.2.4/qemu /mnt

cd /mnt

./install-$ARCH-unknown-linux-musl.sh
cp -RL tests extension-* /tmp/trn

cd /tmp/trn/tests

npm install
# ...
\`\`\`
EOF
                telnet localhost 6660
            ;;
            $ARCH-unknown-freebsd)
                if ! [ -f "$INST_OUT_DIR/install-$ARCH-unknown-freebsd.sh" ]; then
                    echo "You need to run \`gen-installer.sh' first." >&2
                    exit 1
                fi

                quickemu --vm freebsd-15.0-disc1.conf --serial telnet --display none --public-dir "$SHARED_DIR"

                cat <<EOF
Run the following commands to run the tests:

\`\`\`
sudo pkg add node25 npm-node25 firefox

rm -R /tmp/trn
mkdir -p /tmp/trn

sudo mount_smbfs //10.0.2.4/qemu /mnt

cd /mnt

./install-$ARCH-unknown-freebsd.sh
cp -RL tests extension-* /tmp/trn

cd /tmp/trn/tests

npm install
# ...
\`\`\`
EOF
                telnet localhost 6660
            ;;
            $ARCH-apple-darwin)
                if ! [ -f "$INST_OUT_DIR/install-$ARCH-apple-darwin.sh" ]; then
                    echo "You need to run \`gen-installer.sh' first." >&2
                    exit 1
                fi

                quickemu --vm macos-sequoia.conf --serial telnet --public-dir "$SHARED_DIR"

                cat <<EOF
If you want to use a serial connection, open a
terminal window and run the following command:

\`\`\`
sudo /usr/libexec/getty - tty.serial1
\`\`\`

Then, run the following commands to run the tests:

\`\`\`
sudo mkdir /shared
mkdir -p /tmp/trn
sudo mount -t smbfs //10.0.2.4/qemu /shared

cd /shared

sudo installer -pkg macos-firefox.pkg -target /
sudo installer -pkg macos-nodejs.pkg -target /

./install-$ARCH-apple-darwin.sh
cp -RL tests extension-* /tmp/trn

cd /tmp/trn/tests

npm install
# ...
\`\`\`
EOF
                telnet localhost 6660
            ;;
            $ARCH-pc-windows-msvc)
                if ! [ -f "$INST_OUT_DIR/install-$ARCH-pc-windows-msvc.ps1" ]; then
                    echo "You need to run \`gen-installer.sh' first." >&2
                    exit 1
                fi

                quickemu --vm windows-10.conf --public-dir "$SHARED_DIR"

                cat <<EOF
To enable OpenSSH and allow login, open a PowerShell
window as Administrator and run the following commands:

\`\`\`
Get-WindowsCapability -Online -Name OpenSSH.Server* | Add-WindowsCapability -Online
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
net user Quickemu *
\`\`\`

You only need to run them once.

Once in the password prompt, use \`Quickemu' as the password.
After doing that, press Enter/Return on the following prompt.

EOF

                printf "...> "
                read

cat <<EOF
To log in using ssh, run:

\`\`\`
ssh -F $(pnrelpath "$(pwd)" "$AUX_DIR")/ssh.conf windows-10
\`\`\`

You may want to run that command in a separate terminal window,
as the OpenSSH server that comes bundled with Windows will clear
the screen upon login.

After logging in, run the following commands to run the tests:

\`\`\`
winget install -e --id OpenJS.NodeJS Mozilla.Firefox

\$share = \\\\10.0.2.4\\qemu
\$trn = \$env:TMP\\trn
mkdir \$trn

Invoke-Command \$share\\install-$ARCH-pc-windows-msvc
Copy-Item -Recurse -Path \$share\\tests \$share\\extension-* -Destination \$trn

cd \$trn\\tests

npm install
# ...
\`\`\`

You may need to log out and log back in so Firefox
and NodeJS get added to the system's executable path.
EOF

                
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
