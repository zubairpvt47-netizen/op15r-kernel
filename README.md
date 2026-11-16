<div align="center">

# OnePlus 15R Kernel

**A custom GKI kernel for the OnePlus 15R (CPH2767)**
KernelSU · SUSFS · NoMount · ZeroMount · Baseband Guard · NTSync · networking · CIFS

![Device](https://img.shields.io/badge/device-OnePlus%2015R%20(CPH2767)-eb0028?style=flat-square)
![Kernel](https://img.shields.io/badge/kernel-GKI%20android16--6.12-3ddc84?style=flat-square)
![Root](https://img.shields.io/badge/root-KernelSU-8250df?style=flat-square)
![Built by](https://img.shields.io/badge/built%20by-GitHub%20Actions-2b3137?style=flat-square)
![License](https://img.shields.io/badge/license-GPL--3.0-lightgrey?style=flat-square)

[Features](#features) · [How it works](#how-it-works) · [Build](#building) · [Install](#installing) · [Rollback](#rollback) · [Credits](#credits)

</div>

---

## Overview

The OnePlus 15R ships Google's unmodified **GKI** kernel, and Google publishes the exact source for it.
This project rebuilds that same kernel for the phone's firmware, in CI, and adds the feature set below.

- **Matches your firmware.** The build is pinned to the exact upstream commit your phone runs (`expect_commit`), so vendor modules keep working.
- **Reproducible.** Everything is built from source by a public workflow. The kernel is never committed; the only prebuilt binaries are the stock AnyKernel3 flasher helpers (`busybox`, `magiskboot`, ...) vendored unchanged in `android16-6.12/anykernel3/tools`.
- **Safe by construction.** The NTSync step is atomic, the final `.config` is checked for every enabled feature, and the build keeps stock module-compatibility settings.

Current default: firmware `CPH2767_17.0.0.106(EX01)`, kernel 6.12.69, upstream source `android16-6.12-2026-03_r54` (`242e1a07f878`).
`uname -r` reports `6.12.69-android16-6-4k-OP15R-Core-<release_version>`.

## Features

### Root and mount hiding
| | |
|---|---|
| **KernelSU** | Official [tiann/KernelSU](https://github.com/tiann/KernelSU) `main`, built into the kernel at a pinned commit. No LKM or `init_boot` patch needed. Use the manager built from the same commit (see Installing). |
| **SUSFS** | susfs4ksu with its KernelSU enable patch: path, mount, kstat and map hiding, uname and cmdline/bootconfig spoofing, open redirect, symbol hiding, priority UID filter. Debug logging off. |
| **NoMount** | Built-in systemless path redirection at the VFS layer (`fs/nomount`), driven by the NoMount module. |
| **ZeroMount** | Built-in VFS path redirection (`/dev/zeromount`, `fs/zeromount.c`, needs SUSFS), driven by the ZeroMount module. Present alongside NoMount; use one module at a time. |
| **Baseband Guard** | Security module that blocks writes to critical baseband/modem block devices. It gets its own LSM slot so the stock BPF LSM is not displaced. |

### Extras
| | |
|---|---|
| **NTSync** | NT synchronization primitives for Winlator/GameHub (`/dev/ntsync`). Replaces the stock driver, whose Kconfig entry is marked `BROKEN`, with the current one. |
| **Networking** | BBR (default congestion control) with fq_codel (default qdisc), Westwood, HTCP, `fq`, CAKE, ip_set (up to 65534 sets), IPv6 NAT, and the `TTL`/`HL`, `DSCP`, `CONNMARK`, `CLASSIFY`, `IDLETIMER`, `NFLOG`, `HMARK` netfilter targets and matches. |
| **Filesystems** | NTFS3 (read/write USB-OTG drives), exFAT, VFAT, MSDOS, CIFS/SMB client, tmpfs xattr/ACL. |

## How it works

Each build runs these steps in order:

1. **Sync** Google's `kernel/common` at the exact release tag of the phone's kernel, and verify the commit.
2. **KernelSU** is added as a built-in at a pinned commit, with `KSU_VERSION` pinned from the commit count.
3. The pinned **SUSFS** patch and KernelSU enable patch are applied with WildKernels' compatibility helpers.
4. **NoMount** and **ZeroMount** are added as built-ins.
5. **NTSync** is applied atomically (rolled back if any patch fails) and the networking configs are added.
6. **Baseband Guard**, its LSM slot and the Kconfig fragment are added.
7. **Build** with Kleaf/Bazel, check the final `.config` for every enabled feature, then package an AnyKernel3 zip and the raw `Image`.

<details>
<summary>Stock-compatibility guard rails</summary>

The phone loads hundreds of vendor modules built against Google's GKI ABI, so the build mirrors the stock kernel:

| Stock property (read from the device) | Handling in this build |
|---|---|
| `MODVERSIONS`, `PREEMPT`, `MODULE_UNLOAD` (vermagic flags `SMP preempt mod_unload modversions`) | Stripped from the fragment so they can never change. |
| `LTO_NONE` and `CFI_CLANG` | Built with `--lto=none`, CFI left as stock. |
| Module version CRC checks | CRC mismatch bypass applied, since struct changes from SUSFS/NoMount/ZeroMount can shift CRCs. |
| GKI protected-export enforcement | Protected export lists removed so the kernel does not refuse vendor modules. |
| `ZRAM=m`, `ANDROID_BINDER_IPC_RUST=m` | Left as modules. |
| `CONFIG_IPV6_SUBTREES`, `MAC80211_MESH` | Not enabled: they change struct layouts that vendor modules use. |

</details>

## Building

1. Open **Actions → OnePlus 15R kernel → Run workflow**.
2. Keep the defaults for the current firmware, or toggle individual features.
3. Download the artifact when it finishes:

| File | What it is |
|---|---|
| `*-AnyKernel3.zip` | Flashable from a custom recovery. Replaces only the kernel in the active slot's `boot`. |
| `Image` | Raw arm64 kernel, for repacking or `fastboot boot` testing. |
| `gkid-report.txt` | Which feature groups and patches applied. |
| `final-config.fragment` / `final.config` | The Kconfig fragment used and the final `.config`. |
| `Module.symvers`, `System.map` | ABI evidence for checking vendor-module compatibility. |
| `SHA256SUMS.txt` | Checksums for the files above. |

Pins live in `android16-6.12/root-pins.env`; `ksu_commit`, `susfs_commit` and `nomount_ref` override them for a single run.

**New firmware.** Read the kernel string on the phone (`uname -r`) and take the `g<sha>` part. Find the matching
`android16-6.12-<YYYY-MM>_r<N>` tag in [`kernel/common`](https://android.googlesource.com/kernel/common), then run the
workflow with `common_ref` (`refs/tags/...`), `release_branch` (`android16-6.12-<YYYY-MM>`) and `expect_commit` (the sha).
The build aborts if the source does not match that commit.

## Installing

> **Status: pre-release.** Do not flash a build that has not passed a test boot on your device.

Requirements: an **unlocked bootloader**, `adb` and `fastboot`, and **your own partition backups**.

1. **Back up** from a root shell, for the slot you use:
   ```sh
   S=$(getprop ro.boot.slot_suffix)
   for p in boot init_boot vendor_boot vbmeta dtbo recovery; do
     dd if=/dev/block/by-name/$p$S of=/sdcard/bk_$p$S.img
   done
   ```
2. **Flash** the AnyKernel3 zip from your recovery.
3. **Root.** KernelSU is built in, so use a clean `init_boot` (remove any LKM-patched one) and install the manager APK built from the same KernelSU commit (the pin in `root-pins.env`; KernelSU's CI publishes it as `KernelSU_v<version>-<n>-g<sha>_<code>-release.apk`). The manager and kernel must share the same UAPI version, otherwise the manager reports that it or the kernel needs an update.

## Rollback

```sh
fastboot flash boot_b boot_b.img      # use your active slot letter
```

or flash your saved `boot` image from recovery. The kernel zip only rewrites the kernel inside `boot`; it does not touch
`recovery`, `vendor_boot`, `vbmeta` or `init_boot`.

## Repository layout

```
.github/workflows/build-op15r.yml   single-job pipeline: sync, patch, configure, build, package
android16-6.12/
  anykernel3/                       vendored AnyKernel3 flasher template (own banner/flash log; see SOURCE.txt)
  build-helpers/                    config assembly, ABI-check bypass, LSM-slot, build-flag, BBG and SUSFS compat helpers
  gkid/                             networking config fragments and the NTSync patches
  zeromount/                        ZeroMount VFS patch
  defconfig.fragment                base / susfs / overlayfs Kconfig sections
  root-pins.env                     pinned KernelSU, SUSFS and WildKernels helper commits
scripts/gkid-extras.sh              NTSync (atomic, with rollback) and networking configs, with report
tools/repack_boot.py                builds a test-bootable image from a new kernel
```

## Disclaimer

Custom kernels can stop a device from booting and may void warranty or break apps that check device integrity.
You are responsible for your device. Everything here is provided as is, without warranty. This project is not affiliated
with OnePlus, Google, or any project credited below.

## Credits

| Project | Used for |
|---|---|
| [Android Common Kernel](https://android.googlesource.com/kernel/common) (Google) | Base source |
| [KernelSU](https://github.com/tiann/KernelSU) (tiann) | Root solution |
| [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) (simonpunk) | SUSFS |
| [WildKernels](https://github.com/WildKernels) | SUSFS compatibility scripts, NTSync patches, base of the vendored AnyKernel3 flasher template |
| [NoMount](https://github.com/maxsteeel/nomount) (maxsteeel) | NoMount driver |
| [ZeroMount](https://github.com/enginex0/zeromount) and [Enginex0/Super-Builders](https://github.com/Enginex0/Super-Builders) | ZeroMount driver, build pipeline |
| [GKID-Kernels](https://github.com/ahmed-alnassif/GKID-Kernels) | Networking and filesystem configs |
| [AnyKernel3](https://github.com/osm0sis/AnyKernel3) (osm0sis) | Flashable-zip framework |
| [Baseband-guard](https://github.com/vc-teahouse/Baseband-guard) | Baseband Guard module |

## License

Kernel patches are derived from the Linux kernel and carry **GPL-2.0**. Build scripts and workflows derived from Super-Builders
are **GPL-3.0**. See [LICENSE](LICENSE).
