/*
 * qemu-3dfx passthrough hooks for Wine wined3d
 *
 * Reverse-engineered from reference qemu-3dfx Wine 1.8.7 DLLs.
 * Provides HAL enumeration, passthrough control, render target override,
 * cooperative level override, and frame rate limiting.
 *
 * Detection: the QEMUchs guest device (created by the qemu-3dfx guest
 * driver stack) is probed first; the legacy donor heuristics (known
 * qemu-3dfx exe name, "QEMU Bochs" adapter string) are kept as fallback.
 */

#ifndef _WIN32
#error "This file is for Windows PE targets only"
#endif

#include <windows.h>

/* ── Render-target flag location (Wine-version dependent) ──────────
 * struct wined3d_resource layout moves the flag field across Wine
 * versions. Verified against donor DLL disassembly + Wine sources:
 *   1.8.7/1.9.7/2.0.5 : usage      +0x28, WINED3DUSAGE_RENDERTARGET (0x1)
 *   3.0.5             : usage      +0x2C, 0x1
 *   4.12.1            : bind_flags +0x30, WINED3D_BIND_RENDER_TARGET (0x20)
 *   5.0.5             : bind_flags +0x34, 0x20
 *   6.0.4/7.0.2       : bind_flags +0x30, 0x20  (donor-verified)
 *   8.0.2             : bind_flags +0x34, 0x20
 * Default = 6.0.4 layout (primary donor reference). The Dockerfile
 * overrides per version via -DQEMU3DFX_RTV_FLAG_OFFSET / _BIT. */
#ifndef QEMU3DFX_RTV_FLAG_OFFSET
#define QEMU3DFX_RTV_FLAG_OFFSET 0x30
#endif
#ifndef QEMU3DFX_RTV_FLAG_BIT
#define QEMU3DFX_RTV_FLAG_BIT 0x20
#endif

/* ── Globals ───────────────────────────────────────────────────────
 * Initializers match the donor .data section (Wine 6.0.4 build):
 * enum_hal_last starts TRUE and is cleared by config probing unless
 * the D3D1EnumHalLast registry value says otherwise. ddheap starts
 * FALSE. override counter/trigger start at sentinel (feature off). */

BOOL qemu3dfx_detected = FALSE;
BOOL hal_enum_done = TRUE;
BOOL ddheap_active = FALSE;
BOOL passthru_enabled = FALSE;
DWORD override_counter = (DWORD)-1;
DWORD override_trigger = (DWORD)-1;
DWORD blit_frame_count = 0;
DWORD flip_frame_count = 0;
static DWORD blit_fps_counter = 0;
static DWORD flip_fps_flag = 0;
static DWORD fps_timestamp = 0;

/* WGL_3DFX_gamma_control extension entry points, resolved lazily via
 * GetProcAddress once passthrough is detected. NULL = unavailable. */
typedef BOOL (WINAPI *WGL3DFXPROC)(void *, void *);
WGL3DFXPROC p_wglGetDeviceGammaRamp3DFX = NULL;
WGL3DFXPROC p_wglSetDeviceGammaRamp3DFX = NULL;
WGL3DFXPROC p_wglSetDeviceCursor3DFX = NULL;
const char wgl_3dfx_gamma_control[] = "WGL_3DFX_gamma_control";

/* ── Frame rate limiter (matches reference RVA 0x29190) ────────────── */

static void fps_limit(DWORD divisor)
{
    DWORD now, end, target;

    if (divisor == 0) return;

    for (;;)
    {
        now = GetTickCount();
        if (now >= fps_timestamp)
            break;
        Sleep(0);
    }

    end = now;
    target = 1000 / divisor;

    if (end >= (DWORD)~target)
    {
        while (end >= (DWORD)~target)
            end = GetTickCount();
        fps_timestamp = end;
    }

    fps_timestamp = end + target;
}

/* ── QEMU display adapter detection (matches reference RVA 0x2AAFD) ── */

static int str_compare(const char *a, const char *b, int n)
{
    int i;
    for (i = 0; i < n; i++)
    {
        if (a[i] != b[i])
            return 1;
        if (a[i] == '\0' || b[i] == '\0')
            break;
    }
    return 0;
}

