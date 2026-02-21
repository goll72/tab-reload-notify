version := `jq --raw-output '.version' < src/manifest.json`

extension_zip := "web-ext-artifacts/tab-reload-notify-" + version + ".zip"
server_manifest := "tab_reload_notify_server.json"

target := `rustc -vV | sed -n 's/host: //p'`

[parallel]
build: build-extension build-notify-server

lint:
    npx web-ext lint -s src -i '*.ts'

run *args:
    npx web-ext run -s src {{args}}

[unix]
install: (install-notify-server (home_dir() + "/.mozilla/native-messaging-hosts") "notify-server")

install-notify-server path bin:
    sed "s:%EXT_APP_INSTALL_PATH%:{{path}}:" app/{{server_manifest}}.in > app/{{server_manifest}}
    install -D -m755 app/target/{{target}}/release/app {{path}}/{{bin}}
    install -D -m644 app/{{server_manifest}} {{path}}/{{server_manifest}}

build-extension:
    npx tsc
    npx web-ext build --overwrite-dest -s src -i '*.ts' 

[working-directory: "app"]
build-notify-server:
    cargo build --release --target {{target}}
