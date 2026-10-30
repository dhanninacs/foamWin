# Optional Windows partitioners

FoamWin can use real Scotch and METIS decomposition libraries when they are
cross-built for Windows. The same-named libraries under `lib/dummy` are stubs;
they report that the corresponding partitioner is unavailable.

`scripts/build-thirdparty-partitioners.sh` can cross-build separately supplied
Scotch, METIS, and GKlib source trees without modifying them or installing to the
system. It needs CMake, make, flex, MinGW-w64, and a Linux host able to execute
generated Windows programs (for example, WSL executable interop). Point
`SCOTCH_SOURCE`, `METIS_SOURCE`, and `GKLIB_SOURCE` to the source trees and
`PARTITIONER_BUILD_ROOT` to a new directory. The script prints the paths needed
for the adapter build. It uses 32-bit METIS indices to match `WM_LABEL_SIZE=32`.

The cross-build was exercised with Scotch 7.0.12 from OpenFOAM ThirdParty-14
revision `6f75cb6aa1a3d8f1ba768840f9ee535244b4c70a`, METIS revision
`272d4a91c5f66c92327493339a476c553ebf1f5d`, and GKlib revision
`3b7d61b9f885063c89901f3901fb4426f9cfb58f`. Use and distribute the sources
under their respective licenses; these revision identifiers are not a license
grant. Other versions need separate validation.

`scripts/build-partitioners.sh` then builds the OpenFOAM adapters against the
prepared MinGW libraries. It requires a populated case-sensitive Linux build
tree and these environment variables:

```bash
export OF14_SOURCE=/path/to/case-sensitive/OpenFOAM-14
export SCOTCH_ARCH_PATH=/path/to/windows-scotch-prefix
export METIS_INCLUDE_DIR=/path/to/windows-metis/include
export METIS_LIB_DIR=/path/to/windows-metis/lib
export GKLIB_LIB_DIR=/path/to/windows-gklib/lib
bash scripts/build-partitioners.sh
```

The script does not download third-party sources or decide their license terms.
The build used for the native tests linked Scotch 7.0.12, METIS and GKlib
statically. Verify the licenses, source availability, and redistribution terms
of the exact third-party revisions before distributing binaries. In particular,
the tested GKlib contains additional LGPL and BSD components.

When a completed build contains real `libmetisDecomp.dll` or
`libscotchDecomp.dll` in its main library directory, `make-installer.sh`
excludes the corresponding staged dummy to avoid a Windows filename collision.
It also requires the license material: set `SCOTCH_LICENSE_FILE`,
`METIS_LICENSE_FILE`, and `GKLIB_NOTICES_DIR` as applicable. The GKlib notice
directory must contain `LICENSE.txt`, `LICENSES.md`, and `LICENSES/`. Providing
notices does not by itself establish that all source and relinking obligations
for the selected dependencies have been met.

After assembling a portable runtime, test fresh meshes with both algorithms:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-windows-partitioners.ps1 `
    -RuntimeRoot C:\path\to\FoamWin -OutputDirectory C:\path\to\new-test-folder
```

The test keeps its case directories and logs. `-Processes` selects the number
of partitions. It checks decomposition, not a parallel solver run; test MPI
execution and reconstruction separately before release.