static BOOL detect_qemu_bochs(void)
{
    DISPLAY_DEVICEA dd;

    memset(&dd, 0, sizeof(dd));
    dd.cb = sizeof(dd);

    if (!EnumDisplayDevicesA(NULL, 0, &dd, 0))
        return FALSE;

    if (strstr(dd.DeviceString, "QEMU") ||
        strstr(dd.DeviceString, "Bochs") ||
        strstr(dd.DeviceString, "VGA") ||
        strstr(dd.DeviceString, "Cirrus"))
        return TRUE;

    return FALSE;
}

/* ── Known qemu-3dfx host applications (donor heuristic) ───────────── */

static BOOL detect_qemu_exe(void)
{
    static const char * const exe_names[] = { "ds9dw.exe", NULL };
    char buf[260];
    const char * const *name;
    DWORD ret;

    ret = GetModuleFileNameA(NULL, buf, sizeof(buf));
    if (ret == 0 || ret > sizeof(buf) - 1)
        return FALSE;

    for (name = exe_names; *name; name++)
    {
        if (strstr(buf, *name))
            return TRUE;
    }
    return FALSE;
}

static void qemu3dfx_log(const char *msg)
{
    HANDLE h;
    DWORD written;
    if (!msg || !*msg) return;
    OutputDebugStringA(msg);
    h = CreateFileA("C:\\wined3d.log", FILE_APPEND_DATA,
                    FILE_SHARE_READ | FILE_SHARE_WRITE,
                    NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE)
        h = CreateFileA("wined3d.log", FILE_APPEND_DATA,
                        FILE_SHARE_READ | FILE_SHARE_WRITE,
                        NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h != INVALID_HANDLE_VALUE)
    {
        WriteFile(h, msg, lstrlenA(msg), &written, NULL);
        CloseHandle(h);
    }
}

/* ── Passthrough detection ───────────────────────────────────────────
 * Primary NT/XP: \\.\MAPMEM device exposed by fxptl.sys.
 * Primary Win9x: \\.\QEMUchs device exposed by fxmemmap.vxd.
 * Direct: wglGetDeviceGammaRamp3DFX in opengl32.dll.
 * Fallbacks: known exe name, adapter string. */

#define QEMUCHS_DEVICE "\\\\.\\QEMUchs"
#define MAPMEM_DEVICE  "\\\\.\\MAPMEM"

BOOL detect_qemu_passthrough(void)
{
    HANDLE h;
    HMODULE hgl;

    qemu3dfx_log("qemu3dfx: Probing hardware passthrough...\r\n");

    /* 1. NT/XP kernel driver */
    h = CreateFileA(MAPMEM_DEVICE, GENERIC_READ | GENERIC_WRITE,
                    0, NULL, OPEN_EXISTING, 0, NULL);
    if (h != INVALID_HANDLE_VALUE)
    {
        CloseHandle(h);
        qemu3dfx_log("qemu3dfx: Found \\\\.\\MAPMEM (fxptl.sys NT passthrough driver)\r\n");
        return TRUE;
    }

    /* 2. Win9x kernel driver */
    h = CreateFileA(QEMUCHS_DEVICE, GENERIC_READ | GENERIC_WRITE,
                    0, NULL, OPEN_EXISTING, 0, NULL);
    if (h != INVALID_HANDLE_VALUE)
    {
        CloseHandle(h);
        qemu3dfx_log("qemu3dfx: Found \\\\.\\QEMUchs (fxmemmap.vxd Win9x passthrough driver)\r\n");
        return TRUE;
    }

    /* 3. Direct OpenGL 3dfx passthrough wrapper check */
    hgl = GetModuleHandleA("opengl32.dll");
    if (hgl && GetProcAddress(hgl, "wglGetDeviceGammaRamp3DFX"))
    {
        qemu3dfx_log("qemu3dfx: Found wglGetDeviceGammaRamp3DFX in opengl32.dll\r\n");
        return TRUE;
    }

    if (detect_qemu_exe())
    {
        qemu3dfx_log("qemu3dfx: Matched known qemu exe name\r\n");
        return TRUE;
    }

    if (detect_qemu_bochs())
    {
        qemu3dfx_log("qemu3dfx: Matched QEMU display adapter string\r\n");
        return TRUE;
    }

    qemu3dfx_log("qemu3dfx: Passthrough NOT detected\r\n");
    return FALSE;
}

/* ── WGL extension loader ──────────────────────────────────────────── */

