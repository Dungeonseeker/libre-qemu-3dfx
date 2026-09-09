# QEMU MESA GL/3Dfx Glide Pass-Through
Copyright (C) 2018-2026<br>
https://github.com/wordgitet/libre-qemu-3dfx<br>
https://www.winehq.org

## Content
    freeaddons/         - FreeAddons guest additions ISO build toolchain
    qemu-0/hw/3dfx      - Overlay for QEMU source tree to add 3Dfx Glide pass-through device model
    qemu-1/hw/mesa      - Overlay for QEMU source tree to add MESA GL pass-through device model
    scripts/sign_commit - Script for stamping commit id
    wined3d-windows/    - Universal WineD3D build system (DirectDraw, D3D8, D3D9)
    wrappers/3dfx       - Glide wrappers for supported guest OS/environment (DOS/Windows/DJGPP/Linux)
    wrappers/mesa       - MESA GL wrapper for supported guest OS/environment (Windows)
## Patch
    00-qemu92x-mesa-glide.patch - Patch for QEMU version 9.2.x (MESA & Glide)
    01-qemu82x-mesa-glide.patch - Patch for QEMU version 8.2.x (MESA & Glide)
    02-qemu72x-mesa-glide.patch - Patch for QEMU version 7.2.x (MESA & Glide)
## QEMU Windows Guests Glide/OpenGL/Direct3D Acceleration
Witness, experience and share your thoughts on modern CPU/GPU prowess for retro Windows games on Apple Silicon macOS, modern Windows and Linux. Most games can be installed and played in pristine condition without the hassle of hunting down unofficial, fan-made patches to play them on modern Windows or Linux/Wine.
- YouTube channel (https://www.youtube.com/@qemu-3dfx/videos)
- VOGONS forums (https://www.vogons.org)
- Wiki (https://github.com/wordgitet/libre-qemu-3dfx/wiki)
## Building QEMU

### Host Build Dependencies
- **Debian / Ubuntu**:
  ```bash
  sudo apt install git build-essential ninja-build meson libglib2.0-dev libpixman-1-dev libsdl2-dev pkg-config python3-venv wget rsync
  ```
- **Arch Linux**:
  ```bash
  sudo pacman -S git base-devel ninja meson glib2 pixman sdl2 wget rsync
  ```
- **Fedora**:
  ```bash
  sudo dnf install git make gcc ninja-build meson glib2-devel pixman-devel SDL2-devel pkgconf-pkg-config wget rsync
  ```
- **Windows (MSYS2 `mingw64` shell)**:
  ```bash
  pacman -S base-devel mingw-w64-x86_64-toolchain ninja meson mingw-w64-x86_64-glib2 mingw-w64-x86_64-pixman mingw-w64-x86_64-SDL2 wget rsync
  ```

### Guide to Apply Patch & Build
(using `00-qemu92x-mesa-glide.patch` with QEMU 9.2.2):

```bash
mkdir ~/myqemu && cd ~/myqemu
git clone https://github.com/wordgitet/libre-qemu-3dfx.git
cd libre-qemu-3dfx
wget https://download.qemu.org/qemu-9.2.2.tar.xz
tar xf qemu-9.2.2.tar.xz
cd qemu-9.2.2
rsync -r ../qemu-0/hw/3dfx ../qemu-1/hw/mesa ./hw/
patch -p0 -i ../00-qemu92x-mesa-glide.patch
bash ../scripts/sign_commit
mkdir ../build && cd ../build
../qemu-9.2.2/configure --target-list=i386-softmmu,x86_64-softmmu --enable-sdl && make -j$(nproc)
```

## Running QEMU & Guest Setup
See [`docs/usage.md`](docs/usage.md) for full instructions on:
- Launching QEMU with hardware pass-through (`-display sdl` and `-M pc`).
- Installing drivers and Glide acceleration via `freeaddons.iso`.
- Configuring Direct3D 8/9, Glide, and OpenGL games.

## Building FreeAddons ISO
To build the all-in-one guest additions ISO (`freeaddons.iso`):
```bash
./freeaddons/scripts/assemble-iso.sh
```

## Building Guest Wrappers (Optional)
**Requirements:**
 - `base-devel` (make, sed, xxd etc.)
 - `gendef, shasum`
 - `mingw32` cross toolchain (`binutils, gcc, windres, dlltool`) for WIN32 DLL wrappers
 - `Open-Watcom-1.9/v2.0` or `Watcom C/C++ 11.0` for DOS32 OVL wrapper
 - `{i586,i686}-pc-msdosdjgpp` cross toolchain (`binutils, gcc, dxe3gen`) for DJGPP DXE wrappers
<br>

```bash
cd wrappers/3dfx
mkdir build && cd build
bash ../../../scripts/conf_wrapper
make

cd ../../mesa
mkdir build && cd build
bash ../../../scripts/conf_wrapper
make
```
 
## DirectDraw & Direct3D (WineD3D) Acceleration
Universal WineD3D libraries provide hardware-accelerated DirectDraw, Direct3D 8, and Direct3D 9 for Windows 95, 98, ME, 2000, and XP guests inside QEMU.
- **100% Free and Open Source (LGPL v2.1)**: Built from clean Wine sources with built-in D3DKMT texture emulation and single-threaded passthrough hooks.
- **Pre-packaged in Freeaddons**: Mount `freeaddons.iso` as a CD-ROM in QEMU and run:
  ```bat
  freeaddons-get install 6.0.4 d3d9
  ```
- **Source code & build instructions**: Bundled in [`wined3d-windows/`](wined3d-windows/), originally created by [@startergo](https://github.com/startergo/wined3d-windows).

## License & Credits
- **QEMU**: GNU General Public License (GPL)
- **Wine / WineD3D**: GNU Lesser General Public License (LGPL v2.1)
- **qemu-3dfx**: OpenGLide, Glide, and MESA GL pass-through for QEMU guests by [@kjliew](https://github.com/kjliew/qemu-3dfx)
- **wined3d-windows**: Standalone build system, compatibility shims, and passthrough hooks by [@startergo](https://github.com/startergo/wined3d-windows)
