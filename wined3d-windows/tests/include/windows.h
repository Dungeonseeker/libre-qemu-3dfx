/*
 * Mock Windows types and API declarations for Linux unit testing.
 *
 * Replaces the real <windows.h> when compiling the passthrough C sources
 * on a Linux host (via -Itests/include -D_WIN32).  Only the subset of
 * types and declarations actually used by the three source files is
 * provided here.
 */
#ifndef MOCK_WINDOWS_H
#define MOCK_WINDOWS_H

#ifdef __cplusplus
extern "C" {
#endif

/* ── Basic types ─────────────────────────────────────────────────── */
typedef int            BOOL;
typedef unsigned long  DWORD;
typedef void          *HANDLE;
typedef unsigned short WORD;
typedef unsigned char  BYTE;
typedef long           LONG;
typedef long           HRESULT;
typedef const char    *LPCSTR;
typedef char          *LPSTR;
typedef const void    *LPCVOID;
typedef DWORD         *LPDWORD;
typedef HANDLE         HMODULE;
typedef void          *HDC;
typedef struct _GUID {
    unsigned long  Data1;
    unsigned short Data2;
    unsigned short Data3;
    unsigned char  Data4[8];
} GUID;
typedef const GUID    *REFIID;

#ifndef TRUE
#  define TRUE  1
#endif
#ifndef FALSE
#  define FALSE 0
#endif
#ifndef NULL
#  define NULL ((void *)0)
#endif

/* ── Constants ────────────────────────────────────────────────────── */
#define INVALID_HANDLE_VALUE ((HANDLE)(long)-1)
#define GENERIC_READ         0x80000000UL
#define FILE_APPEND_DATA     0x0004
#define FILE_SHARE_READ      0x00000001
#define FILE_SHARE_WRITE     0x00000002
#define OPEN_ALWAYS          4
#define FILE_ATTRIBUTE_NORMAL 0x00000080
#define GENERIC_WRITE        0x40000000UL
#define OPEN_EXISTING        3
#define S_OK                 ((HRESULT)0L)
#define S_FALSE              ((HRESULT)1L)
#define E_FAIL               ((HRESULT)0x80004005L)

/* ── Calling convention ───────────────────────────────────────────── */
/* stdcall is not a real calling convention on Linux x86-64; treat
   both WINAPI and __stdcall as no-ops so the sources compile cleanly. */
#ifndef WINAPI
#  define WINAPI
#endif
#ifndef __stdcall
#  define __stdcall
#endif

/* ── SECURITY_ATTRIBUTES ─────────────────────────────────────────── */
typedef struct _SECURITY_ATTRIBUTES {
    DWORD  nLength;
    void  *lpSecurityDescriptor;
    BOOL   bInheritHandle;
} SECURITY_ATTRIBUTES;

/* ── Windows API declarations ─────────────────────────────────────── */
HANDLE CreateFileA(LPCSTR lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode,
                   SECURITY_ATTRIBUTES *lpSecurityAttributes,
                   DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes,
                   HANDLE hTemplateFile);
BOOL   CloseHandle(HANDLE hObject);
HANDLE GetModuleHandleA(LPCSTR lpModuleName);
void  *GetProcAddress(HANDLE hModule, LPCSTR lpProcName);
HMODULE LoadLibraryA(LPCSTR lpLibFileName);
BOOL    FreeLibrary(HMODULE hLibModule);
DWORD   GetTickCount(void);
void    Sleep(DWORD dwMilliseconds);
DWORD   GetModuleFileNameA(HANDLE hModule, LPSTR lpFilename, DWORD nSize);
void    OutputDebugStringA(LPCSTR lpOutputString);
BOOL    WriteFile(HANDLE hFile, LPCVOID lpBuffer, DWORD nNumberOfBytesToWrite,
                  LPDWORD lpNumberOfBytesWritten, void *lpOverlapped);
int     lstrlenA(LPCSTR lpString);

/* ── DISPLAY_DEVICEA (subset used by adapter detection) ───────────── */
typedef struct _DISPLAY_DEVICEA {
    DWORD cb;
    char  DeviceName[32];
    char  DeviceString[128];
    DWORD StateFlags;
} DISPLAY_DEVICEA;
BOOL EnumDisplayDevicesA(LPCSTR lpDevice, DWORD iDevNum,
                         DISPLAY_DEVICEA *lpDisplayDevice, DWORD dwFlags);

#ifdef __cplusplus
}
#endif

#endif /* MOCK_WINDOWS_H */
