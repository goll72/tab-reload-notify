#!/bin/sh
# Downloads VM images and runs virtual machines with additional
# setup so they can be used as testbeds for the extension.
# 
# Dependencies: `quickget`, `quickemu`, `smbd` (samba), `curl`,
# `rsync`, `unzip`

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)

. "$REPO_ROOT/scripts/common.sh"

OUT_DIR="$VM_OUT_DIR"
mkdir -p "$OUT_DIR"

ARCH=$(uname -m)

: "${SERIAL:=6660}"

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
        [ -f netbsd-10.1.conf ] || quickget netbsd 10.1
        [ -f macos-sequoia.conf ] || quickget macos sequoia
        [ -f windows-10.conf ] || quickget windows 10

        sed 's/boot="legacy"//' netbsd-10.1.conf > netbsd-10.1.conf.new
        mv netbsd-10.1.conf.new netbsd-10.1.conf

        cat <<EOF
The following VM images have been installed to \`$OUT_DIR':

    alpine-v3.23.conf         ->   $ARCH-unknown-linux-musl
    freebsd-15.0-disc1.conf   ->   x86_64-unknown-freebsd
    netbsd-10.1.conf          ->   x86_64-unknown-netbsd
        [ NOTE: You will need to switch to the bootloader prompt before the ]
        [       3s timer runs out and run \`consdev com0' and then \`boot' if ]
        [       you want to use a serial interface.                         ]
        [                                                                   ]
        [       In the "Select your distribution" menu, choose              ]
        [       "Full Installation".                                        ]
        [                                                                   ]
        [       If there is no internet connectivity once you boot into the ]
        [       installed system, run \`dhcpcd'.                            ]
        [                                                                   ]
        [       For a more pleasant terminal experience, install \`zsh' and  ]
        [       \`tmux' and set \`zsh' as your login shell.                   ]

    macos-sequoia.conf        ->   $ARCH-apple-darwin
        [ NOTE: You may need to reboot and select the recovery disk multiple ]
        [       times before being able to boot into the installed system.   ]

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

        {
            cd "$OUT_DIR" > /dev/null
            
            for i in */; do
                [ -f "${i%/}/first-time-setup.over" ] && X=touch || X="rm -f"
                echo "$X \$OUT_DIR/${i%/}/first-time-setup.over"
            done

            cd - > /dev/null
        } > "$OUT_DIR/saved.flag"
    ;;
    --restore)
        for i in "$OUT_DIR"/*/disk.qcow2.bak; do
            cp "$i" "${i%.bak}"
        done

        . "$OUT_DIR/saved.flag"
    ;;
    --run)
        mkdir -p "$SHARED_DIR"
        chmod 777 "$SHARED_DIR"

        [ -f "$SHARED_DIR/macos-nodejs.pkg" ] || curl -L "https://nodejs.org/dist/v25.7.0/node-v25.7.0.pkg" -o "$SHARED_DIR/macos-nodejs.pkg"

        cp -R "$REPO_ROOT"/web-ext-artifacts/* "$INST_OUT_DIR"/* "$SHARED_DIR"
        rsync -rL --exclude="node_modules/*" --exclude=package-lock.json "$REPO_ROOT/tests/" "$SHARED_DIR/tests"

        TARGET="$2"

        case "$TARGET" in
            "$ARCH-unknown-linux-musl")
                if ! [ -f "$INST_OUT_DIR/install-$TARGET.sh" ]; then
                    echo "You need to run \`gen-installer.sh' first." >&2
                    exit 1
                fi

                quickemu --vm alpine-v3.23.conf --serial telnet --serial-telnet-port "$SERIAL" --display none --public-dir "$SHARED_DIR"

                if ! [ -f "$OUT_DIR/alpine-v3.23/first-time-setup.over" ]; then
                    cat <<EOF

Access VM by running \`telnet localhost 6660' in a separate terminal window.
Log in as \`root'.

Run:

\`\`\`
adduser trn
addgroup trn wheel

setup-apkrepos -c

apk add doas nodejs npm cifs-utils xz firefox chromium
echo "permit persist :wheel" > /etc/doas.d/20-wheel.conf

exit
\`\`\`

EOF

                    printf "...> "
                    read -r _
                    
                    touch "$OUT_DIR/alpine-v3.23/first-time-setup.over"
                fi
            
                cat <<EOF
Access VM by running \`telnet localhost 6660' in a separate terminal window.
Log in as \`trn'.

Run:

\`\`\`
rm -R /tmp/trn
mkdir -p /tmp/trn

doas mount -t cifs //10.0.2.4/qemu /mnt

cd /mnt

doas ./install-$ARCH-unknown-linux-musl.sh --system
cp -R tests extension* /tmp/trn

cd /tmp/trn/tests

export PUPPETEER_SKIP_DOWNLOAD=1
npm install

PUPPETEER_EXECUTABLE_PATH=/usr/bin/firefox BROWSER=firefox node main.ts
PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser BROWSER=chrome node main.ts
\`\`\`
EOF
            ;;
            x86_64-unknown-freebsd)
                if ! [ -f "$INST_OUT_DIR/install-$TARGET.sh" ]; then
                    echo "You need to run \`gen-installer.sh' first." >&2
                    exit 1
                fi

                quickemu --vm freebsd-15.0-disc1.conf --serial telnet --serial-telnet-port "$SERIAL" --display none --public-dir "$SHARED_DIR"

                if ! [ -f "$OUT_DIR/freebsd-15.0-disc1/first-time-setup.over" ]; then
                    cat <<EOF

Access VM by running \`telnet localhost 6660' in a separate terminal window.
Log in as \`root'.

Run:

\`\`\`
pw useradd -n trn -G wheel -b /home -m
passwd trn
 
pkg install doas node25 npm-node25 firefox chromium samba423

echo "permit persist :wheel" >> /usr/local/etc/doas.conf

exit
\`\`\`

EOF
                    printf "...> "
                    read -r _

                    touch "$OUT_DIR/freebsd-15.0-disc1/first-time-setup.over"
                fi

                cat <<EOF

Access VM by running \`telnet localhost 6660' in a separate terminal window.
Log in as \`trn'.

Run:

\`\`\`
rm -R /tmp/trn
mkdir -p /tmp/trn

cd /tmp/trn
smbclient '\\\\10.0.2.4\\qemu' -N -c 'prompt OFF; recurse ON; mget *'

sh ./install-x86_64-unknown-freebsd.sh

cd tests

export PUPPETEER_SKIP_DOWNLOAD=1
npm install

PUPPETEER_EXECUTABLE_PATH=/usr/local/bin/firefox BROWSER=firefox node main.ts
PUPPETEER_EXECUTABLE_PATH=/usr/local/bin/chrome BROWSER=chrome node main.ts
\`\`\`
EOF
            ;;
            x86_64-unknown-netbsd)
                if ! [ -f "$INST_OUT_DIR/install-$TARGET.sh" ]; then
                    echo "You need to run \`gen-installer.sh' first." >&2
                    exit 1
                fi

                quickemu --vm netbsd-10.1.conf --serial telnet --serial-telnet-port "$SERIAL" --display none --public-dir "$SHARED_DIR"

if ! [ -f "$OUT_DIR/netbsd-10.1/first-time-setup.over" ]; then
                    cat <<EOF

Access VM by running \`telnet localhost 6660' in a separate terminal window.
Log in as \`root'.

Run:

\`\`\`
useradd -b /home -m -G wheel trn
passwd trn

export PKG_PATH=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/x86_64/10.1/All
pkg_add pkgin

pkgin install doas nodejs firefox chromium samba

echo consdev=com0 >> /boot.cfg
echo "permit persist :wheel" > /usr/pkg/etc/doas.conf

sed -i -E 's:/( |\t)*ffs( |\t)*rw( |\t):/\tffs\trw,sync,log\t:' /etc/fstab

exit
\`\`\`

EOF
                    printf "...> "
                    read -r _

                    touch "$OUT_DIR/netbsd-10.1/first-time-setup.over"
                fi

                cat <<EOF

Access VM by running \`telnet localhost 6660' in a separate terminal window.
Log in as \`trn'.

Run:

\`\`\`
rm -R /tmp/trn
mkdir -p /tmp/trn

cd /tmp/trn
smbclient '\\\\10.0.2.4\\qemu' -N -c 'prompt OFF; recurse ON; mget *'

sh ./install-x86_64-unknown-netbsd.sh

cd tests

export PUPPETEER_SKIP_DOWNLOAD=1
npm install

PUPPETEER_EXECUTABLE_PATH=/usr/pkg/bin/firefox BROWSER=firefox node main.ts
PUPPETEER_EXECUTABLE_PATH=/usr/pkg/bin/chromium BROWSER=chrome node main.ts
\`\`\`
EOF
            ;;
            "$ARCH-apple-darwin")
                if ! [ -f "$INST_OUT_DIR/install-$TARGET.sh" ]; then
                    echo "You need to run \`gen-installer.sh' first." >&2
                    exit 1
                fi

                quickemu --vm macos-sequoia.conf --serial telnet --serial-telnet-port "$SERIAL" --public-dir "$SHARED_DIR"

                cat <<EOF
Open a terminal window on macOS and run:

\`\`\`
sudo /usr/libexec/getty - tty.serial1
\`\`\`

Access VM by running \`telnet localhost 6660' in a separate terminal window.
Log in.

Run:

\`\`\`
mkdir -p /tmp/trn

sudo mount_9p Public-$(echo "$USER" | tr 'A-Z' 'a-z')
cd /Volumes/Public-$(echo "$USER" | tr 'A-Z' 'a-z')

sudo installer -pkg macos-nodejs.pkg -target /

sh ./install-$ARCH-apple-darwin.sh
cp -R tests extension* /tmp/trn

cd /tmp/trn/tests

npm install
npx puppeteer browsers install firefox

BROWSER=firefox node main.ts
BROWSER=chrome node main.ts
\`\`\`
EOF
            ;;
            "$ARCH-pc-windows-msvc")
                if ! [ -f "$INST_OUT_DIR/install-$TARGET.ps1" ]; then
                    echo "You need to run \`gen-installer.sh' first." >&2
                    exit 1
                fi

                quickemu --vm windows-10.conf --public-dir "$SHARED_DIR"

                if ! [ -f "$OUT_DIR/windows-10/first-time-setup.over" ]; then
                    cat <<EOF
On Windows, open a PowerShell window as Administrator.

Run:

\`\`\`
Get-WindowsCapability -Online -Name OpenSSH.Server* | Add-WindowsCapability -Online
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

net user Quickemu *

winget install -e --id OpenJS.NodeJS
\`\`\`

EOF

                    printf "...> "
                    read -r _

                    touch "$OUT_DIR/windows-10/first-time-setup.over"
                fi

cat <<EOF
Access VM by running \`ssh -F $(pnrelpath "$(pwd)" "$AUX_DIR")/ssh.conf windows-10' in a separate terminal window.

Run:

\`\`\`
\$share = \\\\10.0.2.4\\qemu
\$trn = \$env:TMP\\trn

mkdir \$trn

Invoke-Command \$share\\install-$ARCH-pc-windows-msvc.ps1
Copy-Item -Recurse -Path \$share\\tests \$share\\extension* -Destination \$trn

cd \$trn\\tests

npm install
npx puppeteer browsers install firefox

$env:BROWSER = 'firefox'; node main.ts
$env:BROWSER = 'chrome'; node main.ts
\`\`\`
EOF
            ;;
            "")
                echo "You need to specify a target to run." >&2
                exit 1
            ;;
            *)
                echo "Unsupported target: $TARGET" >&2
                exit 1
            ;;
        esac 
    ;;
    *)
        cat <<EOF >&2
Usage: $(basename "$0") [ -h | --help | --download | --run <TARGET> ]

Downloads VM images and runs virtual machines with additional set up
so they can be used as testbeds for the extension.

    -h, --help
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
            x86_64-unknown-freebsd
            x86_64-unknown-netbsd
            $ARCH-apple-darwin
            $ARCH-pc-windows-msvc

Environment Variables

    SERIAL
        Port used for serial interfacing over telnet (not used on Windows guests)

        Current value: SERIAL="$SERIAL"
EOF
        [ "$1" = "-h" ] || [ "$1" = "--help" ]
        exit $?
    ;;
esac
