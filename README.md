# OnePlus 15R (CPH2767) GKI kernel build

Rebuilds the exact GKI kernel shipped in CPH2767_17.0.0.106 (Google `kernel/common` tag
`android16-6.12-2026-03_r54`, commit `242e1a07f878`, Linux 6.12.69) and adds SukiSU Ultra
(built-in), enhanced SUSFS, ZeroMount VFS and the WildKernels feature set.

Run the **OnePlus 15R kernel** workflow; the flashable AnyKernel3 zip is in the run's artifacts.

Pipeline adapted from Enginex0/Super-Builders (GPL-3.0); feature patches from
WildKernels/kernel_patches. All patches keep their upstream licenses.
