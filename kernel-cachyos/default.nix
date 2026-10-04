{
  inputs,
  applyPatches,
  buildLinux,
  callPackage,
  kernelPatches,
  lib,
  stdenv,
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

  cachyosConfigFile = inputs.cachyos-config + "/linux-cachyos/config";
  localVersion = "-cachyos-lto";
  helpers = callPackage ../helpers.nix { };

  src = applyPatches {
    name = "linux-src-patched";
    src = inputs.kernel-src;
    patches = [
      kernelPatches.bridge_stp_helper.patch
      kernelPatches.request_key_helper.patch
    ];
    postPatch = ''
      install -Dm644 ${cachyosConfigFile} arch/x86/configs/cachyos_defconfig
    '';
  };

  profileConfig = with lib.kernel; {
    NR_CPUS = option (freeform "8192");
    LOCALVERSION = freeform localVersion;

    OVERLAY_FS = module;
    OVERLAY_FS_REDIRECT_DIR = no;
    OVERLAY_FS_REDIRECT_ALWAYS_FOLLOW = yes;
    OVERLAY_FS_INDEX = no;
    OVERLAY_FS_XINO_AUTO = no;
    OVERLAY_FS_METACOPY = no;
    OVERLAY_FS_DEBUG = no;
    HID = yes;

    CACHY = yes;
    MQ_IOSCHED_ADIOS = yes;

    LTO_NONE = no;
    LTO_CLANG_THIN = yes;
    LTO_CLANG_FULL = no;

    HZ_300 = no;
    HZ_1000 = yes;
    HZ = freeform "1000";

    HZ_PERIODIC = no;
    NO_HZ_IDLE = no;
    NO_HZ_FULL = yes;

    PREEMPT = yes;
    PREEMPT_LAZY = no;

    CC_OPTIMIZE_FOR_PERFORMANCE = no;
    CC_OPTIMIZE_FOR_PERFORMANCE_O3 = yes;

    TCP_CONG_CUBIC = module;
    DEFAULT_CUBIC = no;
    TCP_CONG_BBR3 = yes;
    DEFAULT_BBR3 = yes;
    DEFAULT_TCP_CONG = freeform "bbr3";
    NET_SCH_FQ_CODEL = module;
    DEFAULT_FQ_CODEL = no;
    NET_SCH_FQ = yes;
    DEFAULT_FQ = yes;
    TRANSPARENT_HUGEPAGE_MADVISE = no;
    TRANSPARENT_HUGEPAGE_NEVER = no;

    TRANSPARENT_HUGEPAGE_ALWAYS = yes;

    MZEN4 = no;
    X86_NATIVE_CPU = no;
    GENERIC_CPU = yes;
    X86_64_VERSION = freeform "4";
  };

  kernel = buildLinux {
    pname = "linux-cachyos";
    inherit src version;
    stdenv = helpers.stdenvLLVM;
    extraMakeFlags = helpers.ltoMakeflags;
    defconfig = "cachyos_defconfig";
    modDirVersion = "${lib.versions.pad 3 version}${localVersion}";
    ignoreConfigErrors = true;
    structuredExtraConfig = lib.mapAttrs (_: lib.mkForce) profileConfig;
    autoModules = true;

    extraMeta = {
      description = "Linux CachyOS Kernel with Clang+ThinLTO";
      broken = !stdenv.hostPlatform.isx86_64;
    };

    extraPassthru = {
      inherit cachyosConfigFile;
    };
  };
in
{
  linux-cachyos = kernel;
}
