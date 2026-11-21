/*---------------------------------------------------------------------------*\
  FoamWin: reuse of large heap blocks (Windows only).

  OpenFOAM allocates and frees many large temporary fields every iteration.
  The Windows C runtime (msvcrt) hands blocks above its heap's virtual-memory
  threshold straight back to the system, so each new temporary is faulted in
  and zeroed page by page again; glibc keeps such memory for reuse.  On a
  343k-cell case that cost 13x the page faults and ~6x the kernel time of the
  same run on Linux.

  This file replaces the global operator new/delete for the modules that link
  libOpenFOAM.  Blocks of at least largeBlockMin bytes that are freed are
  kept in a small cache and handed out again for a request of a similar
  size.  Every block is a plain msvcrt malloc() block, so memory may still be
  freed by code that does not use these operators (libstdc++ internals,
  free()) and memory from those may be freed here.
\*---------------------------------------------------------------------------*/

#include <cstdlib>
#include <cstddef>
#include <new>
#include <malloc.h>
#include <windows.h>

namespace
{

const size_t largeBlockMin   = size_t(64) << 10;   // 64 KiB
const size_t cacheBytesMax   = size_t(1) << 30;    // 1 GiB kept at most
const int    cacheSlots      = 256;

struct Slot { void* ptr; size_t size; };

Slot slots[cacheSlots];          // zero-initialised: usable before static init
int nSlots = 0;
size_t cachedBytes = 0;
SRWLOCK lock = SRWLOCK_INIT;


void* allocate(size_t n)
{
    if (n == 0) n = 1;

    if (n >= largeBlockMin && nSlots)
    {
        // Smallest cached block that fits without wasting more than 1/4
        const size_t maxSize = n + (n >> 2);
        void* found = nullptr;

        AcquireSRWLockExclusive(&lock);
        int best = -1;
        for (int i = 0; i < nSlots; ++i)
        {
            const size_t s = slots[i].size;
            if (s >= n && s <= maxSize && (best < 0 || s < slots[best].size))
            {
                best = i;
                if (s == n) break;
            }
        }
        if (best >= 0)
        {
            found = slots[best].ptr;
            cachedBytes -= slots[best].size;
            slots[best] = slots[--nSlots];
        }
        ReleaseSRWLockExclusive(&lock);

        if (found) return found;
    }

    void* p = std::malloc(n);
    if (!p) throw std::bad_alloc();
    return p;
}


void deallocate(void* p) noexcept
{
    if (!p) return;

    const size_t s = _msize(p);
    if (s >= largeBlockMin)
    {
        void* evict = nullptr;

        AcquireSRWLockExclusive(&lock);
        if (s <= cacheBytesMax)
        {
            // Make room: drop the oldest entries first
            while (nSlots && (nSlots == cacheSlots || cachedBytes + s > cacheBytesMax))
            {
                std::free(slots[0].ptr);
                cachedBytes -= slots[0].size;
                slots[0] = slots[--nSlots];
            }
            slots[nSlots].ptr = p;
            slots[nSlots].size = s;
            ++nSlots;
            cachedBytes += s;
        }
        else
        {
            evict = p;
        }
        ReleaseSRWLockExclusive(&lock);

        if (evict) std::free(evict);
        return;
    }

    std::free(p);
}

} // End anonymous namespace


void* operator new(size_t n) { return allocate(n); }
void* operator new[](size_t n) { return allocate(n); }

void* operator new(size_t n, const std::nothrow_t&) noexcept
{
    try { return allocate(n); } catch (...) { return nullptr; }
}

void* operator new[](size_t n, const std::nothrow_t&) noexcept
{
    try { return allocate(n); } catch (...) { return nullptr; }
}

void operator delete(void* p) noexcept { deallocate(p); }
void operator delete[](void* p) noexcept { deallocate(p); }
void operator delete(void* p, size_t) noexcept { deallocate(p); }
void operator delete[](void* p, size_t) noexcept { deallocate(p); }
void operator delete(void* p, const std::nothrow_t&) noexcept { deallocate(p); }
void operator delete[](void* p, const std::nothrow_t&) noexcept { deallocate(p); }

// ************************************************************************* //
