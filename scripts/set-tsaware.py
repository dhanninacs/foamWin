"""Mark Windows executables Terminal-Server aware (IMAGE_DLLCHARACTERISTICS_TERMINAL_SERVER_AWARE).

Without the flag, Windows Server runs a program in a Remote Desktop session in its compatibility
mode, and there NVIDIA's driver faulted in cuInit for every MinGW-built program (FoamWin #1);
the same programs with the flag ran normally. MSVC sets it by default for console programs, GNU ld
only with --tsaware, which the wmake rules now pass; this sets it on executables linked before that.

    python3 set-tsaware.py <folder>...     every *.exe below each folder (DLLs ignore the flag)

The PE checksum is recomputed when the file has one. Prints how many files changed.
"""

import struct
import sys
from pathlib import Path

TS_AWARE = 0x8000


def pe_checksum(data: bytearray, checksum_offset: int) -> int:
    """The Windows PE image checksum (as ImageHlp's CheckSumMappedFile)."""
    total = 0
    padded = data + b"\0" * (len(data) % 2)
    for i in range(0, len(padded), 2):
        if checksum_offset <= i < checksum_offset + 4:
            continue
        total += padded[i] | (padded[i + 1] << 8)
        total = (total & 0xFFFF) + (total >> 16)
    total = (total & 0xFFFF) + (total >> 16)
    return (total + len(data)) & 0xFFFFFFFF


def mark(path: Path) -> bool:
    data = bytearray(path.read_bytes())
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe : pe + 4] != b"PE\0\0":
        raise ValueError(f"{path}: not a PE image")
    optional = pe + 24
    # DllCharacteristics is at the same offset in PE32 and PE32+ optional headers.
    flags_at = optional + 70
    flags = struct.unpack_from("<H", data, flags_at)[0]
    if flags & TS_AWARE:
        return False
    struct.pack_into("<H", data, flags_at, flags | TS_AWARE)
    checksum_at = optional + 64
    if struct.unpack_from("<I", data, checksum_at)[0]:
        struct.pack_into("<I", data, checksum_at, pe_checksum(data, checksum_at))
    path.write_bytes(bytes(data))
    return True


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    changed = total = 0
    for folder in sys.argv[1:]:
        for exe in sorted(Path(folder).rglob("*.exe")):
            total += 1
            changed += mark(exe)
    print(f"Terminal-Server aware: {changed} of {total} executables changed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
