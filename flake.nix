{
  description = "System Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    old-nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-22.11";
    };

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, old-nixpkgs, flake-compat }: let 
      system = "x86_64-linux";
    in {

    packages.${system}.default =
      # Is there a simpler way to whitelist electron?
      (import nixpkgs {
        currentSystem = system;
        localSystem = system;
        config = {
          allowInsecure = true;
          permittedInsecurePackages = [
            # "electron-13.6.9"
            "nodejs-14.21.3"
            # "openssl-1.1.1t"
            # "openssl-1.1.1u"
            # "openssl-1.1.1v"
            # "openssl-1.1.1w"
          ];
        };
      }).pkgs.callPackage ./nix/tuxedo-control-center { nodejs-14_x = old-nixpkgs.legacyPackages.${system}.nodejs-14_x; };

    nixosModules.default = import ./nix/module.nix;
  };
}
