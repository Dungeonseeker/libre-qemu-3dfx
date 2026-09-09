/*
 * fxmemmap.c — Open-source Windows 9x VxD memory mapping driver for libre-qemu-3dfx
 *
 * Implements the FXMEMMAP dynamic VxD device interface used by Glide on Windows 9x
 * to map QEMU PCI MMIO FIFO BARs into user-mode address space.
 *
 * Compiled with Open Watcom (wcl386 + wlink format windows vxd dynamic).
 * Replaces the proprietary fxmemmap.xxd (3Dfx Interactive 1997 driver blob).
 */

#define W32_DEVICEIOCONTROL 0x0023
#define GETLINEARADDR       2

typedef struct {
    unsigned long   Internal1;
    unsigned long   VMHandle;
    unsigned long   Internal2;
    unsigned long   dwIoControlCode;
    void*           lpvInBuffer;
    unsigned long   cbInBuffer;
    void*           lpvOutBuffer;
    unsigned long   cbOutBuffer;
    unsigned long*  lpcbBytesReturned;
    void*           lpoOverlapped;
    unsigned long   hDevice;
    unsigned long   tagProcess;
} DIOC_PARAMS;

struct VxD_Desc_Block {
    unsigned long   DDB_Next;
    unsigned short  DDB_SDK_Version;
    unsigned short  DDB_Req_Device_Number;
    unsigned char   DDB_Dev_Major_Version;
    unsigned char   DDB_Dev_Minor_Version;
    unsigned short  DDB_Flags;
    char            DDB_Name[8];
    unsigned long   DDB_Init_Order;
    unsigned long   DDB_Control_Proc;
    unsigned long   DDB_V86_API_Proc;
    unsigned long   DDB_PM_API_Proc;
    unsigned long   DDB_V86_API_CSIP;
    unsigned long   DDB_PM_API_CSIP;
    unsigned long   DDB_Reference_Data;
    unsigned long   DDB_Service_Table_Ptr;
    unsigned long   DDB_Service_Table_Size;
    unsigned long   DDB_Win32_Service_Table;
    unsigned long   DDB_Prev;
    unsigned long   DDB_Size;
    unsigned long   DDB_Reserved1;
    unsigned long   DDB_Reserved2;
    unsigned long   DDB_Reserved3;
};

/* VMM service _MapPhysToLinear (service ID 0x0001006c) */
extern unsigned long MapPhysToLinear(unsigned long PhysAddr, unsigned long nBytes, unsigned long flags);
#pragma aux MapPhysToLinear = \
    0xcd 0x20 0x6c 0x00 0x01 0x00 \
    parm [eax] [edx] [ecx] \
    value [eax];

extern int VxD_Device_Control(unsigned long msg, unsigned long vm, DIOC_PARAMS *dioc);
#pragma aux VxD_Device_Control parm [eax] [ebx] [esi] value [eax];

int VxD_Device_Control(unsigned long msg, unsigned long vm, DIOC_PARAMS *dioc)
{
    (void)vm;
    if (msg == W32_DEVICEIOCONTROL && dioc != 0) {
        if (dioc->dwIoControlCode == GETLINEARADDR) {
            unsigned long *pPhys = (unsigned long *)dioc->lpvInBuffer;
            unsigned long *pLin = (unsigned long *)dioc->lpvOutBuffer;
            if (pPhys != 0 && pLin != 0) {
                unsigned long phys_addr = pPhys[0];
                unsigned long length    = pPhys[1];
                unsigned long lin_addr  = MapPhysToLinear(phys_addr, length, 0);

                pLin[0] = lin_addr;
                pLin[1] = length;

                if (dioc->lpcbBytesReturned != 0) {
                    *(dioc->lpcbBytesReturned) = (lin_addr != 0xFFFFFFFF) ? sizeof(unsigned long) * 2 : 0;
                }
                return 0; /* DEVIOCTL_NOERROR */
            }
        }
        return 0;
    }
    return 0;
}

struct VxD_Desc_Block The_DDB = {
    0, 0x0400, 0, 1, 0, 0,
    {'F','X','M','E','M','M','A','P'},
    0, (unsigned long)VxD_Device_Control,
    0, 0, 0, 0, 0, 0, 0, 0, 0, sizeof(struct VxD_Desc_Block), 0, 0, 0
};
