.POSIX:

SRC := src/main.ts src/common.ts src/options.ts
JS := $(SRC:%.ts=%.js)

EXTENSION_DIR := web-ext-artifacts/extension
EXTENSION_ZIP := web-ext-artifacts/extension.zip

ICONS = src/icon16.png src/icon32.png src/icon48.png src/icon64.png src/icon128.png

build: $(EXTENSION_ZIP) $(EXTENSION_DIR)

lint:
	npx web-ext lint

run:
	npx web-ext run $(ARGS)

release:
	@[ -n "`git tag --points-at HEAD`" ] || { echo "Cannot make release from non-tagged commit" >&2; exit 1; }
	./scripts/gen-installer.sh
	gh release create `git tag --points-at HEAD` scripts/output/installers/install-*

node_modules: package.json
	npm install
	touch -m $@

$(JS): $(SRC) src/types.d.ts tsconfig.json node_modules
	npx tsc

src/browser-polyfill.js: node_modules
	cp node_modules/webextension-polyfill/dist/browser-polyfill.js $@

src/icon%.png: src/icon.svg
	rsvg-convert --width=$* --height=$* --keep-aspect-ratio $? > $@ 

$(EXTENSION_ZIP): $(JS) src/browser-polyfill.js src/options.html $(ICONS) src/manifest.json
	npx web-ext build -n `basename $(EXTENSION_ZIP)`

$(EXTENSION_DIR): $(EXTENSION_ZIP)
	unzip -o -d $@ $?
	touch -m $@

.PHONY: build lint run release
