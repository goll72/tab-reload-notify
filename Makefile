.POSIX:

VERSION != jq --raw-output ".version" < src/manifest.json

SRC := src/main.ts src/common.ts src/options.ts
JS := $(SRC:%.ts=%.js)

SERVER_BINARY := native/notify-server/target/release/notify-server
EXTENSION_ZIP := web-ext-artifacts/tab-reload-notify-$(VERSION).zip 

PREFIX ?= ~/.local
NATIVE_MANIFEST_PATH ?= ~/.mozilla/native-messaging-hosts

build: $(EXTENSION_ZIP) $(SERVER_BINARY)

lint:
	npx web-ext lint -s src -i '*.ts'

run:
	npx web-ext run -s src

install: $(SERVER_BINARY)
	sed "s:%SERVER_INSTALL_BASE_DIR%:$(PREFIX)/libexec/tab-reload-notify/:" native/native-manifest.json.in > native/native-manifest.json
	install -D -m755 $(SERVER_BINARY) $(PREFIX)/libexec/tab-reload-notify/notify-server
	install -D -m644 native/native-manifest.json $(NATIVE_MANIFEST_PATH)/tab_reload_notify_server.json

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
