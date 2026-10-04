{
  inputs,
  applyPatches,
  buildLinux,
  callPackage,
  kernelPatches,
  lib,
  impureUseNativeOptimizations,
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
  patchVersion = lib.versions.majorMinor version;

  cachyosConfigFile = inputs.cachyos-config + "/linux-cachyos/config";
  helpers = callPackage ../helpers.nix { };

  settings = with lib.kernel; {
    cpusched = {
      bore = {
        SCHED_BORE = yes;
      };
      bmq = {
        SCHED_ALT = yes;
        SCHED_BMQ = yes;
      };
      eevdf = { };
      rt = {
        PREEMPT_RT = yes;
      };
      rt-bore = {
        PREEMPT_RT = yes;
        SCHED_BORE = yes;
      };
    };
    lto = {
      none = {
        LTO_NONE = yes;
        LTO_CLANG_THIN = no;
        LTO_CLANG_FULL = no;
      };
      thin = {
        LTO_NONE = no;
        LTO_CLANG_THIN = yes;
        LTO_CLANG_FULL = no;
      };
      full = {
        LTO_NONE = no;
        LTO_CLANG_THIN = no;
        LTO_CLANG_FULL = yes;
      };
    };
    hzTicks = {
      "300" = {
        HZ_300 = yes;
        HZ = freeform "300";
      };
    }
    // lib.genAttrs [ "100" "250" "500" "600" "750" "1000" ] (hz: {
      HZ_300 = no;
      "HZ_${hz}" = yes;
      HZ = freeform hz;
    });
    tickrate = {
      periodic = {
        HZ_PERIODIC = yes;
        NO_HZ_IDLE = no;
        NO_HZ_FULL = no;
      };
      idle = {
        HZ_PERIODIC = no;
        NO_HZ_IDLE = yes;
        NO_HZ_FULL = no;
      };
      full = {
        HZ_PERIODIC = no;
        NO_HZ_IDLE = no;
        NO_HZ_FULL = yes;
      };
    };
    preemptType = {
      full = {
        PREEMPT = yes;
        PREEMPT_LAZY = no;
      };
      lazy = {
        PREEMPT = no;
        PREEMPT_LAZY = yes;
      };
    };
    hugepage = {
      always = {
        TRANSPARENT_HUGEPAGE_ALWAYS = yes;
        TRANSPARENT_HUGEPAGE_MADVISE = no;
        TRANSPARENT_HUGEPAGE_NEVER = no;
      };
      madvise = {
        TRANSPARENT_HUGEPAGE_ALWAYS = no;
        TRANSPARENT_HUGEPAGE_MADVISE = yes;
        TRANSPARENT_HUGEPAGE_NEVER = no;
      };
      never = {
        TRANSPARENT_HUGEPAGE_ALWAYS = no;
        TRANSPARENT_HUGEPAGE_MADVISE = no;
        TRANSPARENT_HUGEPAGE_NEVER = yes;
      };
    };
    processorOpt = {
      x86_64-v1 = {
        GENERIC_CPU = yes;
        MZEN4 = no;
        X86_NATIVE_CPU = no;
        X86_64_VERSION = freeform "1";
      };
      x86_64-v2 = {
        GENERIC_CPU = yes;
        MZEN4 = no;
        X86_NATIVE_CPU = no;
        X86_64_VERSION = freeform "2";
      };
      x86_64-v3 = {
        GENERIC_CPU = yes;
        MZEN4 = no;
        X86_NATIVE_CPU = no;
        X86_64_VERSION = freeform "3";
      };
      x86_64-v4 = {
        GENERIC_CPU = yes;
        MZEN4 = no;
        X86_NATIVE_CPU = no;
        X86_64_VERSION = freeform "4";
      };
      zen4 = {
        GENERIC_CPU = no;
        MZEN4 = yes;
        X86_NATIVE_CPU = no;
      };
      native = {
        GENERIC_CPU = no;
        MZEN4 = no;
        X86_NATIVE_CPU = yes;
      };
    };
  };

  mkKernel =
    {
      cpusched ? "eevdf",
      lto ? "thin",
      hzTicks ? "1000",
      kcfi ? false,
      performanceGovernor ? false,
      tickrate ? "full",
      preemptType ? "full",
      ccHarder ? true,
      bbr3 ? true,
      hugepage ? "always",
      processorOpt ? "x86_64-v4",
      hardened ? false,
      rt ? false,
      acpiCall ? false,
      handheld ? false,
      autofdo ? false,
      prePatch ? "",
      patches ? [ ],
      postPatch ? "",
      autoModules ? true,
      structuredExtraConfig ? { },
      ...
    }@args:
    assert autofdo != false -> lto != "none";
    assert cpusched == "rt" || cpusched == "rt-bore" -> rt;
    let
      cachyosPatches = builtins.map (patch: "${inputs.kernel-patches}/${patchVersion}/${patch}") (
        lib.optional (cpusched == "bore" || cpusched == "rt-bore") "sched/0001-bore-cachy.patch"
        ++ lib.optional (cpusched == "bmq") "sched/0001-prjc-cachy.patch"
        ++ lib.optional hardened "misc/0001-hardened.patch"
        ++ lib.optional rt "misc/0001-rt-i915.patch"
        ++ lib.optional acpiCall "misc/0001-acpi-call.patch"
        ++ lib.optional handheld "misc/0001-handheld.patch"
      );
      patchedSrc = applyPatches {
        name = "linux-src-patched";
        src = inputs.kernel-src;
        patches = [
          kernelPatches.bridge_stp_helper.patch
          kernelPatches.request_key_helper.patch
        ]
        ++ cachyosPatches
        ++ patches;
        inherit prePatch;
        postPatch = ''
          install -Dm644 ${cachyosConfigFile} arch/x86/configs/cachyos_defconfig
        ''
        + postPatch;
      };
      localVersion = if lto == "none" then "-cachyos" else "-cachyos-lto";
      profileConfig =
        with lib.kernel;
        {
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
        }
        // settings.lto.${lto}
        // lib.optionalAttrs (cpusched != null) settings.cpusched.${cpusched}
        // lib.optionalAttrs (hzTicks != null) settings.hzTicks.${hzTicks}
        // lib.optionalAttrs (tickrate != null) settings.tickrate.${tickrate}
        // lib.optionalAttrs (preemptType != null) settings.preemptType.${preemptType}
        // lib.optionalAttrs (hugepage != null) settings.hugepage.${hugepage}
        // lib.optionalAttrs (processorOpt != null) settings.processorOpt.${processorOpt}
        // lib.optionalAttrs kcfi {
          ARCH_SUPPORTS_CFI_CLANG = yes;
          CFI_CLANG = yes;
          CFI_AUTO_DEFAULT = yes;
        }
        // lib.optionalAttrs performanceGovernor {
          CPU_FREQ_DEFAULT_GOV_SCHEDUTIL = no;
          CPU_FREQ_DEFAULT_GOV_PERFORMANCE = yes;
        }
        // lib.optionalAttrs ccHarder {
          CC_OPTIMIZE_FOR_PERFORMANCE = no;
          CC_OPTIMIZE_FOR_PERFORMANCE_O3 = yes;
        }
        // lib.optionalAttrs bbr3 {
          TCP_CONG_CUBIC = module;
          DEFAULT_CUBIC = no;
          TCP_CONG_BBR3 = yes;
          DEFAULT_BBR3 = yes;
          DEFAULT_TCP_CONG = freeform "bbr3";
          NET_SCH_FQ_CODEL = module;
          DEFAULT_FQ_CODEL = no;
          NET_SCH_FQ = yes;
          DEFAULT_FQ = yes;
        }
        // lib.optionalAttrs (autofdo != false) {
          AUTOFDO_CLANG = yes;
        }
        // lib.optionalAttrs hardened {
          RUST = no;
        }
        // structuredExtraConfig;
    in
    buildLinux (
      (lib.removeAttrs args [
        "cpusched"
        "lto"
        "hzTicks"
        "kcfi"
        "performanceGovernor"
        "tickrate"
        "preemptType"
        "ccHarder"
        "bbr3"
        "hugepage"
        "processorOpt"
        "hardened"
        "rt"
        "acpiCall"
        "handheld"
        "autofdo"
        "prePatch"
        "patches"
        "postPatch"
        "autoModules"
        "structuredExtraConfig"
      ])
      // {
        pname = "linux-cachyos";
        inherit version;
        src = patchedSrc;
        stdenv = (if processorOpt == "native" then impureUseNativeOptimizations else lib.id) (
          if lto == "none" then stdenv else helpers.stdenvLLVM
        );
        extraMakeFlags =
          lib.optionals (lto != "none") helpers.ltoMakeflags
          ++ lib.optionals (builtins.isPath autofdo) [ "CLANG_AUTOFDO_PROFILE=${autofdo}" ]
          ++ (args.extraMakeFlags or [ ]);
        defconfig = "cachyos_defconfig";
        modDirVersion = "${lib.versions.pad 3 version}${localVersion}";
        ignoreConfigErrors = true;
        structuredExtraConfig = lib.mapAttrs (_: lib.mkForce) profileConfig;
        inherit autoModules;

        extraMeta = {
          description = "Configurable Linux CachyOS kernel";
          broken = !stdenv.hostPlatform.isx86_64;
        };

        extraPassthru = {
          inherit cachyosConfigFile;
        };
      }
    );
in
{
  linux-cachyos = lib.makeOverridable mkKernel { };
}
