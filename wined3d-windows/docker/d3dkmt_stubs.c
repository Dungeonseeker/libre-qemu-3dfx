/* D3DKMT emulation and stubs for Windows NT (XP/2000) and Win9x.
   On Windows Vista+, D3DKMT functions are provided by gdi32.dll for
   kernel-mode display driver interactions. On Windows XP and earlier,
   these functions do not exist in the OS.

   Upstream Wine 6.0+ relies on D3DKMTCreateDCFromMemory and
   D3DKMTDestroyDCFromMemory in dlls/wined3d/texture.c to create GDI-accessible
   DCs for texture surfaces. Returning STATUS_UNSUCCESSFUL breaks all texture
   DC operations (GDI blits, text rendering, surface locking).

   This implementation mirrors the donor binary's built-in DIBSection
   emulation (RVA 0x1004b7b2 and 0x1004b95b):
   1. D3DKMTCreateDCFromMemory maps D3DDDIFORMAT to BITMAPINFO, creates a
      DIBSection and memory DC, and tracks the allocation in a linked list.
   2. D3DKMTDestroyDCFromMemory copies modified DIB pixels back to the caller's
      texture memory, deletes the DC and bitmap, and frees the tracking node.
   3. D3DKMTOpenAdapterFromGdiDisplayName returns STATUS_NOT_IMPLEMENTED,
      causing Wine to fall back to legacy GDI display device enumeration.
   4. Stubs for CloseAdapter, CreateDevice, DestroyDevice, SetVidPnSourceOwner
      return STATUS_SUCCESS. */

#include <windows.h>
#include <string.h>

#ifndef STATUS_SUCCESS
#define STATUS_SUCCESS          ((NTSTATUS)0x00000000L)
#endif
#ifndef STATUS_UNSUCCESSFUL
#define STATUS_UNSUCCESSFUL     ((NTSTATUS)0xC0000001L)
#endif
#ifndef STATUS_NOT_IMPLEMENTED
#define STATUS_NOT_IMPLEMENTED  ((NTSTATUS)0xC0000002L)
#endif

typedef struct _D3DKMT_CREATEDCFROMMEMORY {
    void *pMemory;
    UINT Format;
    UINT Width;
    UINT Height;
    UINT Pitch;
    HDC hDeviceDc;
    PALETTEENTRY *pColorTable;
    HDC hDc;
    HANDLE hBitmap;
} D3DKMT_CREATEDCFROMMEMORY;

typedef struct _D3DKMT_DESTROYDCFROMMEMORY {
    HDC hDc;
    HANDLE hBitmap;
} D3DKMT_DESTROYDCFROMMEMORY;

/* Format mapping table matching donor wined3d.dll RVA 0x100a9240 */
struct d3dkmt_format_entry {
    UINT format;
    WORD bit_count;
    WORD reserved;
    DWORD compression;
    DWORD clr_used;
    DWORD red_mask;
    DWORD green_mask;
    DWORD blue_mask;
};

static const struct d3dkmt_format_entry format_table[] = {
    { 0x14, 24, 0, BI_RGB, 0, 0, 0, 0 },
    { 0x15, 32, 0, BI_RGB, 0, 0, 0, 0 },
    { 0x16, 32, 0, BI_RGB, 0, 0, 0, 0 },
    { 0x17, 16, 0, BI_BITFIELDS, 0, 0x0000f800, 0x000007e0, 0x0000001f },
    { 0x18, 16, 0, BI_BITFIELDS, 0, 0x00007c00, 0x000003e0, 0x0000001f },
    { 0x19, 16, 0, BI_BITFIELDS, 0, 0x00007c00, 0x000003e0, 0x0000001f },
    { 0x1a, 16, 0, BI_BITFIELDS, 0, 0x00000f00, 0x000000f0, 0x0000000f },
    { 0x1e, 16, 0, BI_BITFIELDS, 0, 0x00000f00, 0x000000f0, 0x0000000f },
    { 0x29, 8, 0, BI_RGB, 256, 0x00000100, 0, 0 },
};

