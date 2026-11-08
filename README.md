<div align="center">

# OnePlus 15R · GKI 6.12.69 Kernel

**SukiSU Ultra · Enhanced SUSFS · ZeroMount VFS · the full WildKernels feature set**
rebuilt from the exact kernel your phone ships, in CI, from source.

![Device](https://img.shields.io/badge/device-OnePlus%2015R%20(CPH2767)-eb0028?style=flat-square)
![Firmware](https://img.shields.io/badge/firmware-CPH2767__17.0.0.106(EX01)-555?style=flat-square)
![Kernel](https://img.shields.io/badge/linux-6.12.69-2b6cb0?style=flat-square)
![ABI](https://img.shields.io/badge/GKI-android16--6.12-3ddc84?style=flat-square)
![Root](https://img.shields.io/badge/root-SukiSU%20Ultra%20(built--in)-8250df?style=flat-square)
![License](https://img.shields.io/badge/license-GPL--3.0-lightgrey?style=flat-square)

[**Features**](#features) · [**How it works**](#how-it-works) · [**Build**](#building) · [**Install**](#installing) · [**Rollback**](#rollback) · [**Credits**](#credits)

</div>

---

## Why this exists

OnePlus publishes kernel source per release, but for the 15R it stops at **6.12.38** (March 2026).
The CPH2767_17.0.0.106 update ships **6.12.69**, so every prebuilt custom kernel built from OnePlus'
tree is a version behind and can't be used on it.

The 15R's shipped kernel is not a OnePlus fork, though. It is Google's unmodified GKI build
(`6.12.69-android16-6-g242e1a07f878-ab15865446-4k`, built by `kleaf@build-host`). Google publishes that
exact commit, so the same kernel can be rebuilt from source and extended with patches while staying ABI-compatible with the stock vendor modules.

| | |
|---|---|
| **Upstream source** | [`kernel/common`](https://android.googlesource.com/kernel/common/+/refs/tags/android16-6.12-2026-03_r54) tag `android16-6.12-2026-03_r54` |
| **Commit** | `242e1a07f8782987c579929a20a74c0b26e88608` (Wed Jul 15 2026, Linux 6.12.69) |
| **Pinned in CI** | The workflow aborts if it does not get sublevel 69 and that commit. |

## Features

### Root and hiding
| Feature | Details |
|---|---|
| **SukiSU Ultra** (built-in) | Compiled into the kernel, pinned to a known-good commit. No LKM or `init_boot` patch needed. |
| **Enhanced SUSFS** | Mount hiding, kstat spoofing and redirect, map hiding, uname and cmdline/bootconfig spoofing, open redirect, symbol hiding, Unicode filter, auto-hide of KSU default and bind mounts. |
| **ZeroMount VFS** | Systemless path redirection at the VFS layer: `getname()` redirection, directory-entry injection, `d_path`/xattr/`statfs` spoofing, bloom-filter lookup, ioctl control interface. |
| **Baseband Guard** | Security module that blocks writes to critical baseband/modem block devices. |

### Networking
| Feature | Details |
|---|---|
| **BBR** | Selectable TCP congestion control, alongside CUBIC. |
| **Queue disciplines** | `fq`, `fq_codel`, **CAKE**, **PIE**, `fq_pie`. |
| **ip_set** | Bitmap, hash and list set types, up to 65534 sets. `xt_set` and `addrtype` matches. |
| **IPv6 NAT** | `ip6table_nat` and IPv6 masquerade. |
| **TTL / HL** | `TTL` target and `HL` match/target, commonly used for tethering TTL adjustment. |

### Containers and compatibility
| Feature | Details |
|---|---|
| **Droidspaces** | `SYSVIPC`, `PID_NS`, `USER_NS`, `POSIX_MQUEUE`, `DEVTMPFS`, `MACVLAN`, netfilter `REJECT`/`LOG`/`recent`. Shipped with the **kABI padding patches** so struct layouts stay compatible with the stock vendor modules. |
| **NTSync** | Windows NT synchronization primitives for Wine/Proton. |
| **Overlay support** | `TMPFS_XATTR` and `TMPFS_POSIX_ACL`. |
| **Unicode bypass fix** | WildKernels' Unicode bypass fix (marked experimental upstream). |

### Performance and tuning (WildKernels set, 24 patches)
<details>
<summary>Show patch list</summary>

| Area | Patches |
|---|---|
| **Memory** | `optimized_mem_operations`, `optimise_memcmp`, `clear_page_16bytes_align`, `mem_opt_prefetch`, `file_struct_8bytes_align`, `reduce_cache_pressure`, `int_sqrt` |
| **Scheduler / power** | `minimise_wakeup_time`, `adjust_cpu_scan_order`, `disable_cache_hot_buddy`, `avoid_extra_s2idle_wake_attempts`, `reduce_pci_pme_wakeups`, `reduce_freeze_timeout`, `add_timeout_wakelocks_globally` |
| **CPU frequency** | `add_limitation_scaling_min_freq`, `re_write_limitation_scaling_min_freq`, `use_unlikely_wrap_cpufreq` |
| **Storage** | `f2fs_reduce_congestion`, `f2fs_enlarge_min_fsync_blocks`, `reduce_gc_thread_sleep_time`, `increase_ext4_default_commit_age` |
| **Network** | `increase_sk_mem_packets` |
| **Logging** | `silence_irq_cpu_logspam`, `silence_system_logspam` |

</details>

### Deliberately not included
- **HMBird/SCX scheduler**: the WildKernels 15R config also leaves it off.
- **BBRv3**: BBR (v1) is used instead, matching the WildKernels 15R config.
- **OnePlus vendor-module blacklisting and `fake_config`**: those belong to OnePlus' own kernel tree, not GKI.
- **ZRAM LZ4K/LZ4KD**: ZRAM is a module on your stock kernel and stays that way.

## How it works

```mermaid
flowchart LR
    A[Google kernel/common<br/>tag r54 · 6.12.69] --> B[SukiSU Ultra<br/>built-in]
    B --> C[Enhanced SUSFS<br/>50 + 51 + 70]
    C --> D[ZeroMount VFS<br/>60]
    D --> E[WildKernels patches<br/>atomic groups]
    E --> F[Config fragment<br/>+ BBG]
    F --> G[Kleaf / Bazel build]
    G --> H[AnyKernel3 zip<br/>+ raw Image]
```

**Atomic feature groups.** Every WildKernels feature group (NTSync, Droidspaces, Unicode fix) is applied
transactionally. If any patch in a group fails to apply, the tree is rolled back to a snapshot and that
group's kernel configs are **not** enabled. A partially applied Droidspaces patch set, for example, would
change `task_struct` layout and break the vendor modules, so it either goes in complete or not at all.
The result of every group is recorded in `wild-report.txt` in the build artifacts.

### Stock-compatibility guard rails
The phone loads hundreds of vendor modules built against Google's GKI ABI, so the build mirrors the stock kernel:

| Stock property (read from the device) | Handling in this build |
|---|---|
| `CONFIG_MODVERSIONS=y`, `PREEMPT=y`, `MODULE_UNLOAD` → vermagic flags `SMP preempt mod_unload modversions` | Those options are stripped from the fragment so they can never be changed. |
| `LTO_NONE` + `CFI_CLANG` | Built with `--lto=none`, CFI left as stock. |
| Module version CRC checks | CRC mismatch bypass applied (kernel-side struct changes from SUSFS/ZeroMount can shift CRCs). |
| GKI protected-export enforcement | Protected export lists removed so the rebuilt kernel does not refuse vendor modules. |
| `CONFIG_ZRAM=m`, `ANDROID_BINDER_IPC_RUST=m` | Left as modules. The IPC namespace symbols Rust binder needs are exported. |

## Building

1. **Actions → OnePlus 15R kernel → Run workflow.**
2. Leave the defaults, or toggle individual features (ZeroMount, Baseband Guard, tuning, NTSync, Droidspaces, Unicode fix).
3. Download the artifact when it finishes:

| File | What it is |
|---|---|
| `*-AnyKernel3.zip` | Flashable from a custom recovery. Replaces only the kernel in the active slot's `boot` partition. |
| `Image` | Raw arm64 kernel, for repacking or `fastboot boot` testing. |
| `wild-report.txt` | Which feature groups and patches applied. |
| `final-config.fragment` | Exact Kconfig fragment used. |
| `SHA256SUMS.txt` | Checksums for everything above. |

Pipeline and ZeroMount/SUSFS patch sets are adapted from [Enginex0/Super-Builders](https://github.com/Enginex0/Super-Builders);
WildKernels patches come from [WildKernels/kernel_patches](https://github.com/WildKernels/kernel_patches).

## Installing

> **Status: unreleased.** The pipeline applies every patch cleanly to the 6.12.69 source. The kernel has
> **not** been boot-tested yet. Do not flash a build that has not passed a test boot on your device.

Requirements: an **unlocked bootloader**, `adb`/`fastboot`, and **backups of your own partitions** (below).

1. **Back up** before anything else (from a root shell, per slot you use):
   ```sh
   for p in boot init_boot vendor_boot vbmeta dtbo recovery; do
     dd if=/dev/block/by-name/${p}_$(getprop ro.boot.slot_suffix | tr -d _) of=/sdcard/bk_$p.img
   done
   ```
2. **Test boot without flashing** (a reboot returns to your stock kernel):
   ```sh
   python repack_boot.py stock_boot.img Image test_boot.img
   fastboot boot test_boot.img
   ```
3. **Flash** the AnyKernel3 zip from your recovery.
4. **Root manager.** SukiSU Ultra is built into the kernel, so restore a *clean* `init_boot` (remove any LKM-patched
   one) and install the SukiSU Ultra manager app.

## Rollback

Restore the stock kernel by flashing your saved `boot` image back to the active slot:

```sh
fastboot flash boot_b boot_b.img      # use your active slot letter
```

or flash the stock `boot` image from recovery. The AnyKernel3 zip only rewrites the kernel inside `boot`; it does not modify `recovery`, `vendor_boot`, `vbmeta` or `init_boot`.

## Repository layout

```
.github/workflows/build-op15r.yml   single-job pipeline: sync, patch, configure, build, package
android16-6.12/
  SukiSU-Ultra/patches/             50 upstream SUSFS · 51 enhanced SUSFS · 60 ZeroMount · 70 KSU safety
  build-helpers/                    config assembly, ABI-check bypass, build-flag and BBG helpers
  defconfig.fragment                base / susfs / overlayfs / wild Kconfig sections
  sukisu-pin.txt                    pinned SukiSU Ultra commit
scripts/wild-extras.sh              atomic WildKernels patch groups with rollback and report
```

## Disclaimer

Custom kernels can prevent a device from booting and may void warranty or break apps that check device integrity.
You are responsible for your device. Everything here is provided as is, without warranty. Not affiliated with OnePlus,
Google, or any of the projects credited below.

## Credits

| Project | Used for |
|---|---|
| [Android Common Kernel](https://android.googlesource.com/kernel/common) (Google) | Base source |
| [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) | Root solution |
| [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) (simonpunk) | SUSFS |
| [Enginex0/Super-Builders](https://github.com/Enginex0/Super-Builders) and [ZeroMount](https://github.com/enginex0/zeromount) | Enhanced SUSFS, ZeroMount, build pipeline |
| [WildKernels](https://github.com/WildKernels) | Feature patches, AnyKernel3 |
| [Baseband-guard](https://github.com/vc-teahouse/Baseband-guard) | Baseband Guard LSM |

## License

Kernel patches are derived from the Linux kernel and carry **GPL-2.0**. Build scripts and workflows derived from Super-Builders are
**GPL-3.0**. See [LICENSE](LICENSE).
