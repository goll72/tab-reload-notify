.POSIX:

VERSION != jq --raw-output ".version" < src/manifest.json

SRC := src/main.ts src/common.ts src/options.ts
JS := $(SRC:%.ts=%.js)

EXTENSION_ZIP := web-ext-artifacts/tab-reload-notify-$(VERSION).zip 

NATIVE_MANIFEST_PATH ?= $${HOME}/.mozilla/native-messaging-hosts/tab_reload_notify_server.json
SERVER_BINARY_PATH ?= $${XDG_BIN_HOME:-$${HOME}/.local/bin}/tab-reload-notify/notify-server

build: $(EXTENSION_ZIP) $(SERVER_BINARY)

lint:
	npx web-ext lint -s src -i '*.ts'

run:
	npx web-ext run -s src

install: $(SERVER_BINARY)
	sed "s:%SERVER_BINARY_PATH%:$(SERVER_BINARY_PATH):" native/native-manifest.json.in > native/native-manifest.json
	install -D -m755 native/notify-server/target/release/notify-server $(SERVER_BINARY_PATH)
	install -D -m644 native/native-manifest.json $(NATIVE_MANIFEST_PATH)

node_modules:
	npm install --package-lock-only
	touch -m $@

$(JS): $(SRC) src/types.d.ts tsconfig.json node_modules
	npx tsc

$(EXTENSION_ZIP): $(JS) src/manifest.json
	npx web-ext build --overwrite-dest -s src -i '*.ts' 

$(SERVER_BINARY): native/notify-server/src/main.rs
	cd native/notify-server && cargo build --release

.PHONY: build lint run install
