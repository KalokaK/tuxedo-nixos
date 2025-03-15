{ lib, stdenv, fetchurl, rpm, cpio, wrapGAppsHook
, nss, gtk3, libappindicator-gtk3, libayatana-appindicator
, glib, cairo, pango, gdk-pixbuf, atk, xorg
, cups, dbus, libsecret, systemd }:

let 
  rpath = lib.makeLibraryPath [
    nss
    gtk3
    libappindicator-gtk3
    libayatana-appindicator
    glib
    cairo
    pango
    gdk-pixbuf
    atk
    xorg.libX11
    xorg.libXScrnSaver
    xorg.libXcomposite
    xorg.libXcursor
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXi
    xorg.libXrandr
    xorg.libXrender
    cups
    dbus
    libsecret
    systemd
    xorg.libxshmfence
  ] + ":${stdenv.cc.cc.lib}/lib64";
in
stdenv.mkDerivation rec {
  pname = "tuxedo-control-center-bin";
  version = "2.1.16";

  src = fetchurl {
    url = "https://rpm.tuxedocomputers.com/fedora/40/x86_64/base/tuxedo-control-center_${version}.rpm";
    sha256 = "1vamldcmryp0gqa46aib51lki97vhi8hwdrl684hdq08dkhpmjz6";
  };

  nativeBuildInputs = [ 
    rpm 
    cpio 
    ## wrapGAppsHook 
  ];

  buildInputs = [
    
  ];

  dontBuild = true;

  unpackPhase = ''
    rpm2cpio $src | cpio -idmv
  '';

  installPhase = ''
    mkdir -p $out
    cp -r usr/* $out
    cp -r opt $out

    mkdir -p $out/bin
    ln -sfv $out/opt/tuxedo-control-center/tuxedo-control-center $out/bin/tuxedo-control-center

    install -Dm644 opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/dist-data/tuxedo-control-center.desktop \
      $out/share/applications/tuxedo-control-center.desktop
    install -Dm644 opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/dist-data/com.tuxedocomputers.tccd.policy \
      $out/share/polkit-1/actions/com.tuxedocomputers.tccd.policy
    install -Dm644 opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/dist-data/com.tuxedocomputers.tccd.conf \
      $out/share/dbus-1/system.d/com.tuxedocomputers.tccd.conf
    install -Dm644 opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/dist-data/tccd.service \
      $out/lib/systemd/system/tccd.service
    install -Dm644 opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/dist-data/tccd-sleep.service \
      $out/lib/systemd/system/tccd-sleep.service
  '';

  # preFixup = ''
  #   gappsWrapperArgs+=(
  #     --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath buildInputs}"
  #   )
  # '';

  postFixup = ''
    patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" --set-rpath "${rpath}:$out/opt/tuxedo-control-center" "$out/opt/tuxedo-control-center/tuxedo-control-center"
    patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" --set-rpath "${rpath}:$out/opt/tuxedo-control-center" "$out/opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/service/tccd"
  '';

  meta = {
    description = "Control performance, energy, fan, and comfort settings on TUXEDO laptops";
    homepage = "https://github.com/tuxedocomputers/tuxedo-control-center";
    license = lib.licenses.gpl3;
    platforms = [ "x86_64-linux" ];
    maintainers = [ "KalokaK" ];
  };
}