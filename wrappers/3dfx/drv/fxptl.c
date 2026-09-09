/*
 * fxptl.c — Open-source physical memory mapping driver for libre-qemu-3dfx
 *
 * Implements the MAPMEM device interface used by Glide and Mesa OpenGL
 * wrappers to map QEMU PCI MMIO FIFO BARs into user-mode process address space.
 *
 * Replaces the proprietary fxptl.xxd (Microsoft NT DDK mapmem.sys sample blob).
 */

#define _WIN32_WINNT 0x0501
#define NTDDI_VERSION 0x05010200
#define _X86_ 1

/* Workaround for MinGW-w64 ddk header issue */
typedef struct { int dummy; } SYSTEM_POWER_STATE_CONTEXT;

#include <ddk/wdm.h>
#include <ddk/ntddk.h>

#define FILE_DEVICE_MAPMEM                      0x00008000
#define MAPMEM_IOCTL_INDEX                      0x800

#define IOCTL_MAPMEM_MAP_USER_PHYSICAL_MEMORY   CTL_CODE(FILE_DEVICE_MAPMEM, MAPMEM_IOCTL_INDEX,   METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_MAPMEM_UNMAP_USER_PHYSICAL_MEMORY CTL_CODE(FILE_DEVICE_MAPMEM, MAPMEM_IOCTL_INDEX+1, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_MAPMEM_GET_MSR                    CTL_CODE(FILE_DEVICE_MAPMEM, MAPMEM_IOCTL_INDEX+2, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_MAPMEM_SET_MSR                    CTL_CODE(FILE_DEVICE_MAPMEM, MAPMEM_IOCTL_INDEX+3, METHOD_BUFFERED, FILE_ANY_ACCESS)

typedef struct {
    INTERFACE_TYPE InterfaceType;
    ULONG BusNumber;
    LARGE_INTEGER BusAddress;
    ULONG AddressSpace;
    ULONG Length;
} PHYSICAL_MEMORY_INFO, *PPHYSICAL_MEMORY_INFO;

typedef struct {
    ULONG msrNum;
    ULONG msrLo;
    ULONG msrHi;
} MSRInfo;

static UNICODE_STRING g_DeviceName;
static UNICODE_STRING g_SymbolicLinkName;

static NTSTATUS NTAPI FxptlCreateClose(PDEVICE_OBJECT DeviceObject, PIRP Irp)
{
    (void)DeviceObject;
    Irp->IoStatus.Status = STATUS_SUCCESS;
    Irp->IoStatus.Information = 0;
    IoCompleteRequest(Irp, IO_NO_INCREMENT);
    return STATUS_SUCCESS;
}

