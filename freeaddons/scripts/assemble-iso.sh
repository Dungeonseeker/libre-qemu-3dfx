#!/bin/sh
# assemble-iso.sh — stage the Freeaddons tree and emit freeaddons.iso.
#
# Usage: assemble-iso.sh [--skip-fetch]
#   Without --skip-fetch, fetch-msys.sh and fetch-drivers.sh run first.
# Sources (all paths relative to the qemu-3dfx workspace root):
#   wrappers/3dfx/build, wrappers/mesa/build, wined3d-windows/output,
#   freeaddons/src/ddthru, qemu-xtra openglide, fetch staging.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STAGE="$ROOT/freeaddons/iso-staging"
OUT="$ROOT/freeaddons/freeaddons.iso"
FETCH=1
[ "$1" = "--skip-fetch" ] && FETCH=0

rm -rf "$STAGE"
mkdir -p "$STAGE/win32" "$STAGE/drivers"

# Fetched third-party trees live outside staging (they survive the wipe).
FETCHDIR="$ROOT/freeaddons/stage-fetch"
if [ -d "$FETCHDIR" ]; then
    cp -r "$FETCHDIR"/. "$STAGE"/
fi

if [ "$FETCH" = "1" ]; then
    sh "$ROOT/freeaddons/scripts/fetch-msys.sh" "$FETCHDIR/win32"
    sh "$ROOT/freeaddons/scripts/fetch-drivers.sh" "$FETCHDIR/win32"
    cp -r "$FETCHDIR"/. "$STAGE"/
fi

# ── root launchers ──────────────────────────────────────────────────
cp "$ROOT/freeaddons/src/autorun.inf" "$ROOT/freeaddons/src/freeaddons.bat" \
   "$ROOT/freeaddons/src/freeaddbsh.bat" "$ROOT/freeaddons/src/freeaddons.sh" "$STAGE/"
[ -f "$ROOT/freeaddons/src/qemu.ico" ] && cp "$ROOT/freeaddons/src/qemu.ico" "$STAGE/"

# ── wrapfx (glide guest wrappers, built in-tree) ─────────────────────
mkdir -p "$STAGE/win32/wrapfx"
for f in fxmemmap.vxd fxptl.sys glide.dll glide2x.dll glide3x.dll \
         glide2x.ovl glide2x.dxe glide3x.dxe instdrv.exe \
         libfxgl2.a libfxgl3.a libglide2x.dll.a libglide3x.dll.a; do
    [ -f "$ROOT/wrappers/3dfx/build/$f" ] && \
        cp "$ROOT/wrappers/3dfx/build/$f" "$STAGE/win32/wrapfx/"
done

# ── wrapgl (mesa guest wrapper + tools) ─────────────────────────────
mkdir -p "$STAGE/win32/wrapgl"
[ -f "$ROOT/wrappers/mesa/build/opengl32.dll" ] && \
    cp "$ROOT/wrappers/mesa/build/opengl32.dll" "$STAGE/win32/wrapgl/"
for t in wglinfo.exe wglgears.exe bxvmodes.exe; do
    [ -f "$ROOT/wrappers/mesa/build/$t" ] && \
        cp "$ROOT/wrappers/mesa/build/$t" "$STAGE/win32/wrapgl/"
done

# ── wine sets (universal, donor-identical per-version layout) ───────
mkdir -p "$STAGE/win32/wine"
for src in "$ROOT/wined3d-windows/output/"*; do
    [ -d "$src" ] || continue
    ver=`basename $src`
    case "$ver" in *-nt) continue ;; esac
    mkdir -p "$STAGE/win32/wine/$ver"
    for f in d3d8.dll d3d9.dll ddraw.dll wined3d.dll msvcrt.dll build-timestamp; do
        [ -f "$src/$f" ] && cp "$src/$f" "$STAGE/win32/wine/$ver/"
    done
done
cp "$ROOT/freeaddons/src/freeaddons-get" "$STAGE/win32/wine/"
chmod +x "$STAGE/win32/wine/freeaddons-get"

# ── ddthru trampolines (one build, three OS dirs like donor) ─────────
if [ ! -f "$ROOT/freeaddons/src/ddthru/ddraw.dll" ] || [ ! -f "$ROOT/freeaddons/src/ddthru/dsound.dll" ]; then
    make -C "$ROOT/freeaddons/src/ddthru" check
fi
for os in 2K 98ME XP; do
    mkdir -p "$STAGE/win32/wine/ddthru/$os"
    cp "$ROOT/freeaddons/src/ddthru/ddraw.dll" \
       "$ROOT/freeaddons/src/ddthru/dsound.dll" \
       "$STAGE/win32/wine/ddthru/$os/"
done

# ── openglide host-side wrappers ────────────────────────────────────
if [ -d "$ROOT/myqemu/qemu-xtra/build/.libs" ]; then
    mkdir -p "$STAGE/win32/openglide"
    for f in "$ROOT"/myqemu/qemu-xtra/build/.libs/glide*.dll; do
        [ -f "$f" ] && cp "$f" "$STAGE/win32/openglide/"
    done
fi

# ── SOURCES.txt provenance ──────────────────────────────────────────
{
    echo "Freeaddons — provenance log (reproducible inputs)"
    echo "Built: `date -u '+%Y-%m-%d %H:%M:%S UTC'`"
    echo ""
    echo "== in-tree builds =="
    echo "win32/wrapfx <- qemu-3dfx wrappers/3dfx (open source, this repo)"
    echo "win32/wrapgl <- qemu-3dfx wrappers/mesa (open source, this repo)"
    echo "win32/wine/<ver> <- wined3d-windows output/<ver>-nt (open source, this repo)"
    echo "win32/wine/ddthru <- freeaddons/src/ddthru (open source, this repo)"
    echo "win32/openglide <- qemu-xtra openglide (LGPL, kjliew/qemu-xtra)"
    echo ""
    echo "== fetched third-party =="
    cat "$STAGE"/win32/SOURCES.*.txt 2>/dev/null || echo "(fetch scripts skipped)"
} > "$STAGE/SOURCES.txt"

# ── self-checks ─────────────────────────────────────────────────────
echo "=== self-checks ==="
FAIL=0
for dll in "$STAGE"/win32/wine/*/*.dll "$STAGE"/win32/wrapfx/*.dll \
           "$STAGE"/win32/wrapgl/*.dll "$STAGE"/win32/wine/ddthru/*/*.dll; do
    [ -f "$dll" ] || continue
    i686-w64-mingw32-objdump -p "$dll" > /dev/null 2>&1 || \
        { echo "BROKEN PE: $dll"; FAIL=1; }
    if i686-w64-mingw32-objdump -p "$dll" 2>/dev/null | grep -qi "ucrtbase\|api-ms-win"; then
        echo "UCRT IMPORT: $dll"; FAIL=1
    fi
done
[ "$FAIL" = "0" ] && echo "PE checks OK" || exit 1

# ── ISO (Joliet for Win9x-era readability + Rock Ridge) ──────────────
xorriso -as mkisofs -J -R -l -V FREEADDONS -o "$OUT" "$STAGE" 2>&1 | tail -n 3
ls -lh "$OUT"
echo "freeaddons.iso ready"
