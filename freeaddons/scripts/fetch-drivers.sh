#!/bin/sh
# fetch-drivers.sh — reproducibly stage third-party driver/audio trees
# for the Freeaddons ISO. Everything lands with a SOURCES.txt entry
# (upstream URL, version, license); downloads are hash-pinned via
# MANIFEST.drivers.sha256 (use --record once, review, commit).
#
# Usage: fetch-drivers.sh <staging-win32-dir> [--record]
set -e
DESTDIR="$1"
RECORD=0
[ "$2" = "--record" ] && RECORD=1
[ -z "$DESTDIR" ] && { echo "Usage: $0 <staging-win32-dir> [--record]"; exit 1; }

CACHE="$(cd "$(dirname "$0")" && pwd)/.pkgcache-drivers"
MANIFEST="$(cd "$(dirname "$0")" && pwd)/MANIFEST.drivers.sha256"
SRCLOG="$DESTDIR/SOURCES.drivers.txt"
mkdir -p "$CACHE" "$DESTDIR"
[ "$RECORD" = "1" ] && rm -f "$MANIFEST.new"

get() { # get <url> <cache-name>
    if [ ! -f "$CACHE/$2" ]; then
        echo "GET $1"
        curl -sL --retry 3 -o "$CACHE/$2" "$1"
    fi
    if [ "$RECORD" = "1" ]; then
        sha256sum "$CACHE/$2" | sed "s|$CACHE/||" >> "$MANIFEST.new"
    elif [ -f "$MANIFEST" ]; then
        grep -F "$2" "$MANIFEST" > "$CACHE/.chk" || true
        (cd "$CACHE" && sha256sum -c --status .chk) \
            || { echo "HASH MISMATCH: $2"; exit 1; }
    else
        echo "WARNING: no $MANIFEST — run with --record once, review, commit"
    fi
}

note() { echo "$1" >> "$SRCLOG"; }
: > "$SRCLOG"

# ── VirtualBox Guest Additions 7.0.10 (VGA adapter driver) ──────────
# Donor VBoxVideo.inf: 07/12/2023, 7.0.10.8379 r158379. License: GPLv3
# (Guest Additions); redistributable with source reference below.
get https://download.virtualbox.org/virtualbox/7.0.10/VBoxGuestAdditions_7.0.10.iso \
    VBoxGuestAdditions_7.0.10.iso
note "drivers/box/vbox <- VBoxGuestAdditions_7.0.10.iso (GPLv3, virtualbox.org)"
mkdir -p "$DESTDIR/drivers/box/vbox"
7z x -y -o"$DESTDIR/drivers/box/vbox" "$CACHE/VBoxGuestAdditions_7.0.10.iso" \
    VBoxWindowsAdditions-x86.exe > /dev/null 2>&1 || \
    bsdtar -xf "$CACHE/VBoxGuestAdditions_7.0.10.iso" \
        -C "$DESTDIR/drivers/box/vbox" VBoxWindowsAdditions-x86.exe

# ── VMDisp9x Display Driver for Win9x (MIT, JHRobotics/vmdisp9x) ────
# Replaces proprietary Bochs VBE display driver. Includes dedicated
# qemumini.drv and qemumini.vxd for QEMU Standard VGA (-vga std).
VMDISP_URL=https://github.com/JHRobotics/vmdisp9x/releases/download/v1.2025.0.119/vmdisp9x-1.2025.0.119b-driver-2d.zip
get $VMDISP_URL vmdisp9x-1.2025.0.119b-driver-2d.zip
note "drivers/display/vmdisp9x <- VMDisp9x v1.2025.0.119b (MIT, github.com/JHRobotics/vmdisp9x)"
mkdir -p "$DESTDIR/drivers/display/vmdisp9x"
7z x -y -o"$DESTDIR/drivers/display/vmdisp9x" "$CACHE/vmdisp9x-1.2025.0.119b-driver-2d.zip" > /dev/null

# ── VirtIO guest floppy (virtio-win 0.1.173, last era with XP + .vfd) ─
VIRTIO_BASE=https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.173-9
get $VIRTIO_BASE/virtio-win_x86.vfd virtio-win_x86.vfd
get $VIRTIO_BASE/virtio-win_amd64.vfd virtio-win_amd64.vfd
note "drivers/FD <- virtio-win 0.1.173-9 vfds (Fedora/RHEL guest drivers, GPLv2)"
mkdir -p "$DESTDIR/drivers/FD"
cp "$CACHE/virtio-win_x86.vfd" "$DESTDIR/drivers/FD/"
cp "$CACHE/virtio-win_amd64.vfd" "$DESTDIR/drivers/FD/"

# ── DSOAL + OpenAL Soft (EAX-era audio) ──────────────────────────────
get https://github.com/kcat/dsoal/archive/refs/heads/master.tar.gz dsoal-master.tar.gz
note "win32/dsoal <- kcat/dsoal master (LGPL, github.com/kcat/dsoal)"
get https://openal-soft.org/openal-binaries/openal-soft-1.23.1-bin.zip \
    openal-soft-1.23.1-bin.zip
note "win32/dsoal <- OpenAL Soft 1.23.1 binaries (LGPL, openal-soft.org)"
mkdir -p "$DESTDIR/dsoal"

# Extract OpenAL Soft 32-bit runtime and info tool
7z e -y -o"$DESTDIR/dsoal" "$CACHE/openal-soft-1.23.1-bin.zip" \
    openal-soft-1.23.1-bin/bin/Win32/soft_oal.dll \
    openal-soft-1.23.1-bin/openal-info32.exe > /dev/null
mv -f "$DESTDIR/dsoal/soft_oal.dll" "$DESTDIR/dsoal/libopenal-1.dll"
mv -f "$DESTDIR/dsoal/openal-info32.exe" "$DESTDIR/dsoal/openal-info.exe"

# Build DSOAL DirectSound wrapper (dsound.dll) from source if not cached
if [ ! -f "$CACHE/dsoal-dsound.dll" ]; then
    echo "Building DSOAL dsound.dll from source..."
    DSOAL_TMP=$(mktemp -d)
    tar -xf "$CACHE/dsoal-master.tar.gz" -C "$DSOAL_TMP"
    cmake -S "$DSOAL_TMP/dsoal-master" -B "$DSOAL_TMP/dsoal-master/build" \
        -DCMAKE_SYSTEM_NAME=Windows \
        -DCMAKE_CXX_COMPILER=i686-w64-mingw32-g++ \
        -DCMAKE_CXX_FLAGS="-D_UCRT -static-libgcc -static-libstdc++" \
        -DCMAKE_SHARED_LINKER_FLAGS="-static-libgcc -static-libstdc++" > /dev/null
    make -C "$DSOAL_TMP/dsoal-master/build" -j$(nproc) dsound > /dev/null
    i686-w64-mingw32-strip --strip-unneeded "$DSOAL_TMP/dsoal-master/build/dsound.dll"
    cp "$DSOAL_TMP/dsoal-master/build/dsound.dll" "$CACHE/dsoal-dsound.dll"
    rm -rf "$DSOAL_TMP"
fi
cp "$CACHE/dsoal-dsound.dll" "$DESTDIR/dsoal/dsound.dll"

[ "$RECORD" = "1" ] && mv "$MANIFEST.new" "$MANIFEST" && echo "manifest written"
echo "fetch-drivers done (review SOURCES + TODO(verify) items)"

