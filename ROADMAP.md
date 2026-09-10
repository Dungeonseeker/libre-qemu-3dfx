# Roadmap

TODO for Beta:

### Core & Kernel Drivers
- ~~Eliminate proprietary binary driver blobs (fxptl.xxd, fxmemmap.xxd) with clean-room C implementations~~ — Implemented free fxptl.c (WDM NT kernel driver) and fxmemmap.c (Open Watcom dynamic VxD), verified under full 3DMark03 load

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
- Publish portable pre-built QEMU binaries per release (x86-64 baseline without restrictive CPUID or march flags, compatible across Skylake through Zen 5 class CPUs)
- Forward-port 3dfx/Mesa patches to future QEMU 10.x

### Guest UX & Installers
- ~~Bundle free 2D display driver for Windows 9x~~ — Integrated VMDisp9x (v1.2025.0.119b, MIT) with dedicated QEMU Standard VGA miniport (qemumini.drv / qemumini.vxd)
- ~~Bundle free AC'97 audio driver for Windows 98/2000/XP~~ — Integrated Intel 810 / ICH AC'97 WDM driver (MIT, ReactOS / WDK 7.1) for QEMU -device AC97
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
- Evaluate Aaru disc image format support

