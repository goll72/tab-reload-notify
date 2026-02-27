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
EOF
