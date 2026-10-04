{
  inputs,
  callPackage,
  linuxKernel,
  ...
}:
let
  helpers = callPackage ../helpers.nix { };
  kernel = (callPackage ./. { inherit inputs; }).linux-cachyos;
  packages = helpers.kernelModuleLLVMOverride (linuxKernel.packagesFor kernel);
in
{
  linuxPackages-cachyos = packages;
}
