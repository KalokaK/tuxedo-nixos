# How to update

1. Run `update.sh` with the target version, e.g. `./update.sh 3.0.6`.
   It prints the new `version`, `src.hash` and `npmDepsHash`.
1. Update those three values in [default.nix](./default.nix).
1. Check whether the upstream toolchain changed (node/electron/Angular
   versions in `package.json`). If so, bump `nodejs_*`/`electron_*` in
   [default.nix](./default.nix) and the corresponding inputs in
   [flake.nix](../../flake.nix) accordingly.
1. Check `MOD_API_MIN_VERSION` in
   `src/native-lib/tuxedo_io_lib/tuxedo_io_ioctl.h` upstream against the
   `tuxedo-drivers` version assertion in [module.nix](../module.nix).
1. Build and test:
   - `nix build .#default`
   - `./result/bin/tccd --version`
   - `./result/bin/tuxedo-control-center`

## Packaging notes

The package is built with `buildNpmPackage` (the nixpkgs-native npm
builder). The build does not use `npm run build` directly because parts
of it don't work under nix:

- electron must not download its own binary (`ELECTRON_SKIP_BINARY_DOWNLOAD`);
  we wrap the nix `electron_*` instead.
- the service daemon is bundled with esbuild (mirroring upstream's
  `esbuild-service-prod` script) but **not** packaged with `@yao-pkg/pkg`,
  which produces a node binary unsuitable for nix. We run the esbuild
  bundle on the nix-provided node instead.
- lifecycle scripts are skipped during dependency install
  (`npmFlags = [ "--ignore-scripts" ]`) so `electron-builder
  install-app-deps` and `patch-package` don't run; the one native module
  (`TuxedoIOAPI`) is rebuilt by hand with `node-gyp`.
