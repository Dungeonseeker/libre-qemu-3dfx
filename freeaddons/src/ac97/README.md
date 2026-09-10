# Intel 810 / ICH AC'97 WDM Audio Driver

Free WDM audio driver for Intel AC'97 controllers, targeting QEMU's `-device AC97` (Intel 82801AA, PCI ID `8086:2415`).

## Provenance
- **Upstream Project:** [ReactOS](https://github.com/reactos/reactos)
- **Upstream Directory:** `drivers/wdm/audio/drivers/ac97`
- **Upstream Commit:** `a55e9ce19cc20afc6b13258321a845684b94d0c6`
- **Original Source:** Microsoft Windows Driver Kit (WDK) 7.1.0 AC'97 sample
- **License:** MIT License (Copyright (c) Microsoft Corporation, LCA-cleared, see `license.txt`)

## Hardware Support
- **PCI ID:** `PCI\VEN_8086&DEV_2415` (Intel 82801AA AC'97 Audio Controller emulated by QEMU)
- **Target OS:** Windows 98 SE, Windows ME, Windows 2000, Windows XP
- **Interface:** Windows Driver Model (WDM) PortClass (`portcls.sys`)
