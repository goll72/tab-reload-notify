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
./scripts/output/installers/install-$(rustc -vV | sed -n "s/host: //p").sh
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

## Installing

The extension can be installed from [addons.mozilla.org](https://addons.mozilla.org)
or [Chrome Web Store](https://chromewebstore.google.com/). However, a native
component is needed for the extension to work. Install scripts can be found
in the [releases page](https://github.com/goll72/tab-reload-notify/releases/latest).

> [!NOTE]
>
> On Windows, you may need to install the Microsoft Visual C++
> Redistributable v14 before being able to use the extension.
>
> - [Download page (x64)](https://aka.ms/vc14/vc_redist.x64.exe)
> - [Download page (ARM64)](https://aka.ms/vc14/vc_redist.arm64.exe)

## Development and Testing

First, you will need to install all the dependencies outlined in
`scripts/gen-installer.sh` and `scripts/run-vm-tests.sh`.

### Install Scripts

`./scripts/gen-installer.sh` will generate a install script for the
native component of the extension, for each supported target, using
POSIX sh on *nix targets andPowershell 5.1 on Windows targets.

### Virtual Machines

You may run `./scripts/run-vm-tests.sh --download` to download VM images
and follow the instructions to set up the virtual machines for testing
the extension.

> [!NOTE]
>
> You can also run the tests natively:
>
> ```sh
> cd tests
>
> npm install
> npx puppeteer browsers install firefox
>
> BROWSER=firefox EXT_PATH=../web-ext-artifacts node main.ts
> BROWSER=chrome EXT_PATH=../web-ext-artifacts node main.ts
> ```

### Signing

If you are in possession of a signing key, you may sign the extension by running

```sh
chromium --pack-extension=web-ext-artifacts/extension --pack-extension-key=key.pem
```

> [!TIP]
>
> By having the extension's public key (which can be found in the manifest's `key`
> field), it is possible to derive the Chrome extension ID:
>
> ```sh
> jq --raw-output '"-----BEGIN PUBLIC KEY-----\n\(.key)\n-----END PUBLIC KEY-----"' src/manifest.json | \
>     openssl pkey -in /dev/stdin -pubin -outform DER | shasum -a 256 | head -c32 | tr 0-9a-f a-p
> ```