struct d3dkmt_dib_node {
    struct d3dkmt_dib_node *next;
    HDC hDc;
    HANDLE hBitmap;
    HGDIOBJ hOldBitmap;
    void *pMemory;
    void *pBits;
    UINT size;
};

static struct d3dkmt_dib_node *g_dib_head = NULL;
static CRITICAL_SECTION g_dib_cs;
static volatile LONG g_dib_inited = 0;

static void d3dkmt_lock(void)
{
    if (InterlockedCompareExchange((LONG *)&g_dib_inited, 1, 0) == 0)
    {
        InitializeCriticalSection(&g_dib_cs);
        g_dib_inited = 2;
    }
    else
    {
        while (g_dib_inited != 2) Sleep(1);
    }
    EnterCriticalSection(&g_dib_cs);
}

static void d3dkmt_unlock(void)
{
    LeaveCriticalSection(&g_dib_cs);
}

NTSTATUS __stdcall D3DKMTCreateDCFromMemory(D3DKMT_CREATEDCFROMMEMORY *desc)
{
    const struct d3dkmt_format_entry *fmt = NULL;
    struct {
        BITMAPINFOHEADER bmiHeader;
        RGBQUAD bmiColors[256];
    } bmi;
    void *pBits = NULL;
    HBITMAP hBitmap;
    HDC hDc;
    HGDIOBJ hOldBitmap;
    UINT size;
    size_t i;

    if (!desc)
        return STATUS_UNSUCCESSFUL;

    for (i = 0; i < sizeof(format_table) / sizeof(format_table[0]); i++)
    {
        if (format_table[i].format == desc->Format)
        {
            fmt = &format_table[i];
            break;
        }
    }

    if (!fmt)
    {
        OutputDebugStringA("qemu3dfx: D3DKMTCreateDCFromMemory unsupported format\n");
        return STATUS_UNSUCCESSFUL;
    }

    memset(&bmi, 0, sizeof(bmi));
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = desc->Width;
    bmi.bmiHeader.biHeight = -(LONG)desc->Height;
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = fmt->bit_count;
    bmi.bmiHeader.biCompression = fmt->compression;
    bmi.bmiHeader.biClrUsed = fmt->clr_used;
    size = desc->Pitch * desc->Height;
    bmi.bmiHeader.biSizeImage = size;

    if (fmt->compression == BI_BITFIELDS)
    {
        DWORD *masks = (DWORD *)bmi.bmiColors;
        masks[0] = fmt->red_mask;
        masks[1] = fmt->green_mask;
        masks[2] = fmt->blue_mask;
    }
    else if (fmt->format == 0x29 && desc->pColorTable)
    {
        memcpy(bmi.bmiColors, desc->pColorTable, 256 * sizeof(RGBQUAD));
    }

    hBitmap = CreateDIBSection(desc->hDeviceDc, (const BITMAPINFO *)&bmi,
                               DIB_RGB_COLORS, &pBits, NULL, 0);
    if (!hBitmap || !pBits)
    {
        OutputDebugStringA("qemu3dfx: CreateDIBSection failed\n");
        return STATUS_UNSUCCESSFUL;
    }

    hDc = CreateCompatibleDC(desc->hDeviceDc);
    if (!hDc)
    {
        DeleteObject(hBitmap);
        return STATUS_UNSUCCESSFUL;
    }

    hOldBitmap = SelectObject(hDc, hBitmap);

    if (desc->pMemory && pBits && size > 0)
    {
        memcpy(pBits, desc->pMemory, size);
    }

    desc->hDc = hDc;
    desc->hBitmap = (HANDLE)hBitmap;

    struct d3dkmt_dib_node *node =
        (struct d3dkmt_dib_node *)HeapAlloc(GetProcessHeap(), 0, sizeof(*node));
    if (node)
    {
        node->hDc = hDc;
        node->hBitmap = (HANDLE)hBitmap;
        node->hOldBitmap = hOldBitmap;
        node->pMemory = desc->pMemory;
        node->pBits = pBits;
        node->size = size;

        d3dkmt_lock();
        node->next = g_dib_head;
        g_dib_head = node;
        d3dkmt_unlock();
    }

    return STATUS_SUCCESS;
}

