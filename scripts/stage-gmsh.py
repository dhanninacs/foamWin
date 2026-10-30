#!/usr/bin/env python3
"""Stage the standalone Gmsh CLI and corresponding source for FoamWin packaging."""
import argparse
import hashlib
import json
import shutil
import urllib.request
import zipfile
from pathlib import Path

VERSION = "4.15.2"
ARCHIVES = {
    f"gmsh-{VERSION}-Windows64.zip": ("bin/Windows", "a8208b56aedee3434907a893e303422acacd9003140766e09f2abbc664ba7157"),
    f"gmsh-{VERSION}-source.tgz": ("src", "be3f66f225d27ba9fa014f07e83169285da8a051b0e8ab7103d88066b39bdd3e"),
}

def stage(destination: Path, cache: Path) -> None:
    cache.mkdir(parents=True, exist_ok=True)
    target = destination / "gmsh"
    target.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for filename, (directory, digest) in ARCHIVES.items():
        archive = cache / filename
        url = f"https://gmsh.info/{directory}/{filename}"
        if not archive.is_file():
            with urllib.request.urlopen(url, timeout=120) as response, archive.open("wb") as output:
                shutil.copyfileobj(response, output)
        actual = hashlib.file_digest(archive.open("rb"), "sha256").hexdigest()
        if actual != digest:
            raise SystemExit(f"Checksum mismatch for {filename}; remove the corrupt cache file and retry")
        manifest[filename] = {"url": url, "sha256": digest}
        if filename.endswith(".zip"):
            with zipfile.ZipFile(archive) as bundle:
                for name in ("gmsh.exe", "LICENSE.txt", "CREDITS.txt", "README.txt"):
                    with bundle.open(f"gmsh-{VERSION}-Windows64/{name}") as source, (target / name).open("wb") as output:
                        shutil.copyfileobj(source, output)
        else:
            sources = target / "source"
            sources.mkdir(exist_ok=True)
            shutil.copyfile(archive, sources / filename)
    (target / "provenance.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--cache", type=Path, required=True)
    args = parser.parse_args()
    stage(args.destination, args.cache)
