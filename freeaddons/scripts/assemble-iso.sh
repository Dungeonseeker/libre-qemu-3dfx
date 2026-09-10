#!/bin/sh
# assemble-iso.sh - stage the Freeaddons tree and emit freeaddons.iso.
#
# Usage: assemble-iso.sh [--skip-fetch]
#   Without --skip-fetch, fetch-msys.sh and fetch-drivers.sh run first.
#
# Automatically builds in-tree guest wrappers (wrappers/3dfx, wrappers/mesa,
# freeaddons/src/ddthru) if not already compiled.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STAGE="$ROOT/freeaddons/iso-staging"
OUT="$ROOT/freeaddons/freeaddons.iso"
FETCH=1
[ "$1" = "--skip-fetch" ] && FETCH=0

echo "=== FreeAddons ISO Build System ==="

# ── 1. Host Build Tool Prerequisites ────────────────────────────────
echo "[1/6] Checking host build dependencies..."
MISSING=""
for tool in xorriso 7z curl i686-w64-mingw32-gcc i686-w64-mingw32-objdump; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        MISSING="$MISSING $tool"
    fi
done

if [ -n "$MISSING" ]; then
    echo "ERROR: Missing required host tools:$MISSING"
    echo "Please install them using your package manager (e.g., pacman -S mingw-w64-gcc p7zip curl libisoburn)"
    exit 1
fi
echo "      Host dependencies OK."

# ── 2. Build in-tree wrappers if needed ──────────────────────────────
echo "[2/6] Verifying in-tree guest wrappers..."

# 3dfx Glide wrapper
if [ ! -f "$ROOT/wrappers/3dfx/build/glide2x.dll" ]; then
    echo "      Building wrappers/3dfx..."
    mkdir -p "$ROOT/wrappers/3dfx/build"
    [ -f "$ROOT/wrappers/3dfx/build/Makefile" ] || ln -sf ../src/Makefile.in "$ROOT/wrappers/3dfx/build/Makefile"
    make -C "$ROOT/wrappers/3dfx/build"
fi

# Mesa OpenGL wrapper
if [ ! -f "$ROOT/wrappers/mesa/build/opengl32.dll" ]; then
    echo "      Building wrappers/mesa..."
    mkdir -p "$ROOT/wrappers/mesa/build"
    [ -f "$ROOT/wrappers/mesa/build/Makefile" ] || ln -sf ../src/Makefile.in "$ROOT/wrappers/mesa/build/Makefile"
    make -C "$ROOT/wrappers/mesa/build"
fi

# ddthru trampolines
if [ ! -f "$ROOT/freeaddons/src/ddthru/ddraw.dll" ]; then
    echo "      Building ddthru trampolines..."
    make -C "$ROOT/freeaddons/src/ddthru" check
fi
echo "      Guest wrappers OK."

# ── 3. Fetch external drivers & MSYS runtime ────────────────────────
echo "[3/6] Fetching/staging external runtime components..."
FETCHDIR="$ROOT/freeaddons/stage-fetch"
if [ "$FETCH" = "1" ]; then
    sh "$ROOT/freeaddons/scripts/fetch-msys.sh" "$FETCHDIR/win32"
    sh "$ROOT/freeaddons/scripts/fetch-drivers.sh" "$FETCHDIR/win32"
fi

# Deterministic timestamp for bit-for-bit reproducible ISO builds
if [ -z "$SOURCE_DATE_EPOCH" ]; then
    SOURCE_DATE_EPOCH=$(git -C "$ROOT" log -1 --pretty=%ct 2>/dev/null || echo 1700000000)
    export SOURCE_DATE_EPOCH
fi

# ── 4. Stage ISO payload ────────────────────────────────────────────
echo "[4/6] Staging ISO filesystem..."
rm -rf "$STAGE"
mkdir -p "$STAGE/win32" "$STAGE/drivers"

if [ -d "$FETCHDIR" ]; then
    cp -r "$FETCHDIR"/. "$STAGE"/
fi

# Root launchers
cp "$ROOT/freeaddons/src/autorun.inf" "$ROOT/freeaddons/src/freeaddons.bat" \
   "$ROOT/freeaddons/src/freeaddbsh.bat" "$ROOT/freeaddons/src/freeaddons.sh" "$STAGE/"
[ -f "$ROOT/freeaddons/src/qemu.ico" ] && cp "$ROOT/freeaddons/src/qemu.ico" "$STAGE/"

# wrapfx (glide guest wrappers)
mkdir -p "$STAGE/win32/wrapfx"
for f in fxmemmap.vxd fxptl.sys glide.dll glide2x.dll glide3x.dll \
         glide2x.ovl glide2x.dxe glide3x.dxe instdrv.exe \
         libfxgl2.a libfxgl3.a libglide2x.dll.a libglide3x.dll.a; do
    [ -f "$ROOT/wrappers/3dfx/build/$f" ] && \
        cp "$ROOT/wrappers/3dfx/build/$f" "$STAGE/win32/wrapfx/"
done

# wrapgl (mesa guest wrapper + tools)
mkdir -p "$STAGE/win32/wrapgl"
[ -f "$ROOT/wrappers/mesa/build/opengl32.dll" ] && \
    cp "$ROOT/wrappers/mesa/build/opengl32.dll" "$STAGE/win32/wrapgl/"
