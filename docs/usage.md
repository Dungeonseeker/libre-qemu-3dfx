# Usage Guide

This guide covers running QEMU with 3dfx Glide and Mesa OpenGL hardware pass-through, and installing guest acceleration using `freeaddons.iso`.

## 1. Running QEMU

### Mandatory Flags
- **`-display sdl`**: Required. Mesa OpenGL and Glide blit directly to the host SDL2 window. GTK, Cocoa, and VNC will not work.
- **`-M pc`**: Required. Hardware pass-through devices hook into the standard PC machine type.
- **`-accel kvm`** (Linux), **`-accel whpx`** (Windows), or **`-accel hvf`** (macOS).

### Example Command (Linux / KVM)
```bash
./qemu-system-i386 \
  -M pc,accel=kvm -cpu host -m 1024 \
  -display sdl \
  -drive file=winxp.qcow2,format=qcow2,if=ide \
  -cdrom freeaddons.iso \
  -audiodev sdl,id=snd0 -device ac97,audiodev=snd0 \
  -netdev user,id=net0 -device rtl8139,netdev=net0 \
  -boot c
```

### Windows (WHPX)
```cmd
qemu-system-i386.exe ^
  -M pc,accel=whpx -cpu host -m 1024 ^
  -display sdl ^
  -drive file=winxp.qcow2,format=qcow2,if=ide ^
  -cdrom freeaddons.iso ^
  -audiodev sdl,id=snd0 -device ac97,audiodev=snd0 ^
  -boot c
```

---

## 2. Guest Installation (freeaddons.iso)

Attach `freeaddons.iso` to your virtual machine's CD-ROM drive.

### Windows 2000 / XP
1. Open the CD-ROM drive (`D:\`).
2. Run `freeaddons.bat` as Administrator.
   - This installs the `fxptl.sys` kernel driver (MAPMEM service) and system-wide Glide DLLs.
3. Reboot the VM when prompted.

### Windows 95 / 98 / ME
1. Open `D:\` and run `freeaddons.bat`.
   - This installs `FXMEMMAP.VXD` and system Glide DLLs.
2. Reboot the VM.

---

## 3. Configuring Games

### Direct3D 8 and Direct3D 9
To enable hardware acceleration for a Direct3D game:
1. Open a command prompt or MSYS shell from `freeaddons.iso`.
2. Navigate to your installed game directory (where the game `.exe` lives).
3. Run:
   ```cmd
   D:\win32\wine\freeaddons-get install 6.0.4 d3d9
   ```
   *(Replace `d3d9` with `d3d8` for DirectX 8 games).*
4. This drops the hardware-accelerated WineD3D wrapper DLLs directly into the game folder without overwriting Windows system files.

### 3dfx Glide Games
Glide 2.x and 3.x games work automatically once `freeaddons.bat` has been run.
- For DOS Glide games: ensure `glide2x.ovl` is in your DOS game folder or `C:\WINDOWS`.

### Mesa OpenGL Games
For OpenGL games (such as Quake III Arena):
- Copy `D:\win32\wrapgl\opengl32.dll` directly into the game installation folder.
