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

> [!NOTE]
>
> On Windows, you may need to install the Microsoft Visual C++
> Redistributable v14 before being able to use the extension.
>
> - [Download page (x64)](https://aka.ms/vc14/vc_redist.x64.exe)
> - [Download page (ARM64)](https://aka.ms/vc14/vc_redist.arm64.exe)

## Development and Testing

First, you will need to install all the dependencies outlined in
`scripts/gen-installer.sh` and `scripts/run-vm-tests.sh`, as well
as `openssl` and `sha256sum`.

### Signing

In order to test an extension on Chrome and have its ID stay the same,
it has to be signed. Run the following commands to generate an RSA
keypair and replace the public key set in the extension's manifest
with your own:

```sh
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out key.pem

PUBKEY=$(openssl rsa -in key.pem -pubout | tail -n +2 | head -n -1 | tr -d '\n')
EXT_ID=$(openssl rsa -in key.pem -pubout -outform DER | shasum -a 256 | head -c32 | tr 0-9a-f a-p)

sed -i "s/CHROME_EXT_ID=.*/CHROME_EXT_ID=$EXT_ID/" .env
sed -i "s#\"key\": \".*\"#\"key\": \"$PUBKEY\"#" src/manifest.json
```

Then, you can use Chromium or Chrome to sign the extension:

```sh
google-chrome --pack-extension=web-ext-artifacts/extension --pack-extension-key=key.pem
```

### Install scripts

`./scripts/gen-installer.sh` will generate a install script for the native component
of the extension, for each supported target, using POSIX sh on *nix targets and
Powershell 5.1 on Windows targets.

### Virtual machines

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
