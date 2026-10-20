"""Repair the original prebuilt distribution without rebuilding every consumer.

The legacy DLL must be rebuilt from src/lagrangian/basic as liblagrangOld.dll.
New source builds use the corrected Make files instead of this migration.
"""
import argparse, hashlib, pathlib, shutil, struct, subprocess, sys
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('platform', type=pathlib.Path)
p.add_argument('--legacy-dll', type=pathlib.Path, required=True)
p.add_argument('--runtime-dir', type=pathlib.Path, required=True)
p.add_argument('--stack-trace', type=pathlib.Path, required=True)
a = p.parse_args()
core = a.platform / 'lib/libOpenFOAM.dll'
old = '76ee913f645c985924bfcbf473d742b3740a7cfac2bbd3734d06c9fd4e75b6e9'
fixed = '11d85ba4cbf5febbc623bc471861f279b99a109885a4f9d348505507b9c7b060'
digest = hashlib.sha256(core.read_bytes()).hexdigest()
if digest not in (old, fixed):
    raise SystemExit('Unrecognized core binary: rebuild from corrected source instead.')
for name in ('libgcc_s_seh-1.dll', 'libstdc++-6.dll'):
    shutil.copy2(a.runtime_dir / name, a.platform / 'bin' / name)
shutil.copy2(a.stack_trace, a.platform / 'bin/libstack_trace.dll')
shutil.copy2(a.legacy_dll, a.platform / 'lib/liblagrangOld.dll')
for target in list(a.platform.rglob('*.dll')) + list(a.platform.rglob('*.exe')):
    b = target.read_bytes()
    # Equal-length import-name migration; existing PE section sizes stay valid.
    updated = b.replace(b'liblagrangian.dll\0', b'liblagrangOld.dll\0')
    if updated != b: target.write_bytes(updated)
if digest == old:
    # This exact release's __CTOR_LIST__: 295 pointers after the -1 sentinel.
    # MinGW visits the list backwards. Reversing it restores Make/files order.
    b = bytearray(core.read_bytes())
    pe = struct.unpack_from('<I', b, 60)[0]
    count = struct.unpack_from('<H', b, pe + 6)[0]
    sections = pe + 24 + struct.unpack_from('<H', b, pe + 20)[0]
    rva = 0x569158
    for i in range(count):
        vs,va,rs,rp = struct.unpack_from('<IIII', b, sections + i*40 + 8)
        if va <= rva < va + max(vs,rs):
            start = rp + rva - va
            break
    else: raise SystemExit('Constructor section not found')
    assert struct.unpack_from('<Q', b, start)[0] == 0xffffffffffffffff
    values = list(struct.unpack_from('<295Q', b, start + 8))
    assert struct.unpack_from('<Q', b, start + 8*296)[0] == 0
    struct.pack_into('<295Q', b, start + 8, *reversed(values))
    assert hashlib.sha256(b).hexdigest() == fixed
    core.write_bytes(b)
subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name('verify-windows-imports.py')), str(a.platform)], check=True)
print('Prebuilt migration complete; run of14-smoke-test.ps1 on Windows.')
