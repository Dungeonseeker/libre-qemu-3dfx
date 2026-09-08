#!/bin/sh
# fetch-win98-oem-drivers.sh — Optional helper for Windows 95/98/ME guests
# requiring vintage OEM drivers (LSI 53C895A SCSI, SigmaTel STAC9700 AC'97,
# Bochs VBE).
#
# NOTE: These are proprietary OEM drivers excluded from official libre releases
# to keep libre-qemu-3dfx 100% free of proprietary binary blobs.
#
# Usage:
#   fetch-win98-oem-drivers.sh [--from-iso <path-to-donor-iso>] [destination-dir]
#
# Default destination: freeaddons/stage-fetch/drivers
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/freeaddons/stage-fetch"
DONOR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --from-iso)
            DONOR="$2"
            shift 2
            ;;
        *)
            DEST="$1"
            shift
            ;;
    esac
done

# If no donor specified, check for private/vmaddons.iso
if [ -z "$DONOR" ] && [ -f "$ROOT/private/vmaddons.iso" ]; then
    DONOR="$ROOT/private/vmaddons.iso"
fi

mkdir -p "$DEST"

if [ -n "$DONOR" ] && [ -f "$DONOR" ]; then
    echo "Extracting Win9x OEM drivers from: $DONOR"
    7z x -y -o"$DEST" "$DONOR" \
        drivers/LSI drivers/STAC97 drivers/BOXV drivers/WIN98 >/dev/null 2>&1 || \
    bsdtar -xf "$DONOR" -C "$DEST" \
        drivers/LSI drivers/STAC97 drivers/BOXV drivers/WIN98
    echo "Win9x OEM drivers staged to: $DEST"
    echo "Run assemble-iso.sh to bundle them into your local freeaddons.iso"
    exit 0
fi

cat << 'INSTRUCTIONS'
=== Windows 95/98/ME OEM Drivers (Optional) ===
The base FreeAddons ISO is 100% libre and includes Direct3D, Glide, and Mesa
acceleration out of the box.

If you are running Windows 98 with specific legacy hardware (-device lsi53c895a
or -device AC97), you can obtain the vintage OEM drivers from driver archives:

1. LSI 53C895A SCSI (SYM_HI.MPD, SYM_HI.INF)
2. SigmaTel STAC9700 AC'97 (stac97.sys, stac97.inf, stac97.cat, stac97.cpl)
3. Bochs VBE (BOXV9X.INF, BOXVMINI.DRV, boxvmini.vxd)

Place them into:
  freeaddons/stage-fetch/drivers/LSI/WIN9XHI/
  freeaddons/stage-fetch/drivers/STAC97/
  freeaddons/stage-fetch/drivers/BOXV/9X/

Then re-run assemble-iso.sh to build your personalized ISO with OEM drivers.
Or pass: --from-iso <path-to-donor-or-driver-cd.iso>
INSTRUCTIONS