for t in wglinfo.exe wglgears.exe bxvmodes.exe; do
    [ -f "$ROOT/wrappers/mesa/build/$t" ] && \
        cp "$ROOT/wrappers/mesa/build/$t" "$STAGE/win32/wrapgl/"
done

# wine sets
mkdir -p "$STAGE/win32/wine"
WINE_COUNT=0
for src in "$ROOT/wined3d-windows/output/"*; do
    [ -d "$src" ] || continue
    ver=`basename $src`
    case "$ver" in *-nt) continue ;; esac
    mkdir -p "$STAGE/win32/wine/$ver"
    for f in d3d8.dll d3d9.dll ddraw.dll wined3d.dll msvcrt.dll build-timestamp; do
        [ -f "$src/$f" ] && cp "$src/$f" "$STAGE/win32/wine/$ver/"
    done
    WINE_COUNT=$((WINE_COUNT + 1))
done

if [ "$WINE_COUNT" -eq 0 ]; then
    echo "WARNING: No WineD3D builds found in wined3d-windows/output/."
    echo "         Direct3D acceleration sets will be omitted from the ISO."
    echo "         To build WineD3D, refer to wined3d-windows/README.md."
fi

cp "$ROOT/freeaddons/src/freeaddons-get" "$STAGE/win32/wine/"
chmod +x "$STAGE/win32/wine/freeaddons-get"

# ddthru trampolines
for os in 2K 98ME XP; do
    mkdir -p "$STAGE/win32/wine/ddthru/$os"
    cp "$ROOT/freeaddons/src/ddthru/ddraw.dll" \
       "$ROOT/freeaddons/src/ddthru/dsound.dll" \
       "$STAGE/win32/wine/ddthru/$os/"
done

# openglide host-side wrappers
if [ -d "$ROOT/myqemu/qemu-xtra/build/.libs" ]; then
    mkdir -p "$STAGE/win32/openglide"
    for f in "$ROOT"/myqemu/qemu-xtra/build/.libs/glide*.dll; do
        [ -f "$f" ] && cp "$f" "$STAGE/win32/openglide/"
    done
fi

# SOURCES.txt provenance
{
    echo "Freeaddons - provenance log (reproducible inputs)"
    echo "Built: $(date -u -d "@$SOURCE_DATE_EPOCH" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo ""
    echo "== in-tree builds =="
    echo "win32/wrapfx <- qemu-3dfx wrappers/3dfx (free software, this repo)"
    echo "win32/wrapgl <- qemu-3dfx wrappers/mesa (free software, this repo)"
    echo "win32/wine/<ver> <- wined3d-windows output/<ver> (free software, this repo)"
    echo "win32/wine/ddthru <- freeaddons/src/ddthru (free software, this repo)"
    echo "win32/openglide <- qemu-xtra openglide (LGPL, kjliew/qemu-xtra)"
    echo ""
    echo "== fetched third-party =="
    cat "$STAGE"/win32/SOURCES.*.txt 2>/dev/null || echo "(fetch scripts skipped)"
} > "$STAGE/SOURCES.txt"

# ── 5. Detailed Self-Checks ─────────────────────────────────────────
echo "[5/6] Running PE closure & compatibility self-checks..."
FAIL=0
for dll in "$STAGE"/win32/wine/*/*.dll "$STAGE"/win32/wrapfx/*.dll \
           "$STAGE"/win32/wrapgl/*.dll "$STAGE"/win32/wine/ddthru/*/*.dll \
           "$STAGE"/win32/dsoal/*.dll; do
    [ -f "$dll" ] || continue
    if ! i686-w64-mingw32-objdump -p "$dll" > /dev/null 2>&1; then
        echo "ERROR: Corrupted or invalid PE image: $dll"
        FAIL=1
    fi
    UCRT_HITS=$(i686-w64-mingw32-objdump -p "$dll" 2>/dev/null | grep -i "ucrtbase\|api-ms-win" || true)
    if [ -n "$UCRT_HITS" ]; then
        echo "ERROR: UCRT import detected in $dll:"
        echo "$UCRT_HITS" | sed 's/^/         /'
        echo "       (Win9x/XP require msvcrt.dll; ensure -mcrtdll=msvcrt was passed during compilation)"
        FAIL=1
    fi
done

if [ "$FAIL" != "0" ]; then
    echo "FATAL: Self-checks failed. Aborting ISO generation."
    exit 1
fi
echo "      All PE binaries passed Win9x/XP compatibility check."

# ── 6. Normalization and ISO Generation ──────────────────────────────
echo "[6/6] Normalizing line endings and building freeaddons.iso..."

# Ensure DOS CRLF line endings on Windows text/batch files
find "$STAGE" -type f \( -name "*.txt" -o -name "*.bat" -o -name "*.inf" -o -name "*.ini" -o -name "*.reg" \) | while read -r f; do
    sed -i 's/\r$//; s/$/\r/' "$f"
done

# Normalize mtime for bit-for-bit reproducible ISO
find "$STAGE" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

# Generate ISO
xorriso -as mkisofs -J -R -l -V FREEADDONS -o "$OUT" "$STAGE" 2>&1 | tail -n 3

echo ""
ls -lh "$OUT"
echo "=== Success: freeaddons.iso ready ==="
