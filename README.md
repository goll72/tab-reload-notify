tab-reload-notify
=================

This browser extension automatically reloads tabs using the file URI scheme
when their content changes, by using file watch primitives. The Rust crate
`notify` is used, thus supporting the following backends:

 - Linux: inotify
 - macOS: FSEvent/kqueue
 - *BSD: kqueue
 - Windows: ReadDirectoryChanges


## Building

To build the extension, you will need `npm`, `make`, `rsvg-convert`, `unzip`
and a nightly Rust toolchain. After having installed the dependencies, run
the following command to build the extension, using `web-ext`.

```sh
make build
```

To build and install the native component, run:

```sh
./scripts/gen-installer.sh --current-target-only
./scripts/output/installers/install-$(rustc -vV | sed "s/host: //p").sh
```

Check out the help text and header for each script to find out about
additional dependencies that may be required, as well as configuration
options that may be provided.

You can also run

```sh
make run
```

and optionally specify an `ARGS` variable to run a Firefox/Chromium
session with the extension enabled for debugging.

## Development and Testing

Install all the dependencies outlined in `scripts/gen-installer.sh` and
`scripts/run-vm-tests.sh`. Then, you may run `./scripts/gen-installer.sh`
to generate install scripts for all supported targets.

Then, run `./scripts/run-vm-tests.sh --download` to download VM images
and follow the instructions to set up the virtual machines for testing
the extension.

> [!NOTE]
>
> You can also run the tests natively:
>
> ```sh
> cd tests
> npm install
> npx puppeteer browsers install firefox
> BROWSER=firefox EXT_PATH=../web-ext-artifacts node main.ts
> BROWSER=chrome EXT_PATH=../web-ext-artifacts node main.ts
> ```