NTSTATUS __stdcall D3DKMTDestroyDCFromMemory(const D3DKMT_DESTROYDCFROMMEMORY *desc)
{
    struct d3dkmt_dib_node **curr;
    struct d3dkmt_dib_node *node = NULL;

    if (!desc)
        return STATUS_UNSUCCESSFUL;

    d3dkmt_lock();
    for (curr = &g_dib_head; *curr; curr = &(*curr)->next)
    {
        if ((*curr)->hDc == desc->hDc || (*curr)->hBitmap == desc->hBitmap)
        {
            node = *curr;
            *curr = node->next;
            break;
        }
    }
    d3dkmt_unlock();

    if (node)
    {
        if (node->pMemory && node->pBits && node->size > 0)
        {
            memcpy(node->pMemory, node->pBits, node->size);
        }
        if (desc->hDc && node->hOldBitmap)
        {
            SelectObject(desc->hDc, node->hOldBitmap);
        }
        HeapFree(GetProcessHeap(), 0, node);
    }

    if (desc->hDc)
        DeleteDC(desc->hDc);
    if (desc->hBitmap)
        DeleteObject(desc->hBitmap);

    return STATUS_SUCCESS;
}

typedef struct _D3DKMT_OPENADAPTERFROMGDIDISPLAYNAME {
    WCHAR DeviceName[32];
    UINT hAdapter;
    LUID AdapterLuid;
    UINT VidPnSourceId;
} D3DKMT_OPENADAPTERFROMGDIDISPLAYNAME;

typedef struct _D3DKMT_OPENADAPTERFROMLUID {
    LUID AdapterLuid;
    UINT hAdapter;
} D3DKMT_OPENADAPTERFROMLUID;

typedef struct _D3DKMT_CREATEDEVICE {
    UINT hAdapter;
    DWORD Flags;
    UINT hDevice;
    void *pCommandBuffer;
    UINT CommandBufferSize;
    void *pAllocationList;
    UINT AllocationListSize;
    void *pPatchLocationList;
    UINT PatchLocationListSize;
} D3DKMT_CREATEDEVICE;

NTSTATUS __stdcall D3DKMTOpenAdapterFromGdiDisplayName(D3DKMT_OPENADAPTERFROMGDIDISPLAYNAME *desc)
{
    if (!desc)
        return STATUS_UNSUCCESSFUL;

    desc->hAdapter = 1;
    desc->AdapterLuid.LowPart = 1;
    desc->AdapterLuid.HighPart = 0;
    desc->VidPnSourceId = 0;
    return STATUS_SUCCESS;
}

NTSTATUS __stdcall D3DKMTOpenAdapterFromLuid(D3DKMT_OPENADAPTERFROMLUID *desc)
{
    if (!desc)
        return STATUS_UNSUCCESSFUL;

    desc->hAdapter = 1;
    return STATUS_SUCCESS;
}

NTSTATUS __stdcall D3DKMTQueryVideoMemoryInfo(void *a)
{
    (void)a;
    return STATUS_NOT_IMPLEMENTED;
}

NTSTATUS __stdcall D3DKMTCloseAdapter(const void *a)
{
    (void)a;
    return STATUS_SUCCESS;
}

NTSTATUS __stdcall D3DKMTCreateDevice(D3DKMT_CREATEDEVICE *desc)
{
    if (!desc)
        return STATUS_UNSUCCESSFUL;

    desc->hDevice = 1;
    return STATUS_SUCCESS;
}

NTSTATUS __stdcall D3DKMTDestroyDevice(const void *a)
{
    (void)a;
    return STATUS_SUCCESS;
}

NTSTATUS __stdcall D3DKMTSetVidPnSourceOwner(const void *a)
{
    (void)a;
    return STATUS_SUCCESS;
}