static void load_wgl_3dfx_extensions(void)
{
    HMODULE hgl;

    hgl = GetModuleHandleA("opengl32.dll");
    if (!hgl)
        return;

    p_wglGetDeviceGammaRamp3DFX =
        (WGL3DFXPROC)GetProcAddress(hgl, "wglGetDeviceGammaRamp3DFX");
    p_wglSetDeviceGammaRamp3DFX =
        (WGL3DFXPROC)GetProcAddress(hgl, "wglSetDeviceGammaRamp3DFX");
    p_wglSetDeviceCursor3DFX =
        (WGL3DFXPROC)GetProcAddress(hgl, "wglSetDeviceCursor3DFX");
}

/* Sticky detection: probe until found, then resolve extensions once. */

void ensure_detected(void)
{
    if (qemu3dfx_detected)
        return;

    if (detect_qemu_passthrough())
    {
        qemu3dfx_detected = TRUE;
        qemu3dfx_log("qemu3dfx: Hardware passthrough active!\r\n");
        load_wgl_3dfx_extensions();
    }
}

/* ── Exported hooks ────────────────────────────────────────────────── */

BOOL WINAPI wined3d_enum_hal_last(void)
{
    return hal_enum_done;
}

BOOL WINAPI wined3d_passthru(BOOL *enabled)
{
    if (enabled && *enabled)
        passthru_enabled = 1;
    return passthru_enabled;
}

void WINAPI wined3d_override_cooplevel(DWORD *cooplevel)
{
    /* Matches donor RVA 0x4b65b exactly:
       - Sentinel counter = feature off (donor .data default).
       - If override_trigger != -1, toggle bit 0 (*cooplevel ^= 1).
       - If override_counter == 1, toggle bit 4 (*cooplevel ^= 0x10).
       There is no counter decrement in the donor binary. */
    if (!cooplevel || override_counter == (DWORD)-1)
        return;

    if (override_trigger != (DWORD)-1)
        *cooplevel ^= 1;

    if (override_counter == 1)
        *cooplevel ^= 0x10;
}

BOOL WINAPI wined3d_hal_3dfx(void)
{
    ensure_detected();
    return qemu3dfx_detected;
}

void WINAPI wined3d_override_rendertarget_view(void *view_ptr)
{
    /* Force the resource's render-target capability flag so the view
       binds as a render target under passthrough. Field location is
       Wine-version dependent — see QEMU3DFX_RTV_FLAG_OFFSET/_BIT. */
    void **view = (void **)view_ptr;
    DWORD *flags;

    if (!view) return;
    if (!view[1]) return;

    flags = (DWORD *)((char *)view[1] + QEMU3DFX_RTV_FLAG_OFFSET);
    if (!(*flags & QEMU3DFX_RTV_FLAG_BIT))
        *flags |= QEMU3DFX_RTV_FLAG_BIT;
}

BOOL WINAPI wined3d_blit_fpslimit(void)
{
    DWORD fps;

    blit_frame_count++;

    fps = blit_fps_counter & 0x7f;
    if (fps)
        fps_limit(fps);
    return TRUE;
}

BOOL WINAPI wined3d_flip_fpslimit(void)
{
    flip_frame_count++;

    if (flip_fps_flag)
        fps_limit(flip_fps_flag);
    return TRUE;
}

/* ── WGL_3DFX_gamma_control entry points ─────────────────────────────
 * Forward to the host driver's extension functions when resolved;
 * FALSE while unavailable (mirrors the donor's graceful fallback). */

BOOL WINAPI wined3d_get_gamma_ramp_3dfx(void *a, void *b)
{
    if (!p_wglGetDeviceGammaRamp3DFX)
        return FALSE;
    return p_wglGetDeviceGammaRamp3DFX(a, b);
}

BOOL WINAPI wined3d_set_gamma_ramp_3dfx(void *a, void *b)
{
    if (!p_wglSetDeviceGammaRamp3DFX)
        return FALSE;
    return p_wglSetDeviceGammaRamp3DFX(a, b);
}

BOOL WINAPI wined3d_set_cursor_3dfx(void *a, void *b)
{
    if (!p_wglSetDeviceCursor3DFX)
        return FALSE;
    return p_wglSetDeviceCursor3DFX(a, b);
}

/* ── DDHeap surface accessor (returns TRUE when HAL passthrough is active) ── */

BOOL WINAPI wined3d_surface_ddheap(void)
{
    return ddheap_active;
}

/* ── Registry config keys ─────────────────────────────────────────── */

const char qemu3dfx_hal_key[] = "D3D1Hal3Dfx";
const char qemu3dfx_enum_hal_last_key[] = "D3D1EnumHalLast";
