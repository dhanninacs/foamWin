; =============================================================================
; OpenFOAM 14 for Windows - interactive installer (NSIS)
; Pages: welcome -> license -> components -> install folder -> progress ->
;        finish (optional immediate shell launch).
; Shortcuts: Start Menu + Desktop (optional sections). Uninstaller included.
; MSYS2: optional automatic download + silent install if not present.
; Build:  makensis OF14-installer.nsi   (produces OF14-win-setup.exe)
; =============================================================================

!define PRODUCT      "OpenFOAM 14"
!define PUBLISHER    "OpenFOAM Foundation community port (blueCFD-style)"
!define EXE_DIRNAME  "linuxmingw-w64GccDPInt32Opt"
!define MSYS2_DEF    "C:\msys64"

;--------------------------------------------------------------------- general
Name "${PRODUCT} for Windows"
OutFile "OF14-win-setup.exe"
InstallDir "$PROGRAMFILES64\OpenFOAM-14"
InstallDirRegKey HKLM "Software\${PRODUCT}" "InstallDir"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
Unicode true

VIProductVersion "14.0.0.2"
VIAddVersionKey FileDescription " for Windows installer"
VIAddVersionKey ProductName "${PRODUCT} for Windows"
VIAddVersionKey CompanyName "${PUBLISHER}"
VIAddVersionKey FileVersion "14.0"
VIAddVersionKey LegalCopyright "GPLv3 - OpenFOAM Foundation codebase"
Caption "${PRODUCT} Setup"

;----------------------------------------------------------------------- pages
!include "MUI2.nsh"
!include "LogicLib.nsh"
!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "LICENSE.txt"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "Open an OpenFOAM 14 shell now"
!define MUI_FINISHPAGE_RUN_FUNCTION "LaunchShell"
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

;------------------------------------------------------------------- sections
Section "!OpenFOAM 14 core (required)" SEC_CORE
    SectionIn RO
    SetOutPath "$INSTDIR"
    File /r "OpenFOAM-14\etc"
    File "OpenFOAM-14\COPYING"
    File "of14-shell.bat"
    File "of14-shell.ps1"
    File "of14-smoke-test.ps1"
    File "of14-mesh-test.ps1"
    File /r "OpenFOAM-14\examples"
    File "README.md"
    File /r "OpenFOAM-14\runtime-licenses"
    File /r "OpenFOAM-14\tutorials"
    SetOutPath "$INSTDIR\platforms\${EXE_DIRNAME}\bin"
    File /r "OpenFOAM-14\platforms\${EXE_DIRNAME}\bin\*.exe"
    File /r "OpenFOAM-14\platforms\${EXE_DIRNAME}\bin\*.dll"
    SetOutPath "$INSTDIR\platforms\${EXE_DIRNAME}\lib"
    File /r "OpenFOAM-14\platforms\${EXE_DIRNAME}\lib\*.dll"
    SetOutPath "$INSTDIR\platforms\${EXE_DIRNAME}\lib\dummy"
    File /r "OpenFOAM-14\platforms\${EXE_DIRNAME}\lib\dummy\*"
    ; registry: install path + uninstaller
    WriteRegStr HKLM "Software\${PRODUCT}" "InstallDir" "$INSTDIR"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT}" \
        "DisplayName" "${PRODUCT} for Windows"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT}" \
        "UninstallString" '"$INSTDIR\Uninstall.exe"'
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT}" \
        "Publisher" "${PUBLISHER}"
    WriteUninstaller "$INSTDIR\Uninstall.exe"
SectionEnd

Section "Start Menu shortcuts" SEC_SMENU
    SetOutPath "$INSTDIR"
    CreateDirectory "$SMPROGRAMS\${PRODUCT}"
    CreateShortCut "$SMPROGRAMS\${PRODUCT}\OpenFOAM 14 shell.lnk" "$INSTDIR\of14-shell.bat"
    CreateShortCut "$SMPROGRAMS\${PRODUCT}\Uninstall ${PRODUCT}.lnk" "$INSTDIR\Uninstall.exe"
SectionEnd

Section "Desktop shortcut" SEC_DESKTOP
    SetOutPath "$INSTDIR"
    CreateShortCut "$DESKTOP\OpenFOAM 14.lnk" "$INSTDIR\of14-shell.bat"
SectionEnd

; MSYS2 helper: download+silent-install if not present
Section /o "Install MSYS2 automatically (tick if you don't have MSYS2)" SEC_MSYS2
    DetailPrint "Checking for MSYS2 at ${MSYS2_DEF} ..."
    ${If} ${FileExists} "${MSYS2_DEF}\usr\bin\bash.exe"
        DetailPrint "MSYS2 found: nothing to do."
    ${Else}
        DetailPrint "Downloading MSYS2 (~100 MB)..."
        NSISdl::Download \
            "https://github.com/msys2/msys2-installer/releases/download/nightly-x86_64/msys2-base-x86_64-20250113.sfx.exe" \
            "$TEMP\msys2-base.sfx.exe"
        Pop $R0
        ${If} $R0 != "success"
            DetailPrint "Primary URL failed ($R0); trying mirror..."
            NSISdl::Download \
                "https://repo.msys2.org/distrib/msys2-x86_64-latest.sfx.exe" \
                "$TEMP\msys2-base.sfx.exe"
            Pop $R0
        ${EndIf}
        ${If} $R0 == "success"
            DetailPrint "Extracting MSYS2 to ${MSYS2_DEF} ..."
            StrCpy $R1 "${MSYS2_DEF}" 2
            SetOutPath "$R1\"
            ExecWait "$TEMP\msys2-base.sfx.exe -y"
            Delete "$TEMP\msys2-base.sfx.exe"
            ${If} ${FileExists} "${MSYS2_DEF}\usr\bin\bash.exe"
                DetailPrint "MSYS2 installed at ${MSYS2_DEF}."
                DetailPrint "Initialising MSYS2 (keyring, package db)..."
                ExecWait '"${MSYS2_DEF}\usr\bin\bash.exe" -lc true'
                ExecWait '"${MSYS2_DEF}\usr\bin\pacman.exe" -Sy --noconfirm'
            ${Else}
                DetailPrint "MSYS2 extraction failed; install manually from msys2.org."
            ${EndIf}
        ${Else}
            DetailPrint "MSYS2 download failed ($R0). Install manually from msys2.org."
        ${EndIf}
    ${EndIf}
SectionEnd

Function LaunchShell
    ExecShell "open" "$INSTDIR\of14-shell.bat"
FunctionEnd

;-------------------------------------------------------------- uninstaller
Section "Uninstall"
    Delete "$INSTDIR\Uninstall.exe"
    Delete "$INSTDIR\of14-shell.bat"
    Delete "$INSTDIR\of14-shell.ps1"
    Delete "$INSTDIR\of14-smoke-test.ps1"
    Delete "$INSTDIR\of14-mesh-test.ps1"
    RMDir /r "$INSTDIR\examples"
    Delete "$INSTDIR\README.md"
    RMDir /r "$INSTDIR\runtime-licenses"
    RMDir /r "$INSTDIR\tutorials"
    RMDir /r "$INSTDIR\etc"
    RMDir /r "$INSTDIR\platforms"
    Delete "$SMPROGRAMS\${PRODUCT}\*.*"
    RMDir  "$SMPROGRAMS\${PRODUCT}"
    Delete "$DESKTOP\OpenFOAM 14.lnk"
    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT}"
    DeleteRegKey HKLM "Software\${PRODUCT}"
SectionEnd
