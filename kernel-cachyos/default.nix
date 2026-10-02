{
  inputs,
  callPackage,
  lib,
  ...
}:
let
  makefileLines = lib.splitString "\n" (builtins.readFile (inputs.kernel-src + "/Makefile"));
  makeValue =
    name:
    lib.removePrefix "${name} = " (
      lib.findFirst (lib.hasPrefix "${name} = ") (throw "Missing ${name} in the kernel Makefile")
        makefileLines
    );
  version = lib.concatStringsSep "." (
    map makeValue [
      "VERSION"
      "PATCHLEVEL"
      "SUBLEVEL"
    ]
  );
  patchVersion = lib.versions.majorMinor version;

  kernel = (callPackage ./mkCachyKernel.nix { }) {
    pname = "linux-cachyos";
    inherit version;
    src = inputs.kernel-src;
    cachyosConfigFile = inputs.cachyos-config + "/linux-cachyos/config";
    cachyosPatchesSrc = inputs.kernel-patches + "/${patchVersion}";
    lto = "thin";
    processorOpt = "x86_64-v4";
    cpusched = "eevdf";
    hzTicks = "1000";
    bbr3 = true;
  };
in
{
  linux-cachyos = kernel;
  linux-cachyos-latest = kernel;
}
