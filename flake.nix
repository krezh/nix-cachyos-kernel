{
  description = "CachyOS kernel";

  inputs = {
    # Newer nixpkgs LLVM closures leave local libbpf symbols unresolved in resolve_btfids.
    nixpkgs.url = "github:NixOS/nixpkgs/545c226a9af7f59fba5c3873f7c6a65e014c8f5f";

    kernel-src = {
      url = "github:CachyOS/linux/cachyos-7.2.8-1";
      flake = false;
    };

    cachyos-config = {
      url = "github:CachyOS/linux-cachyos";
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

      overlays.default = _final: _prev: {
        cachyosKernels = packageSet;
      };
    };
}