static NTSTATUS NTAPI FxptlDeviceControl(PDEVICE_OBJECT DeviceObject, PIRP Irp)
{
    PIO_STACK_LOCATION irpSp = IoGetCurrentIrpStackLocation(Irp);
    ULONG ioControlCode = irpSp->Parameters.DeviceIoControl.IoControlCode;
    ULONG inLen = irpSp->Parameters.DeviceIoControl.InputBufferLength;
    ULONG outLen = irpSp->Parameters.DeviceIoControl.OutputBufferLength;
    PVOID buffer = Irp->AssociatedIrp.SystemBuffer;
    NTSTATUS status = STATUS_SUCCESS;
    ULONG info = 0;

    (void)DeviceObject;

    switch (ioControlCode) {
    case IOCTL_MAPMEM_MAP_USER_PHYSICAL_MEMORY:
        if (inLen < sizeof(PHYSICAL_MEMORY_INFO) || outLen < sizeof(PVOID) || !buffer) {
            status = STATUS_BUFFER_TOO_SMALL;
            break;
        } else {
            PPHYSICAL_MEMORY_INFO pmi = (PPHYSICAL_MEMORY_INFO)buffer;
            UNICODE_STRING physMemString;
            OBJECT_ATTRIBUTES objAttributes;
            HANDLE hSection = NULL;

            RtlInitUnicodeString(&physMemString, L"\\Device\\PhysicalMemory");
            InitializeObjectAttributes(&objAttributes, &physMemString, OBJ_CASE_INSENSITIVE, NULL, NULL);

            status = ZwOpenSection(&hSection, SECTION_ALL_ACCESS, &objAttributes);
            if (NT_SUCCESS(status)) {
                PHYSICAL_ADDRESS viewBase;
                SIZE_T viewSize = pmi->Length;
                PVOID baseAddress = NULL;

                viewBase.QuadPart = pmi->BusAddress.QuadPart;

                status = ZwMapViewOfSection(hSection,
                                            NtCurrentProcess(),
                                            &baseAddress,
                                            0,
                                            viewSize,
                                            &viewBase,
                                            &viewSize,
                                            ViewUnmap,
                                            0,
                                            PAGE_READWRITE | PAGE_NOCACHE);
                ZwClose(hSection);
                if (NT_SUCCESS(status)) {
                    *(PVOID*)buffer = baseAddress;
                    info = sizeof(PVOID);
                }
            }
        }
        break;

    case IOCTL_MAPMEM_UNMAP_USER_PHYSICAL_MEMORY:
        if (inLen < sizeof(PVOID) || !buffer) {
            status = STATUS_BUFFER_TOO_SMALL;
            break;
        } else {
            PVOID baseAddress = *(PVOID*)buffer;
            status = ZwUnmapViewOfSection(NtCurrentProcess(), baseAddress);
            info = 0;
        }
        break;

    case IOCTL_MAPMEM_GET_MSR:
        if (inLen < sizeof(ULONG) || outLen < sizeof(MSRInfo) || !buffer) {
            status = STATUS_BUFFER_TOO_SMALL;
            break;
        } else {
            ULONG msrNum = *(ULONG*)buffer;
            MSRInfo *pMsr = (MSRInfo*)buffer;
            unsigned int lo = 0, hi = 0;
            __asm__ __volatile__("rdmsr" : "=a"(lo), "=d"(hi) : "c"(msrNum));
            pMsr->msrNum = msrNum;
            pMsr->msrLo = lo;
            pMsr->msrHi = hi;
            info = sizeof(MSRInfo);
        }
        break;

    case IOCTL_MAPMEM_SET_MSR:
        if (inLen < sizeof(MSRInfo) || !buffer) {
            status = STATUS_BUFFER_TOO_SMALL;
            break;
        } else {
            MSRInfo *pMsr = (MSRInfo*)buffer;
            __asm__ __volatile__("wrmsr" : : "c"(pMsr->msrNum), "a"(pMsr->msrLo), "d"(pMsr->msrHi));
            info = 0;
        }
        break;

    default:
        status = STATUS_INVALID_DEVICE_REQUEST;
        break;
    }

    Irp->IoStatus.Status = status;
    Irp->IoStatus.Information = info;
    IoCompleteRequest(Irp, IO_NO_INCREMENT);
    return status;
}

static VOID NTAPI FxptlUnload(PDRIVER_OBJECT DriverObject)
{
    IoDeleteSymbolicLink(&g_SymbolicLinkName);
    if (DriverObject->DeviceObject) {
        IoDeleteDevice(DriverObject->DeviceObject);
    }
}

NTSTATUS NTAPI DriverEntry(PDRIVER_OBJECT DriverObject, PUNICODE_STRING RegistryPath)
{
    NTSTATUS status;
    PDEVICE_OBJECT deviceObject = NULL;

    (void)RegistryPath;

    RtlInitUnicodeString(&g_DeviceName, L"\\Device\\MAPMEM");
    RtlInitUnicodeString(&g_SymbolicLinkName, L"\\DosDevices\\MAPMEM");

    status = IoCreateDevice(DriverObject,
                            0,
                            &g_DeviceName,
                            FILE_DEVICE_MAPMEM,
                            0,
                            FALSE,
                            &deviceObject);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    status = IoCreateSymbolicLink(&g_SymbolicLinkName, &g_DeviceName);
    if (!NT_SUCCESS(status)) {
        IoDeleteDevice(deviceObject);
        return status;
    }

    DriverObject->MajorFunction[IRP_MJ_CREATE] = FxptlCreateClose;
    DriverObject->MajorFunction[IRP_MJ_CLOSE] = FxptlCreateClose;
    DriverObject->MajorFunction[IRP_MJ_DEVICE_CONTROL] = FxptlDeviceControl;
    DriverObject->DriverUnload = FxptlUnload;

    return STATUS_SUCCESS;
}
