#!/bin/sh
# build-all.sh - one command full stack build for libre-qemu-3dfx.
#
# Chains: portable QEMU, guest wrappers, freeaddons.iso.
# WineD3D sets are optional: if wined3d-windows/output/ is empty the ISO
# step warns and omits Direct3D sets instead of failing.
#
# Usage:
#   sh scripts/build-all.sh [--host=arch|debian|windows] [--qemu-ver=9.2.2] [--jobs=N] [--skip-iso]
#
# The script first runs a preflight check. On missing tools it prints the
# exact install line for your distro and stops, instead of dying halfway
# through configure with a cryptic Python traceback.
set -e
HOST_KIND="arch"
QEMU_VER="9.2.2"
JOBS=$(nproc 2>/dev/null || echo 4)
SKIP_ISO=0

for arg in "$@"; do
    case "$arg" in
        --host=*) HOST_KIND="${arg#--host=}" ;;
        --qemu-ver=*) QEMU_VER="${arg#--qemu-ver=}" ;;
        --jobs=*) JOBS="${arg#--jobs=}" ;;
        --skip-iso) SKIP_ISO=1 ;;
        --help|-h)
            echo "Usage: $0 [--host=arch|debian|windows] [--qemu-ver=9.2.2] [--jobs=N] [--skip-iso]"
            exit 0
            ;;
        *) echo "Unknown arg: $arg" >&2; exit 1 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Preflight: every tool the chain needs, checked up front.
NEED_QEMU="gcc meson ninja make pkg-config rsync patch wget git objdump"
NEED_WRAP="i686-w64-mingw32-gcc gendef shasum xxd"
NEED_ISO="xorriso 7z curl i686-w64-mingw32-objdump"
MISSING=""
for t in $NEED_QEMU $NEED_WRAP $NEED_ISO; do
    command -v "$t" > /dev/null 2>&1 || MISSING="$MISSING $t"
done
if ! python3 -c "import distlib" 2>/dev/null; then
    MISSING="$MISSING python-distlib"
fi
if [ -n "$MISSING" ]; then
    echo "ERROR: missing build tools:$MISSING"
    echo ""
    if [ -n "$MSYSTEM" ]; then
        echo "Install on MSYS2 (mingw64 shell):"
        echo "  pacman -S base-devel mingw-w64-x86_64-toolchain ninja meson mingw-w64-x86_64-glib2 mingw-w64-x86_64-pixman mingw-w64-x86_64-SDL2 mingw-w64-i686-toolchain wget rsync p7zip libisoburn python-distlib"
    elif [ -f /etc/arch-release ]; then
        echo "Install on Arch:"
        echo "  sudo pacman -S --needed git base-devel ninja meson glib2 pixman sdl2 wget rsync p7zip libisoburn mingw-w64-gcc gendef python-distlib"
        echo "Without sudo, the Python module alone can be installed with:"
        echo "  pip install --user --break-system-packages distlib"
    elif [ -f /etc/debian_version ]; then
        echo "Install on Debian/Ubuntu:"
        echo "  sudo apt install git build-essential ninja-build meson libglib2.0-dev libpixman-1-dev libsdl2-dev pkg-config python3-venv python3-distlib wget rsync p7zip-full xorriso mingw-w64 gendef"
    else
        echo "Install the missing tools with your package manager, then rerun."
    fi
    exit 1
fi
echo "Preflight OK."

echo "=== [1/3] Portable QEMU ($HOST_KIND, QEMU $QEMU_VER) ==="
sh "$ROOT/scripts/build-qemu-portable.sh" --host="$HOST_KIND" --qemu-ver="$QEMU_VER" --jobs="$JOBS"

if [ "$SKIP_ISO" = "1" ]; then
    echo "Skipping ISO step (--skip-iso)."
    exit 0
fi

echo "=== [2/3] Guest wrappers ==="
echo "Wrapper builds run inside the ISO step when outputs are missing."

echo "=== [3/3] freeaddons.iso ==="
sh "$ROOT/freeaddons/scripts/assemble-iso.sh"

echo ""
echo "=== Validating outputs ==="
sh "$ROOT/scripts/smoke-test.sh"
