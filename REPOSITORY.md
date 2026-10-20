# GitHub repository settings

Use these values when creating or configuring the GitHub repository. They describe
the intended public repository; this file does not change GitHub settings itself.

| Setting | Value |
|---|---|
| Name | `openfoam14-windows` |
| Description | Native Windows port of OpenFOAM 14 using MinGW-w64, with a PowerShell launcher, installer, and validated cavity examples. |
| Visibility | Public |
| Default branch | `main` |
| License | GPLv3; retain existing upstream attribution |
| Topics | `openfoam`, `cfd`, `windows`, `mingw-w64`, `fluid-dynamics`, `scientific-computing` |

## Initial release

- Tag: `v14.0.0-win.1`
- Title: **OpenFOAM 14 for Windows — Initial Release**
- Attachments: `OF14-win-setup.exe` and `OF14-win.zip`
- Release notes: use the corresponding entry in [CHANGELOG.md](CHANGELOG.md).

Publish the contents of this source repository, not its parent workspace. Exclude
build directories, validation results, private backups, and credentials. Do not
represent this community port as an official OpenFOAM distribution.
