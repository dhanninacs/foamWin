@echo off
title OpenFOAM 14 (MinGW-w64 native)
rem This launcher is location-independent: it uses %~dp0 (its own folder).
set OF=%~dp0platforms\linuxmingw-w64GccDPInt32Opt
set MSYS=
if exist "%~dp0msys2\usr\bin\bash.exe" set MSYS=%~dp0msys2
if "%MSYS%"=="" if exist "C:\msys64\usr\bin\bash.exe" set MSYS=C:\msys64
if "%MSYS%"=="" goto nomsys
set PATH=%OF%\bin;%OF%\lib;%OF%\lib\dummy;%PATH%
"%MSYS%\usr\bin\env.exe" MSYSTEM=MINGW64 "%MSYS%\usr\bin\bash.exe" --login -i -c "export OFDIR=$(cygpath -u '%OF%'); export PATH=$OFDIR/bin:$OFDIR/lib:$OFDIR/lib/dummy:$PATH; source $OFDIR/../../etc/bashrc; echo OpenFOAM-14 environment loaded; exec bash"
goto :eof
:nomsys
echo MSYS2 was not found and is required to run OpenFOAM.
echo Re-run the installer with "Install MSYS2 automatically" ticked,
echo or install MSYS2 from https://www.msys2.org into C:\msys64.
pause
