#!/usr/bin/env python3
"""Replace the kernel inside a boot image (header v4, no ramdisk) with a new raw Image.

usage: python -I repack_boot.py <stock_boot.img> <new_Image> <out_boot.img>

The stock image is only used as a template for the header. The AVB footer is NOT
carried over (the bootloader is unlocked / orange, so verification failure is tolerated,
the same as with a Magisk/KernelSU-patched image).
"""
import struct
import sys

PAGE = 4096

def main(stock, image, out):
    d = open(stock, 'rb').read()
    kernel = open(image, 'rb').read()
    if d[:8] != b'ANDROID!':
        sys.exit('not an Android boot image')
    hdr_ver = struct.unpack('<I', d[40:44])[0]
    ramdisk_size = struct.unpack('<I', d[12:16])[0]
    if hdr_ver != 4 or ramdisk_size != 0:
        sys.exit(f'unsupported template (header v{hdr_ver}, ramdisk {ramdisk_size}); expected v4 with no ramdisk')
    if kernel[:2] != b'MZ':
        sys.exit('new kernel does not look like an arm64 Image (no MZ header)')
    hdr = bytearray(d[:PAGE])
    struct.pack_into('<I', hdr, 8, len(kernel))   # kernel_size
    pad = (-len(kernel)) % PAGE
    open(out, 'wb').write(bytes(hdr) + kernel + b'\0' * pad)
    print(f'wrote {out}: kernel {len(kernel)} bytes, total {PAGE + len(kernel) + pad} bytes')

if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
