/* Freeaddons ddthru trampoline — behavior-compatible replacement for
 * the donor vmaddons ddraw.dll/dsound.dll stubs.
 *
 * The installer backs up the real system DLL to ddrawwq.dll/dsoundwq.dll
 * and puts this DLL in its place. Every export resolves the same-named
 * function from the backup at first call and jumps to it, so callers
 * observe the original system implementation with zero behavioral delta.
 *
 * No CRT, kernel32 + msvcrt imports only, NO_SEH (set post-link).
 * Build twice: -DDDTHRU_DSOUND=0 (ddraw) and =1 (dsound). */

#include <windows.h>

#if DDTHRU_DSOUND
#define WQ_NAME "dsoundwq.dll"
#define XLIST \
    X(DirectSoundCaptureCreate) \
    X(DirectSoundCaptureCreate8) \
    X(DirectSoundCaptureEnumerateA) \
    X(DirectSoundCaptureEnumerateW) \
    X(DirectSoundCreate) \
    X(DirectSoundCreate8) \
    X(DirectSoundEnumerateA) \
    X(DirectSoundEnumerateW) \
    X(DirectSoundFullDuplexCreate) \
    X(DllCanUnloadNow) \
    X(DllGetClassObject) \
    X(GetDeviceID)
#else
#define WQ_NAME "ddrawwq.dll"
#define XLIST \
    X(AcquireDDThreadLock) \
    X(CompleteCreateSysmemSurface) \
    X(D3DParseUnknownCommand) \
    X(DDInternalLock) \
    X(DDInternalUnlock) \
    X(DirectDrawCreate) \
    X(DirectDrawCreateClipper) \
    X(DirectDrawCreateEx) \
    X(DirectDrawEnumerateA) \
    X(DirectDrawEnumerateExA) \
    X(DirectDrawEnumerateExW) \
    X(DirectDrawEnumerateW) \
    X(DllCanUnloadNow) \
    X(DllGetClassObject) \
    X(GetSurfaceFromDC) \
    X(ReleaseDDThreadLock)
#endif

static HMODULE wq_mod;
static CRITICAL_SECTION wq_cs;
static int wq_cs_ready;

#define X(n) static void *p_##n __attribute__((used));
XLIST
#undef X

/* Resolved on first use (not at attach: the backup may be installed
 * after us in edge cases, and lazy binding avoids loader-lock work). */
void ensure_wq(void)
{
    HMODULE m;

    if (wq_mod)
        return;
    if (!wq_cs_ready)
        return;
    EnterCriticalSection(&wq_cs);
    if (!wq_mod)
    {
        m = LoadLibraryA(WQ_NAME);
        if (m)
        {
#define X(n) p_##n = (void *)GetProcAddress(m, #n);
            XLIST
#undef X
            wq_mod = m;
        }
    }
    LeaveCriticalSection(&wq_cs);
}

/* Naked forwarders: stack is untouched (call+jmp only), so the stdcall
 * callee cleans up exactly as if called directly. Exported undecorated
 * via the .def file, matching the donor export tables. */
#define X(n) \
    __asm__(".text\n\t.globl _" #n "\n_" #n ":\n\tcall _ensure_wq\n\tjmp *_p_" #n);
XLIST
#undef X

BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID unused)
{
    (void)h;
    (void)unused;

    if (reason == DLL_PROCESS_ATTACH)
    {
        InitializeCriticalSection(&wq_cs);
        wq_cs_ready = 1;
        DisableThreadLibraryCalls(h);
    }
    else if (reason == DLL_PROCESS_DETACH)
    {
        if (wq_mod)
            FreeLibrary(wq_mod);
        wq_mod = NULL;
        if (wq_cs_ready)
        {
            wq_cs_ready = 0;
            DeleteCriticalSection(&wq_cs);
        }
    }
    return TRUE;
}
