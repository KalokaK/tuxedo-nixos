{
  pkgs,
  lib,
  stdenv,
  copyDesktopItems,
  python3,
  udev,
  makeWrapper,
  nodejs_20,
  nodejs-14_x,
  electron_37,
  fetchFromGitHub,
  nvidiaPackage ? null,
}:

let
  ## Update Instructions
  #
  # see ./README.md
  version = "2.1.16";

  # keep in sync with update.sh!
  # otherwise the format of package.json does not mach the format used by the
  # version used by nixpkgs, leading to errors such as:
  #   > npm ERR! code ENOTCACHED
  #   > npm ERR! request to https://registry.npmjs.org/node-ble failed: cache mode is 'only-if-cached' but no cached response is available.
  nodejs = nodejs-14_x;

  runtime-dep-path = lib.makeBinPath (
    (import ../runtime-dep-pkgs.nix) { inherit pkgs lib nvidiaPackage; }
  );

  baseNodePackages = (
    import ./node-composition.nix {
      inherit pkgs nodejs;
      inherit (stdenv.hostPlatform) system;
    }
  );

  nodePackages = baseNodePackages.package.override {
    src = fetchFromGitHub {
      owner = "tuxedocomputers";
      repo = "tuxedo-control-center";
      rev = "v${version}";
      sha256 = "odGx1S6F5UVK73QjMI1np9Fx/QawRA+jnK/ZTzV6joI=";
    };

    preRebuild = ''
      # the shebang of this file does not work as is in nix;
      # usually this is taken care of with patch-shebangs.sh,
      # but that only handles files marked as executable.
      # thus mark the file as executable before the hook runs.
      chmod +x ./node_modules/electron-builder/out/cli/cli.js
      # and since this runs *after* patch-shebangs ran,
      # manually execute patch-shebangs for this specific file.
      patchShebangs ./node_modules/electron-builder/out/cli/cli.js
    '';

    buildInputs = [ udev ];

    # Electron tries to download itself if this isn't set. We don't
    # like that in nix so let's prevent it.
    #
    # This means we have to provide our own electron binaries when
    # wrapping this program.
    ELECTRON_SKIP_BINARY_DOWNLOAD = 1;

    # Angular prompts for analytics, which in turn fails the build.
    #
    # We can disable analytics using false or empty string
    # (See https://github.com/angular/angular-cli/blob/1a39c5202a6fe159f8d7db85a1c186176240e437/packages/angular/cli/models/analytics.ts#L506)
    NG_CLI_ANALYTICS = "false";
  };

