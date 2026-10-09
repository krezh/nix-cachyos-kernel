{
  description = "CachyOS kernel";

  inputs = {
    # Newer nixpkgs LLVM closures leave local libbpf symbols unresolved in resolve_btfids.
    nixpkgs.url = "github:NixOS/nixpkgs/545c226a9af7f59fba5c3873f7c6a65e014c8f5f";
  };

  nixConfig = {
    extra-substituters = [ ];
    extra-trusted-public-keys = [ ];
  };

  outputs =
    { self, nixpkgs }:
    let
      sources = import ./kernel-cachyos/sources.nix;
      system = "x86_64-linux";
      mkPackages =
        pkgs:
        let
          load =
            path:
            pkgs.lib.removeAttrs
              (pkgs.callPackage path {
                inherit sources;
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
      updateSources = pkgs.writeShellApplication {
        name = "update-sources";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
          pkgs.nix-prefetch-github
        ];
        text = builtins.readFile ./.github/scripts/update-sources.sh;
      };
      kernels = pkgs.lib.filterAttrs (_: pkgs.lib.isDerivation) packageSet;
    in
    {
      packages.${system} = kernels // {
        default = kernels.linux-cachyos;
      };

      apps.${system}.update-sources = {
        type = "app";
        program = pkgs.lib.getExe updateSources;
      };

      legacyPackages.${system} = packageSet;
      overlay = self.overlays.default;

      overlays.default = _final: _prev: {
        cachyosKernels = packageSet;
      };
    };
}
