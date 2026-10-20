#----------------------------------*-sh-*--------------------------------------
# Pre-settings for cross-compiling OpenFOAM 14 for Windows (MinGW-w64).
# Source this INSTEAD of etc/bashrc when building on Linux:
#   source .../OpenFOAM-14-win/etc/pre-bashrc-mingw_w64.sh
#------------------------------------------------------------------------------
[ "$BASH" ] && bashrcFile=${BASH_SOURCE}
[ "$ZSH_NAME" ] && bashrcFile=$0
if [ -n "$bashrcFile" ]
then
    export REF_OF_ETC=$(cd $(dirname $bashrcFile) && pwd -P)
fi
unset bashrcFile

source $REF_OF_ETC/bashrc \
    WM_OSTYPE=MSwindows \
    WM_COMPILER_TYPE=system \
    WM_COMPILER=Gcc \
    WM_MPLIB=dummy \
    WM_TARGET_ARCH=mingw_w64 \
    WM_COMPILER_ARCH= \
    WM_COMPILER_LIB_ARCH= \
    WM_ARCH_OPTION=64 \
    $@

unset REF_OF_ETC
