/*
 * Mock implementations of the Windows kernel32 API used by
 * qemu3dfx_hooks.c on Linux.
 *
 * The mock_* globals let individual test functions control the
 * behaviour of each mock without rebuilding.
 */
#include <string.h>
#include "include/windows.h"

/* ── Controllable mock state ─────────────────────────────────────── */

/* Set to 1 to make CreateFileA("\\.\QEMUchs",...) succeed. */
int mock_qemuchs_accessible = 0;

/* Set to a non-NULL value to make GetModuleHandleA("opengl32.dll") succeed. */
HANDLE mock_opengl32_handle = NULL;

/* ── CreateFileA ─────────────────────────────────────────────────── */
HANDLE CreateFileA(LPCSTR name, DWORD access, DWORD share,
                   SECURITY_ATTRIBUTES *sa, DWORD creation,
                   DWORD flags, HANDLE tmpl)
{
    (void)access; (void)share; (void)sa;
    (void)creation; (void)flags; (void)tmpl;

    if (name && strcmp(name, "\\\\.\\QEMUchs") == 0)
        return mock_qemuchs_accessible ? (HANDLE)1 : INVALID_HANDLE_VALUE;

    return INVALID_HANDLE_VALUE;
}

/* ── CloseHandle ─────────────────────────────────────────────────── */
BOOL CloseHandle(HANDLE h)
{
    (void)h;
    return TRUE;
}

/* ── GetModuleHandleA ────────────────────────────────────────────── */
HANDLE GetModuleHandleA(LPCSTR name)
{
    if (name && strcmp(name, "opengl32.dll") == 0)
        return mock_opengl32_handle;

    return NULL;
}

/* ── GetProcAddress ─────────────────────────────────────────────── */
/* Returns non-NULL only for the fake ddrawwq.dll handle so the
   passthrough bridge's load_ddrawwq() succeeds. Everything else
   (e.g. WGL extension queries on opengl32) finds nothing. */
void *GetProcAddress(HANDLE h, LPCSTR name)
{
    (void)name;
    if (h == (HANDLE)2)
        return (void *)1;
    return NULL;
}

/* ── LoadLibraryA / FreeLibrary ───────────────────────────────────── */
HANDLE LoadLibraryA(LPCSTR name)
{
    if (name && strcmp(name, "ddrawwq.dll") == 0)
        return (HANDLE)2;
    return NULL;
}

BOOL FreeLibrary(HANDLE h)
{
    (void)h;
    return TRUE;
}

/* ── GetTickCount / Sleep ─────────────────────────────────────────── */
static DWORD mock_tick = 0;
DWORD GetTickCount(void)
{
    mock_tick += 16;
    return mock_tick;
}

void Sleep(DWORD ms)
{
    (void)ms;
}

/* ── Display adapter enumeration ──────────────────────────────────── */
/* Reports no adapters so legacy Bochs-string detection stays FALSE. */
BOOL EnumDisplayDevicesA(LPCSTR dev, DWORD num, DISPLAY_DEVICEA *dd, DWORD flags)
{
    (void)dev; (void)num; (void)dd; (void)flags;
    return FALSE;
}

/* ── GetModuleFileNameA ───────────────────────────────────────────── */
/* Reports a neutral exe name that matches no qemu-3dfx application. */
DWORD GetModuleFileNameA(HANDLE h, LPSTR buf, DWORD size)
{
    static const char name[] = "test_runner.exe";
    unsigned i = 0;
    (void)h;
    if (!buf || size == 0)
        return 0;
    while (name[i] && i + 1 < size) { buf[i] = name[i]; i++; }
    buf[i] = 0;
    return i;
}

void OutputDebugStringA(LPCSTR s) { (void)s; }

BOOL WriteFile(HANDLE h, LPCVOID buf, DWORD len, LPDWORD written, void *ov)
{
    (void)h; (void)buf; (void)ov;
    if (written) *written = len;
    return TRUE;
}

int lstrlenA(LPCSTR s)
{
    return s ? (int)strlen(s) : 0;
}
