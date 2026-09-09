# Roadmap

TODO for Beta:

### Core & Kernel Drivers
- [x] Eliminate proprietary binary driver blobs (`fxptl.xxd`, `fxmemmap.xxd`) with clean-room C implementations:
  - [`fxptl.c`](wrappers/3dfx/drv/fxptl.c): Windows NT/2000/XP WDM kernel driver mapping MMIO/FIFO physical memory. Verified under full 3DMark03 load.
  - [`fxmemmap.c`](wrappers/3dfx/drv/fxmemmap.c): Windows 9x dynamic VxD driver compiled natively via Open Watcom `wcl386`/`wlink`.

### Game Testing
- 3DMark2001 SE on Windows 98 and Windows XP (DirectX 8.1)
- ~~Need for Speed: Underground 2 (DirectX 9.0)~~ — Verified on Windows XP (Wine 6.0.4 D3D9 passthrough, full audio with native DirectSound, 35–50 FPS matching 30 Hz engine design)
- ~~3DMark03 (DirectX 9.0)~~ — Verified on Windows XP (Wine 6.0.4 D3D9 passthrough, 44,715 3DMarks at 1024x768)
- Half-Life 2 (Source Engine / SM2.0)
- Max Payne (DirectX 8.0)
- Diablo II and StarCraft (DirectDraw / DirectX 7)
- Unreal / UT99 (Glide 2x/3x)
- Tomb Raider / Carmageddon (DOS Glide OVL)
- Quake III Arena (Mesa OpenGL)

### CI/CD & Releases
- GitHub Actions workflow to build freeaddons.iso on release tags
- Automatic upload of freeaddons.iso and sha256 checksums to GitHub Releases
- Automated unit test suite in CI

### Host Packages
- Arch Linux AUR package (libre-qemu-3dfx-git)
- Debian/Ubuntu package or AppImage
- Forward-port 3dfx/Mesa patches to future QEMU 10.x

### Guest UX & Installers
- One-click autorun installer on freeaddons.iso
- Bundle USB tablet mouse driver for Windows 98
- Winetray utility for switching WineD3D versions per game

### Optimizations
- Verify Wine 7.x and 8.x profiles for Shader Model 3.0 games
- Optimize D3DKMT surface locks at high resolutions

### Future (Post-1.0)
- Standalone GUI Frontend (ImGui or Qt) for VM configuration and game profiles
- Integration with external retro launchers
- Host UX and packaging optimizations for Windows and macOS