in
stdenv.mkDerivation rec {
  pname = "tuxedo-control-center";
  inherit version;

  src = "${nodePackages}/lib/node_modules/tuxedo-control-center/";

  nativeBuildInputs = [ copyDesktopItems ];

  buildInputs = [
    nodejs
    makeWrapper
    udev

    # For node-gyp
    (python3.withPackages (p-pkgs: with p-pkgs; [ setuptools ]))
  ];

  # These are installed in the right place via copyDesktopItems.
  desktopItems = [
    "src/dist-data/tuxedo-control-center.desktop"
    "src/dist-data/tuxedo-control-center-tray.desktop"
  ];

  # TCC by default writes its config to /etc/tcc, which is
  # inconvenient. Change this to a more standard location.
  #
  # It also hardcodes binary paths.
  postPatch = ''
    substituteInPlace src/common/classes/TccPaths.ts \
      --replace "/etc/tcc" "/var/lib/tcc" \
      --replace "/opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/service/tccd" "$out/bin/tccd" \
      --replace "/opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/camera/" "$out/cameractrls/"

    for desktopFile in ${lib.concatStringsSep " " desktopItems}; do
      substituteInPlace $desktopFile \
        --replace "/opt/tuxedo-control-center/tuxedo-control-center" "$out/bin/tuxedo-control-center" \
        --replace "/opt/tuxedo-control-center/resources/dist/tuxedo-control-center" $out
    done
  '';

  buildPhase = ''
    runHook preBuild

    # We already have `node_modules` in the current directory but we
    # need it's binaries on `PATH` so we can use them!
    export PATH="./node_modules/.bin:$PATH"
    ${pkgs.which}/bin/which npm
    ${pkgs.which}/bin/which node
    ${pkgs.which}/bin/which node-gyp
    # exit 1
    # ${pkgs.which}/bin/which node-gyp
    # Prevent npm from checking for updates
    export NO_UPDATE_NOTIFIER=true

    # The order of `npm` commands matches what `npm run build-prod` does but we split
    # it out so we can customise the native builds in `npm run build-service`.
    npm run clean
    npm run build-electron

    # We don't use `npm run build-service` here because it uses `pkg` which packages
    # node binaries in a way unsuitable for nix. Instead we're doing it ourself.
    tsc -p ./src/service-app
    cp ./src/package.json ./dist/tuxedo-control-center/service-app/package.json

    # We need to tell npm where to find node or `node-gyp` will try to download it.
    # This also _needs_ to be lowercase or `npm` won't detect it
    export npm_config_nodedir=${nodejs}
    # ${pkgs.which}/bin/which node-gyp
    # ${pkgs.nodePackages.node-gyp}/bin/
    node-gyp configure
    node-gyp rebuild # Builds to ./build/Release/TuxedoIOAPI.node

    npm run build-ng-prod

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    # mkdir -p $out/full_root
    # cp -R ./* $out/full_root
    cp -R ./dist/tuxedo-control-center/* $out

    ln -s $src/node_modules $out/node_modules

    # Parts of the code expect the icons to live under `data/dist-data`. Let's just
    # copy the whole thing since the system assumes it has access to all the `dist-data`
    # files.
    mkdir -p $out/data/dist-data
    mkdir -p $out/cameractrls
    cp -R ./src/dist-data/* $out/data/dist-data/
    cp -R ./src/cameractrls/* $out/cameractrls/

    # Install `tccd`
    mkdir -p $out/data/service
    cp ./build/Release/TuxedoIOAPI.node $out/service-app/native-lib/TuxedoIOAPI.node
    makeWrapper ${nodejs_20}/bin/node $out/data/service/tccd \
                --add-flags "$out/service-app/service-app/main.js" \
                --prefix NODE_PATH : $out/data/service \
                --prefix NODE_PATH : $out/node_modules \
                --prefix PATH : ${runtime-dep-path}
    mkdir -p $out/bin
    ln -s $out/data/service/tccd $out/bin/tccd

    # Install `tuxedo-control-center`
    #
    # We use `--no-tccd-version-check` because the app uses the electron context
    # to determine the app version, but the electron context is wrong if electron
    # is invoked directly on a JavaScript file.
    #
    # The fix is to run electron on a folder with a `package.json` but the `tuxedo-control-center`
    # package.json expects all files to live under `dist/` and I'm not a huge fan of that
    # structure so we just disable the check and call it a day.
    makeWrapper ${electron_37}/bin/electron $out/bin/tuxedo-control-center \
                --add-flags "$out/e-app/e-app/main.js" \
                --add-flags "--no-tccd-version-check" \
                --prefix NODE_PATH : $out/node_modules

    mkdir -p $out/share/polkit-1/actions/
    cp $out/data/dist-data/com.tuxedocomputers.tccd.policy $out/share/polkit-1/actions/com.tuxedocomputers.tccd.policy

    mkdir -p $out/etc/dbus-1/system.d/
    cp $out/data/dist-data/com.tuxedocomputers.tccd.conf $out/etc/dbus-1/system.d/com.tuxedocomputers.tccd.conf

    # Put our icons in the right spot
    mkdir -p $out/share/icons/hicolor/scalable/apps/
    cp $out/data/dist-data/tuxedo-control-center_256.svg \
       $out/share/icons/hicolor/scalable/apps/tuxedo-control-center.svg

    runHook postInstall
  '';

  dontPatchELF = true;
  # noAuditTmpdir = true;

  meta = with lib; {
    description = "Fan and power management GUI for Tuxedo laptops";
    homepage = "https://github.com/tuxedocomputers/tuxedo-control-center/";
    license = licenses.gpl3Plus;
    maintainers = [ "KalokaK" ];
    platforms = [ "x86_64-linux" ];
  };
}
