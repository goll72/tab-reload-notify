target := env("TARGET", `rustc -vV | sed -n 's/host: //p'`)

[parallel]
build: build-extension build-server

lint:
    npx web-ext lint -s src -i '*.ts'

run *args:
    npx web-ext run -s src {{args}}

[unix]
install prefix=(home_dir() + "/.local") native-manifest-path=(home_dir() + "/.mozilla/native-messaging-hosts"):
    sed "s:%SERVER_INSTALL_BASE_DIR%:{{prefix}}/libexec/tab-reload-notify/:" native/native-manifest.json.in > native/native-manifest.json
    install -D -m755 native/notify-server/target/{{target}}/release/notify-server {{prefix}}/libexec/tab-reload-notify/notify-server
    install -D -m644 native/native-manifest.json {{native-manifest-path}}/tab_reload_notify_server.json

build-extension:
    npx tsc
    npx web-ext build --overwrite-dest -s src -i '*.ts' 

[working-directory: "native/notify-server"]
build-server:
    cargo build --release --target {{target}}
