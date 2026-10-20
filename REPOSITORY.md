# FoamHarbor repository settings

Use these values when creating or configuring the GitHub repository. They describe
the intended public repository; this file does not change GitHub settings itself.

| Setting | Value |
|---|---|
| Name | `foamharbor` |
| Description | FoamHarbor brings OpenFOAM 14 to native Windows, with a PowerShell launcher, installer, and validated cavity examples. |
| Visibility | Public |
| Default branch | `main` |
| License | GPLv3; retain existing upstream attribution |
| Topics | `openfoam`, `cfd`, `windows`, `mingw-w64`, `fluid-dynamics`, `scientific-computing` |

## Project identity

- Display name: **FoamHarbor**
- Tagline: **OpenFOAM, at home on Windows.**
- Technical description: **A community native Windows port of OpenFOAM 14.**
- Existing executable names, package filenames, and OpenFOAM namespaces are retained.

## Initial release

- Tag: `v14.0.0-win.1`
- Title: **FoamHarbor 14 for Windows — Initial Release**
- Attachments: `OF14-win-setup.exe` and `OF14-win.zip`
- Release notes: use the corresponding entry in [CHANGELOG.md](CHANGELOG.md).

Publish the contents of this source repository, not its parent workspace. Exclude
build directories, validation results, private backups, and credentials. Do not
represent this community port as an official OpenFOAM distribution.
