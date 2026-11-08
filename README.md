<div align="center">

# OnePlus 15R Kernel

**A custom GKI kernel for the OnePlus 15R (CPH2767)**
SukiSU Ultra · Enhanced SUSFS · ZeroMount VFS · the WildKernels feature set

![Device](https://img.shields.io/badge/device-OnePlus%2015R%20(CPH2767)-eb0028?style=flat-square)
![Kernel](https://img.shields.io/badge/kernel-GKI%20android16--6.12-3ddc84?style=flat-square)
![Root](https://img.shields.io/badge/root-SukiSU%20Ultra-8250df?style=flat-square)
![Built by](https://img.shields.io/badge/built%20by-GitHub%20Actions-2b3137?style=flat-square)
![License](https://img.shields.io/badge/license-GPL--3.0-lightgrey?style=flat-square)

[Supported builds](#supported-builds) · [Features](#features) · [How it works](#how-it-works) · [Build](#building) · [Install](#installing) · [Rollback](#rollback) · [Credits](#credits)

</div>

---

## Overview

The OnePlus 15R ships Google's unmodified **GKI** kernel, and Google publishes the exact source for it.
This project rebuilds that same kernel for each firmware release, in CI, and adds a curated feature set on top.
It tracks only the 15R, so every build here is matched to a specific firmware of this one phone.

- **Matches your firmware.** Each build is pinned to the exact upstream commit your phone runs, so vendor modules keep working.
- **Reproducible.** Everything is built from source by a public workflow. There are no prebuilt binaries in the repo.
- **Safe by construction.** Feature groups apply atomically and the build keeps stock module-compatibility settings.

## Supported builds

| Firmware | Kernel | Upstream source | Status |
|---|---|---|---|
| `CPH2767_17.0.0.106(EX01)` | 6.12.69 | `android16-6.12-2026-03_r54` (`242e1a07f878`) | Pipeline verified, awaiting first build and device test |

New firmware gets a new row. Builds for older firmware stay listed so you can match them to the ROM you run.

## Features

### Root and hiding
| | |
|---|---|
| **SukiSU Ultra** | Built into the kernel at a pinned commit. No LKM or `init_boot` patch needed. |
| **Enhanced SUSFS** | Mount hiding, kstat spoofing and redirect, map hiding, uname and cmdline/bootconfig spoofing, open redirect, symbol hiding, Unicode filter, auto-hide of KSU default and bind mounts. |
| **ZeroMount VFS** | Systemless path redirection at the VFS layer: `getname()` redirection, directory-entry injection, `d_path`/xattr/`statfs` spoofing, bloom-filter lookup, ioctl control interface. |
| **Baseband Guard** | Security module that blocks writes to critical baseband/modem block devices. |

### Networking
| | |
|---|---|
| **BBR** | Selectable TCP congestion control, alongside CUBIC. |
| **Queue disciplines** | `fq`, `fq_codel`, CAKE, PIE, `fq_pie`. |
| **ip_set** | Bitmap, hash and list set types (up to 65534 sets), plus `xt_set` and `addrtype` matches. |
| **IPv6 NAT** | `ip6table_nat` and IPv6 masquerade. |
| **TTL / HL** | `TTL` target and `HL` match/target, commonly used for tethering TTL adjustment. |

### Containers and compatibility
| | |
|---|---|
| **Droidspaces** | `SYSVIPC`, `PID_NS`, `USER_NS`, `POSIX_MQUEUE`, `DEVTMPFS`, `MACVLAN`, netfilter `REJECT`/`LOG`/`recent`, with kABI padding patches so struct layouts stay compatible with stock vendor modules. |
| **NTSync** | Windows NT synchronization primitives for Wine/Proton. |
| **Overlay support** | `TMPFS_XATTR` and `TMPFS_POSIX_ACL`. |
| **Unicode bypass fix** | WildKernels' fix (marked experimental upstream). |

### Performance and tuning
23 WildKernels patches for memory, scheduling and power, CPU frequency, storage, networking and log noise.

<details>
<summary>Show the patch list</summary>

| Area | Patches |
|---|---|
| Memory | `optimized_mem_operations`, `optimise_memcmp`, `clear_page_16bytes_align`, `mem_opt_prefetch`, `reduce_cache_pressure`, `int_sqrt` |
| Scheduler / power | `minimise_wakeup_time`, `adjust_cpu_scan_order`, `disable_cache_hot_buddy`, `avoid_extra_s2idle_wake_attempts`, `reduce_pci_pme_wakeups`, `reduce_freeze_timeout`, `add_timeout_wakelocks_globally` |
| CPU frequency | `add_limitation_scaling_min_freq`, `re_write_limitation_scaling_min_freq`, `use_unlikely_wrap_cpufreq` |
| Storage | `f2fs_reduce_congestion`, `f2fs_enlarge_min_fsync_blocks`, `reduce_gc_thread_sleep_time`, `increase_ext4_default_commit_age` |
| Network | `increase_sk_mem_packets` |
| Logging | `silence_irq_cpu_logspam`, `silence_system_logspam` |

</details>

### Not included
- **HMBird/SCX scheduler** and **BBRv3**: the WildKernels 15R config leaves both off too.
- **OnePlus vendor-module blacklisting and `fake_config`**: these belong to OnePlus' own kernel tree, not GKI.
- **ZRAM LZ4K/LZ4KD**: ZRAM is a module on the stock kernel and stays one.
- **`file_struct_8bytes_align`**: it changes the ABI checksum of `struct file`, which would affect vendor modules.

## How it works

Each build runs these steps in order:

1. **Sync** Google's `kernel/common` at the exact release tag of the phone's kernel, and verify the commit.
2. **SukiSU Ultra** is added as a built-in at a pinned commit.
3. **SUSFS** patches (upstream, enhanced, and a KSU safety fix) are applied.
4. **ZeroMount** is applied on top.
5. **WildKernels** feature groups are applied one by one, each rolled back if any of its patches fails.
6. **Baseband Guard** and the Kconfig fragment are added.
7. **Build** with Kleaf/Bazel, then package an AnyKernel3 zip and the raw `Image`.

**Atomic feature groups.** NTSync, Droidspaces and the Unicode fix are each all-or-nothing. If one patch in a group fails,
the tree is restored to a snapshot and that group's configs stay off. A half-applied Droidspaces set would change
`task_struct` layout and break vendor modules. Results are written to `wild-report.txt` in the build artifacts.

<details>
<summary>Stock-compatibility guard rails</summary>

The phone loads hundreds of vendor modules built against Google's GKI ABI, so the build mirrors the stock kernel:

| Stock property (read from the device) | Handling in this build |
|---|---|
| `MODVERSIONS`, `PREEMPT`, `MODULE_UNLOAD` (vermagic flags `SMP preempt mod_unload modversions`) | Stripped from the fragment so they can never change. |
| `LTO_NONE` and `CFI_CLANG` | Built with `--lto=none`, CFI left as stock. |
| Module version CRC checks | CRC mismatch bypass applied, since struct changes from SUSFS/ZeroMount can shift CRCs. |
| GKI protected-export enforcement | Protected export lists removed so the kernel does not refuse vendor modules. |
| `ZRAM=m`, `ANDROID_BINDER_IPC_RUST=m` | Left as modules; the IPC namespace symbols Rust binder needs are exported. |

</details>

## Building

1. Open **Actions → OnePlus 15R kernel → Run workflow**.
2. Keep the defaults for the current firmware, or toggle individual features.
3. Download the artifact when it finishes:

| File | What it is |
|---|---|
| `*-AnyKernel3.zip` | Flashable from a custom recovery. Replaces only the kernel in the active slot's `boot`. |
| `Image` | Raw arm64 kernel, for repacking or `fastboot boot` testing. |
| `wild-report.txt` | Which feature groups and patches applied. |
| `final-config.fragment` | The exact Kconfig fragment used. |
| `SHA256SUMS.txt` | Checksums for the files above. |

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
2. **Test boot without flashing.** A reboot returns you to your stock kernel:
   ```sh
   python tools/repack_boot.py stock_boot.img Image test_boot.img
   fastboot boot test_boot.img
   ```
3. **Flash** the AnyKernel3 zip from your recovery.
4. **Root.** SukiSU Ultra is built in, so restore a clean `init_boot` (remove any LKM-patched one) and install the SukiSU Ultra manager app.

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
  SukiSU-Ultra/patches/             SUSFS, enhanced SUSFS, ZeroMount, KSU safety patches
  build-helpers/                    config assembly, ABI-check bypass, build-flag and BBG helpers
  defconfig.fragment                base / susfs / overlayfs / wild Kconfig sections
  sukisu-pin.txt                    pinned SukiSU Ultra commit
scripts/wild-extras.sh              atomic WildKernels patch groups with rollback and report
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
| [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) | Root solution |
| [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) (simonpunk) | SUSFS |
| [Enginex0/Super-Builders](https://github.com/Enginex0/Super-Builders) and [ZeroMount](https://github.com/enginex0/zeromount) | Enhanced SUSFS, ZeroMount, build pipeline |
| [WildKernels](https://github.com/WildKernels) | Feature patches, AnyKernel3 |
| [Baseband-guard](https://github.com/vc-teahouse/Baseband-guard) | Baseband Guard module |

## License

Kernel patches are derived from the Linux kernel and carry **GPL-2.0**. Build scripts and workflows derived from Super-Builders
are **GPL-3.0**. See [LICENSE](LICENSE).
