#!/usr/bin/env python3
"""Bump LC_ID_DYLIB current/compatibility version in a (fat) Mach-O dylib.

FUSE-T's libfuse-t reports version 0.0.0; ntfs-3g requires libfuse.2 >= 12.0.0.
We set both current and compatibility version to 12.9.0 (0x000C0900) so dyld
accepts the FUSE-T library when it is installed in place of macFUSE's
/usr/local/lib/libfuse.2.dylib. Used by install.sh to build the shim.

Usage: patch_version.py <path-to-dylib>
"""
import struct
import sys

FAT_MAGIC = 0xCAFEBABE          # big-endian on disk
MH_MAGIC_64 = 0xFEEDFACF
LC_ID_DYLIB = 0xD
NEW_VERSION = (12 << 16) | (9 << 8) | 0   # 12.9.0

path = sys.argv[1]
with open(path, "rb") as f:
    data = bytearray(f.read())


def patch_thin(base):
    """Patch the Mach-O 64 slice starting at `base`. Little-endian assumed."""
    magic = struct.unpack_from("<I", data, base)[0]
    assert magic == MH_MAGIC_64, f"unexpected magic {magic:#x} at {base}"
    ncmds = struct.unpack_from("<I", data, base + 16)[0]
    off = base + 32  # sizeof(mach_header_64)
    patched = 0
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == LC_ID_DYLIB:
            # dylib_command: cmd, cmdsize, name_off, timestamp, current, compat
            struct.pack_into("<I", data, off + 16, NEW_VERSION)  # current_version
            struct.pack_into("<I", data, off + 20, NEW_VERSION)  # compatibility_version
            patched += 1
        off += cmdsize
    return patched


magic_be = struct.unpack_from(">I", data, 0)[0]
total = 0
if magic_be == FAT_MAGIC:
    nfat = struct.unpack_from(">I", data, 4)[0]
    for i in range(nfat):
        # fat_arch: cputype, cpusubtype, offset, size, align (all >I)
        _, _, offset, _, _ = struct.unpack_from(">IIIII", data, 8 + i * 20)
        total += patch_thin(offset)
else:
    total += patch_thin(0)

with open(path, "wb") as f:
    f.write(data)
print(f"Patched {total} LC_ID_DYLIB command(s) to version 12.9.0")
