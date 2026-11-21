/*---------------------------------------------------------------------------*\
  FoamWin: opt OpenFOAM processes out of Windows power throttling.

  Windows 11 may run a process it considers to be in the background (no
  window of its own, as for every rank that mpiexec starts) at "EcoQoS":
  lower clock speeds and a preference for the efficiency cores of a hybrid
  CPU.  A solver is never background work, so every process that loads
  libOpenFOAM asks for full execution speed and normal timer resolution as
  soon as the library is loaded.  On an i9-13900 this made an 8-rank run
  ~25% faster.  Nothing happens on Windows versions without the API.
\*---------------------------------------------------------------------------*/

#include <windows.h>

namespace
{

struct PowerThrottlingState { ULONG Version; ULONG ControlMask; ULONG StateMask; };

typedef BOOL (WINAPI *SetProcessInformationFn)(HANDLE, int, LPVOID, DWORD);

struct DisablePowerThrottling
{
    DisablePowerThrottling()
    {
        const HMODULE kernel = GetModuleHandleW(L"kernel32.dll");
        if (!kernel) return;

        const SetProcessInformationFn set = reinterpret_cast<SetProcessInformationFn>
        (
            reinterpret_cast<void*>(GetProcAddress(kernel, "SetProcessInformation"))
        );
        if (!set) return;

        // ProcessPowerThrottling = 4; EXECUTION_SPEED = 0x1, IGNORE_TIMER_RESOLUTION = 0x4.
        // A bit set in ControlMask and clear in StateMask turns that throttling off.
        PowerThrottlingState state = {1, 0x1 | 0x4, 0};
        set(GetCurrentProcess(), 4, &state, sizeof(state));
    }
};

const DisablePowerThrottling disablePowerThrottling;

} // End anonymous namespace

// ************************************************************************* //
