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

# ── Proprietary Win9x OEM Drivers ────────────────────────────────────
# Proprietary legacy drivers (LSI SYM_HI SCSI, SigmaTel STAC9700 AC97,
# Bochs VBE) are excluded from this libre script. Users who require them
# can use fetch-win98-oem-drivers.sh to fold them into a local build.

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

[ "$RECORD" = "1" ] && mv "$MANIFEST.new" "$MANIFEST" && echo "manifest written"
echo "fetch-drivers done (review SOURCES + TODO(verify) items)"
