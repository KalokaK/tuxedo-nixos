{
  description = "System Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-compat,
    }:
    let
      system = "x86_64-linux";
    in
    {

      # nodejs 24 and electron 41 are both packaged in nixpkgs 26.05, so we no
      # longer need an old nixpkgs pin or any insecure-package whitelisting.
      packages.${system}.default =
        nixpkgs.legacyPackages.${system}.callPackage ./nix/tuxedo-control-center { };

      nixosModules.default =
        { config, pkgs, ... }:
        {
          _module.args.tuxedo-control-center = self.packages.${system}.default;
          imports = [ ./nix/module.nix ];
        };
    };
}
