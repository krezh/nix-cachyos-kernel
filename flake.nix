{
  description = "CachyOS kernel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";

    kernel-src = {
      url = "github:CachyOS/linux/cachyos-7.2.8-1";
      flake = false;
    };

    cachyos-config = {
      url = "github:CachyOS/linux-cachyos";
      flake = false;
    };

    kernel-patches = {
      url = "github:CachyOS/kernel-patches";
      flake = false;
    };
  };

  nixConfig = {
    extra-substituters = [
      "https://attic.xuyh0120.win/lantian"
    ];
    extra-trusted-public-keys = [
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
    ];
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      mkPackages =
        pkgs:
        let
          load =
            path:
            pkgs.lib.removeAttrs
              (pkgs.callPackage path {
                inherit inputs;
              })
              [
                "override"
                "overrideDerivation"
              ];
        in
        load ./kernel-cachyos // load ./kernel-cachyos/packages.nix;

      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowInsecurePredicate = _: true;
        };
      };
      packageSet = mkPackages pkgs;
      kernels = pkgs.lib.filterAttrs (_: pkgs.lib.isDerivation) packageSet;
    in
    {
      packages.${system} = kernels // {
        default = kernels.linux-cachyos;
      };

      legacyPackages.${system} = packageSet;
      overlay = self.overlays.default;

      overlays.default = final: _prev: {
        cachyosKernels = mkPackages final;
      };
    };
}
