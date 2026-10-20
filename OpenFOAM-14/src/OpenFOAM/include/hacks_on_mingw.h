// MinGW-w64 adaptation for OpenFOAM (blueCFD-style)
// This header is included at the top of OSspecific.H (and headers that
// come before it). If a mingw header already defined mode_t (unsigned
// short) before us, we keep it — OpenFOAM's mode_t streaming sites are
// patched to handle it. Otherwise define it as unsigned int (Linux-like).

#include <sys/types.h>

#ifndef _HACK4_MODE_T_
#define _HACK4_MODE_T_
#if !defined(__MINGW32__) && !defined(__MINGW64__)
typedef unsigned int mode_t;
#endif
#endif
