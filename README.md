tab-reload-notify
=================

This Firefox browser extension automatically reloads tabs using the file URI
scheme when their content changes, by using file watch primitives. The Rust
crate `notify` is used, thus supporting the following backends:

 - Linux: inotify
 - macOS: FSEvent/kqueue
 - *BSD: kqueue
 - Windows: ReadDirectoryChanges


## Building

To build the extension, you will need `npm`, `make`, `jq` and a nightly Rust toolchain.
After having installed the dependencies, run:

```sh
npm i --package-lock-only
make build install run
```

That command will build the extension and the file watch server, then install
the server binary and native messaging manifest to your local, per-user Firefox
directory and run a new Firefox debugging session with the extension enabled.

## Development

For development, you will also need to install the dependencies outlined in
`scripts/gen-installer.sh` and `scripts/run-vm-tests.sh`.
