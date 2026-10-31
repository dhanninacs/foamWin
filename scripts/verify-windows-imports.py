import struct,pathlib,os,sys
root=pathlib.Path(sys.argv[1]).resolve()
class PE:
 def __init__(self,p):
  self.b=b=p.read_bytes(); pe=struct.unpack_from('<I',b,60)[0]; n=struct.unpack_from('<H',b,pe+6)[0]; sz=struct.unpack_from('<H',b,pe+20)[0]; op=pe+24; self.x64=struct.unpack_from('<H',b,op)[0]==523; self.dd=op+(112 if self.x64 else 96); self.sections=[struct.unpack_from('<IIII',b,op+sz+i*40+8) for i in range(n)]
 def u(self,o):return struct.unpack_from('<I',self.b,o)[0]
 def off(self,r):
  for vs,va,rs,rp in self.sections:
   if va<=r<va+max(vs,rs):return rp+r-va
  return r
 def string(self,o):return self.b[o:self.b.index(0,o)].decode(errors='replace')
 def imports(self):
  r=self.u(self.dd+8)
  if not r:return []
  o=self.off(r); out=[]
  while any(self.b[o:o+20]):
   dll=self.string(self.off(self.u(o+12))); th=self.off(self.u(o) or self.u(o+16)); names=[]; size=8 if self.x64 else 4
   while True:
    v=int.from_bytes(self.b[th:th+size],'little'); th+=size
    if not v:break
    if not v>>(size*8-1):names.append(self.string(self.off(v)+2))
   out.append((dll,names)); o+=20
  return out
 def exports(self):
  r=self.u(self.dd)
  if not r:return set()
  o=self.off(r); count=self.u(o+24); arr=self.off(self.u(o+32)); return {self.string(self.off(self.u(arr+4*i))) for i in range(count)}

# Each backend directory (lib/dummy, lib/msmpi) supplies Pstream and may supply
# partitioners. Resolve DLLs in of14-shell.ps1's PATH order for that backend:
# bin, lib, lib/<backend>, then lib/dummy. A later same-named DLL is shadowed.
system_dlls = {'kernel32.dll','msvcrt.dll','advapi32.dll','user32.dll','imagehlp.dll','msmpi.dll'}
all_files = list(root.rglob('*.dll')) + list(root.rglob('*.exe'))
backend_dirs = {root/'lib'/name for name in ('dummy','msmpi')}
backends = [name for name in ('dummy','msmpi') if (root/'lib'/name/'libPstream.dll').is_file()]
errors = []
seen = {}
for p in all_files:
 key = (p.parent, p.name.lower())
 if key in seen: errors.append(f'Windows filename collision: {seen[key]} and {p}')
 seen[key] = p
for backend in backends:
 order = [root/'bin', root/'lib', root/'lib'/backend] + ([root/'lib'/'dummy'] if backend != 'dummy' else [])
 rank = lambda p: order.index(p.parent) if p.parent in order else len(order)
 index = {}
 for p in sorted((p for p in all_files if p.parent not in backend_dirs or p.parent in order), key=rank):
  index.setdefault(p.name.lower(), p)
 files = list(index.values())
 cache = {}
 for p in files:
  for dll,names in PE(p).imports():
   key = dll.lower()
   if key in system_dlls or key.startswith(('api-ms-', 'ext-ms-')): continue
   if key not in index:
    errors.append(f'{backend}: {p.name}: missing {dll}')
    continue
   if key not in cache: cache[key] = PE(index[key]).exports()
   missing = set(names) - cache[key]
   if missing: errors.append(f'{backend}: {p.name} -> {dll}: missing exports {sorted(missing)}')
 if not errors: print(f'Import validation passed ({backend} backend): {sum(p.suffix == ".exe" for p in files)} executables')
if not backends: errors.append('No Pstream backend is packaged')
if errors:
 print('\n'.join(errors),file=sys.stderr)
 sys.exit(1)
