{
  pkgs,
  lib,
  stdenv,
  copyDesktopItems,
  python3,
  udev,
  makeWrapper,
  nodejs_24,
  electron_41,
  buildNpmPackage,
  fetchFromGitHub,
  nvidiaPackage ? null,
}:

let
  ## Update Instructions
  #
  # see ./README.md
  version = "3.0.6";

  nodejs = nodejs_24;
  electron = electron_41;

  runtime-dep-path = lib.makeBinPath (
    (import ../runtime-dep-pkgs.nix) { inherit pkgs lib nvidiaPackage; }
  );

in
buildNpmPackage rec {
  pname = "tuxedo-control-center";
  inherit version;

  src = fetchFromGitHub {
    owner = "tuxedocomputers";
    repo = "tuxedo-control-center";
    rev = "v${version}";
    hash = "sha256-wb4dj0YjfO9h+1H91dwZL8XSt3oaMe+wmoka4kyMZg8=";
  };

  npmDepsHash = "sha256-QhyU983cEmtv1yXnFf5tJqx40lZp67nuwgfdc2m5kFY=";

  # The lockfile pins three dependencies (dbus-next, node-ble, usocket) to
  # git revisions. buildNpmPackage needs to be told it's OK to use them, and
  # npm needs a writable cache to install them.
  forceGitDeps = true;
  makeCacheWritable = true;

  # Skip lifecycle scripts during dependency installation:
  #   - `electron-builder install-app-deps` would try to rebuild native
  #     modules against electron's headers (and reach the network).
  #   - `patch-package` only patches @electron/rebuild, which we don't use
  #     because we drive node-gyp ourselves.
  # We rebuild the one native module (TuxedoIOAPI) by hand in buildPhase.
  npmFlags = [ "--ignore-scripts" ];

  inherit nodejs;

  nativeBuildInputs = [
    copyDesktopItems
    makeWrapper
    # For node-gyp
    (python3.withPackages (p-pkgs: with p-pkgs; [ setuptools ]))
  ];

  buildInputs = [ udev ];

  # Electron tries to download itself if this isn't set. We provide our own
  # electron binary when wrapping the program below.
  ELECTRON_SKIP_BINARY_DOWNLOAD = 1;

  # Angular prompts for analytics, which fails the build.
  NG_CLI_ANALYTICS = "false";

  # These are installed in the right place via copyDesktopItems.
  desktopItems = [
    "src/dist-data/tuxedo-control-center.desktop"
    "src/dist-data/tuxedo-control-center-tray.desktop"
  ];

  # TCC by default writes its config to /etc/tcc, which is inconvenient.
  # Change this to a more standard location. It also hardcodes binary paths.
  postPatch = ''
    substituteInPlace src/common/classes/TccPaths.ts \
      --replace-fail "/opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/service/tccd" "$out/bin/tccd" \
      --replace-fail "/opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/camera/cameractrls.py" "$out/cameractrls/cameractrls.py" \
      --replace-fail "/opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/camera/v4l2_kernel_names.json" "$out/cameractrls/v4l2_kernel_names.json" \
      --replace-fail "/etc/tcc" "/var/lib/tcc"

    # The two desktop files don't share an identical set of hardcoded paths
    # (e.g. only the main one has the resources/dist icon path), so use
    # --replace-quiet to tolerate a missing pattern in either file.
    for desktopFile in ${lib.concatStringsSep " " desktopItems}; do
      substituteInPlace $desktopFile \
        --replace-quiet "/opt/tuxedo-control-center/tuxedo-control-center" "$out/bin/tuxedo-control-center" \
        --replace-quiet "/opt/tuxedo-control-center/resources/dist/tuxedo-control-center" $out
    done
  '';

  # We run a custom build instead of `npm run build` so we can avoid the
  # parts that don't play nicely with nix (electron download, @yao-pkg/pkg).
  dontNpmBuild = true;

  buildPhase = ''
    runHook preBuild

    export PATH="./node_modules/.bin:$PATH"
    export NO_UPDATE_NOTIFIER=true

    # Tell npm/node-gyp where node lives so it doesn't download headers.
    export npm_config_nodedir=${nodejs}

    npm run clean

    # 1. Electron main process (tsc -> dist/.../e-app)
    npm run build-electron

    # 2. Native module (TuxedoIOAPI.node). Upstream `build-native-prod` runs
    #    `node-gyp configure --release && node-gyp rebuild --release`.
    node-gyp configure --release
    node-gyp rebuild --release # -> ./build/Release/TuxedoIOAPI.node

    # 3. Service daemon.
    #
    # Upstream's `build-service-prod` does: tsc -> copy package.json ->
    # esbuild bundle -> package a self-contained node binary with @yao-pkg/pkg.
    #
    # The raw tsc output cannot be run directly with node: the project compiles
    # to ES modules (module: esnext) with extensionless relative imports, and
    # the native binding (TuxedoIOAPI.js) mixes `export` with a CommonJS
    # `require('./TuxedoIOAPI.node')`. esbuild resolves all of that into a
    # single bundle, which is exactly what upstream runs through pkg.
    #
    # We reproduce the bundle (mirrors the `esbuild-service-prod` script) but
    # skip pkg and run the bundle on the nix-provided node instead.
    tsc -p ./src/service-app
    cp ./src/package.json ./dist/tuxedo-control-center/service-app/package.json
    cp ./build/Release/TuxedoIOAPI.node ./dist/tuxedo-control-center/service-app/native-lib/

    esbuild ./dist/tuxedo-control-center/service-app/service-app/main.js \
      --tree-shaking=true \
      --bundle \
      --minify \
      --drop:debugger \
      --define:DEBUG=false \
      --platform=node \
      --loader:.node=copy \
      --asset-names=[name] \
      --outfile=./dist/tuxedo-control-center/service-app/service-app/esbuild.js

    # 4. Angular renderer (production).
    npm run build-ng-prod

    # 5. Copy runtime data files into dist (mirrors `npm run copy-files`).
    npm run copy-files

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -R ./dist/tuxedo-control-center/* $out

    # The electron app resolves some resources relative to its own location,
    # e.g. the window icon at `data/dist-data/tuxedo-control-center_256.png`
    # (see e-app/.../backendAPIs/browserWindowsAPI.js). The 3.0.6 `copy-files`
    # script places the dist-data files directly under data/, and leaves only
    # a stray `data/dist-data` file (the udev rule). Recreate data/dist-data as
    # a proper directory holding the dist-data files so those lookups resolve.
    rm -f $out/data/dist-data
    mkdir -p $out/data/dist-data
    cp -R ./src/dist-data/* $out/data/dist-data/

    # The service daemon (tccd) and the electron app resolve their runtime
    # dependencies (dbus-next, node-ble, usocket, ...) from node_modules via
    # NODE_PATH. With buildNpmPackage node_modules lives in the build
    # directory, so we copy it into $out (a symlink would dangle).
    cp -R ./node_modules $out/node_modules

    mkdir -p $out/cameractrls
    cp -R ./src/cameractrls/* $out/cameractrls/

    # Install `tccd` (service daemon) wrapped around the nix node.
    #
    # We run the esbuild bundle (esbuild.js), not the raw tsc output: the
    # bundle is self-contained and has the native TuxedoIOAPI.node copied
    # beside it by esbuild's `--loader:.node=copy`.
    makeWrapper ${nodejs}/bin/node $out/bin/tccd \
                --add-flags "$out/service-app/service-app/esbuild.js" \
                --prefix NODE_PATH : $out/service-app \
                --prefix NODE_PATH : $out/node_modules \
                --prefix PATH : ${runtime-dep-path}

    # Install `tuxedo-control-center` (GUI) wrapped around electron.
    #
    # `--no-tccd-version-check` is used because the app uses the electron
    # context to determine its version, which is wrong when electron is
    # invoked directly on a JavaScript file.
    makeWrapper ${electron}/bin/electron $out/bin/tuxedo-control-center \
                --add-flags "$out/e-app/e-app/main.js" \
                --add-flags "--no-tccd-version-check" \
                --prefix NODE_PATH : $out/node_modules

    # NOTE: in 3.0.6 `npm run copy-files` places the dist-data files directly
    # under data/ (not data/dist-data/ as in older versions), so the sources
    # below read from $out/data/.

    # polkit policy
    mkdir -p $out/share/polkit-1/actions/
    cp $out/data/com.tuxedocomputers.tccd.policy $out/share/polkit-1/actions/com.tuxedocomputers.tccd.policy

    # dbus config
    mkdir -p $out/etc/dbus-1/system.d/
    cp $out/data/com.tuxedocomputers.tccd.conf $out/etc/dbus-1/system.d/com.tuxedocomputers.tccd.conf

    # icon
    mkdir -p $out/share/icons/hicolor/scalable/apps/
    cp $out/data/tuxedo-control-center_256.svg \
       $out/share/icons/hicolor/scalable/apps/tuxedo-control-center.svg

    runHook postInstall
  '';

  dontPatchELF = true;

  meta = with lib; {
    description = "Fan and power management GUI for Tuxedo laptops";
    homepage = "https://github.com/tuxedocomputers/tuxedo-control-center/";
    license = licenses.gpl3Plus;
    maintainers = [ "KalokaK" ];
    platforms = [ "x86_64-linux" ];
  };
}
