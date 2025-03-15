{
  description = "System Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-compat}: let 
      system = "x86_64-linux";
    in {

    packages.${system}.default =
      # Is there a simpler way to whitelist electron?
      (import nixpkgs {
        currentSystem = system;
        localSystem = system;
      }).pkgs.callPackage ./nix/tuxedo-control-center {};

    nixosModules.default = {config, pkgs, ...}: {
      _module.args.tuxedo-control-center = self.packages.${system}.default;
      imports = [ ./nix/module.nix ];
    };
  };
}
