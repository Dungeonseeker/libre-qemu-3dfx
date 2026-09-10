#!/bin/sh
# build-qemu-portable.sh - reproducible portable QEMU build for libre-qemu-3dfx.
#
# Baseline: x86-64 v1, no native, no v2/v3/v4, no AVX leak.
# Host order: Arch first, then Debian/Ubuntu, then Windows (MSYS2 mingw64).
# macOS (Intel plus Apple Silicon) is pre-1.0 post beta, handled last.
#
# Usage:
#   sh scripts/build-qemu-portable.sh [--host=arch|debian|windows] [--qemu-ver=9.2.2] [--jobs=N]
#   The script exports pinned CFLAGS/CXXFLAGS, configures, builds,
#   verifies no AVX/AVX2/AVX512 instructions leaked in, and stages a
#   tarball plus sha256 plus build log (same provenance style as
#   freeaddons MANIFEST plus SOURCES.txt).
#
# No GitHub runners required. Run locally and attach outputs to a release.
set -e
HOST_KIND="arch"
QEMU_VER="9.2.2"
JOBS=$(nproc 2>/dev/null || echo 4)

for arg in "$@"; do
    case "$arg" in
        --host=*) HOST_KIND="${arg#--host=}" ;;
        --qemu-ver=*) QEMU_VER="${arg#--qemu-ver=}" ;;
        --jobs=*) JOBS="${arg#--jobs=}" ;;
        --help|-h)
            echo "Usage: $0 [--host=arch|debian|windows] [--qemu-ver=9.2.2] [--jobs=N]"
            exit 0
            ;;
        *) echo "Unknown arg: $arg" >&2; exit 1 ;;
    esac
done

case "$HOST_KIND" in
    arch|debian|windows) ;;
    *) echo "ERROR: --host must be arch, debian, or windows (macOS lands pre-1.0 post beta)" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTDIR="$ROOT/dist-qemu-portable"
LOGDIR="$OUTDIR/logs"
mkdir -p "$OUTDIR" "$LOGDIR"

# Pinned portable baseline: x86-64 v1 with generic tuning.
# Skylake through Zen 5 class CPUs all implement this. Anything newer
# (v2/v3/v4, native, AVX) would break the portable promise.
export CFLAGS="-march=x86-64 -mtune=generic -O2 -pipe -fno-plt"
export CXXFLAGS="-march=x86-64 -mtune=generic -O2 -pipe -fno-plt"

STAMP=$(date -u '+%Y%m%d')
BUILD_LOG="$LOGDIR/qemu-${QEMU_VER}-${HOST_KIND}-${STAMP}.log"
{
    echo "libre-qemu-3dfx portable QEMU build log"
    echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Host kind: $HOST_KIND"
    echo "QEMU version: $QEMU_VER"
    echo "CFLAGS: $CFLAGS"
    echo "CXXFLAGS: $CXXFLAGS"
    echo "Compiler:"
    gcc -v 2>&1 | tail -5 || true
    echo "Target defaults:"
    gcc -Q --help=target 2>/dev/null | grep -e march -e mtune || true
    echo "Repo: $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
} | tee "$BUILD_LOG"

# Fetch and prepare tree if needed.
cd "$ROOT"
if [ ! -d "qemu-${QEMU_VER}" ]; then
    echo "Fetching qemu-${QEMU_VER}.tar.xz ..." | tee -a "$BUILD_LOG"
    wget "https://download.qemu.org/qemu-${QEMU_VER}.tar.xz" 2>&1 | tee -a "$BUILD_LOG"
    tar xf "qemu-${QEMU_VER}.tar.xz" 2>&1 | tee -a "$BUILD_LOG"
fi
cd "qemu-${QEMU_VER}"
rsync -r ../qemu-0/hw/3dfx ../qemu-1/hw/mesa ./hw/ 2>&1 | tee -a "$BUILD_LOG"
# The patch step must run exactly once per fresh tree. A rerun after
# sign_commit touched nearby lines makes patch -N misdetect the vl.c
# hunk and apply it a second time (duplicate feature block), so guard
# on the marker the patch itself adds.
if grep -q "featuring qemu-3dfx@" system/vl.c 2>/dev/null; then
    echo "Patch already applied, skipping." | tee -a "$BUILD_LOG"
else
    patch -p0 -i ../00-qemu92x-mesa-glide.patch 2>&1 | tee -a "$BUILD_LOG"
fi
bash ../scripts/sign_commit 2>&1 | tee -a "$BUILD_LOG" || true

mkdir -p "../build-qemu-${QEMU_VER}-${HOST_KIND}"
cd "../build-qemu-${QEMU_VER}-${HOST_KIND}"
echo "Configuring ..." | tee -a "$BUILD_LOG"
"../qemu-${QEMU_VER}/configure" --target-list=i386-softmmu,x86_64-softmmu --enable-sdl 2>&1 | tee -a "$BUILD_LOG"
echo "Building with $JOBS jobs ..." | tee -a "$BUILD_LOG"
make -j"$JOBS" 2>&1 | tee -a "$BUILD_LOG"

# Portability self check: fail on AVX/AVX2/AVX512 vector encodings.
# Check the real top level binaries only. The build tree also holds a
# qemu-bundle staging dir of symlinks that dangle until link succeeds,
# so resolve -f and fail on anything missing.
echo "Running AVX leak check ..." | tee -a "$BUILD_LOG"
BINARIES="qemu-system-i386 qemu-system-x86_64"
FAIL=0
for bin in $BINARIES; do
    if [ ! -f "$bin" ]; then
        echo "ERROR: missing expected binary $bin" | tee -a "$BUILD_LOG"
        FAIL=1
        continue
    fi
    HITS=$(objdump -d "$bin" 2>/dev/null | grep -E "vmovaps|vmovups|vpxor|vpadd|vbroadcast|ymm[0-9]|zmm[0-9]" || true)
    if [ -z "$HITS" ]; then
        echo "OK: no AVX leak in $bin" | tee -a "$BUILD_LOG"
        continue
    fi
    # Attribute each hit to its enclosing function. Upstream QEMU ships
    # two runtime CPUID dispatched helpers (buffer_zero_avx2 in
    # util/bufferiszero.c, xbzrle_encode_buffer_avx512 in
    # migration/xbzrle.c) that never execute on hosts without AVX2 or
    # AVX512. Hits confined to those are safe. Anything else is a real
    # portability leak and fails the build.
    BAD=$(objdump -d "$bin" 2>/dev/null | awk '/^[0-9a-f]+ <.*>:$/ {sym=$2} /vmovaps|vmovups|vpxor|vpadd|vbroadcast|ymm[0-9]|zmm[0-9]/ {print sym}' | grep -v -e "<buffer_zero_avx2>:" -e "<xbzrle_encode_buffer_avx512>:" || true)
    if [ -n "$BAD" ]; then
        echo "ERROR: AVX encoding outside dispatched helpers in $bin:" | tee -a "$BUILD_LOG"
        echo "$HITS" | head -10 | tee -a "$BUILD_LOG"
        FAIL=1
    else
        echo "OK: AVX use in $bin confined to runtime dispatched helpers:" | tee -a "$BUILD_LOG"
        echo "$HITS" | head -5 | tee -a "$BUILD_LOG"
    fi
done
if [ "$FAIL" != "0" ]; then
    echo "FATAL: portability check failed. Rebuild with pinned v1 flags only." | tee -a "$BUILD_LOG"
    exit 1
fi

# Stage tarball plus checksums plus provenance.
PKG="libre-qemu-3dfx-qemu${QEMU_VER}-${HOST_KIND}-x86-64-v1-${STAMP}"
STAGE="$OUTDIR/$PKG"
rm -rf "$STAGE"
mkdir -p "$STAGE"
for bin in $BINARIES; do
    cp "$bin" "$STAGE/"
done
cp "$BUILD_LOG" "$STAGE/BUILD.log"
{
    echo "libre-qemu-3dfx portable QEMU provenance"
    echo "Package: $PKG"
    echo "QEMU: $QEMU_VER with 00-qemu92x-mesa-glide.patch"
    echo "Baseline: x86-64 v1 (-march=x86-64 -mtune=generic -O2)"
    echo "Built: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Commit: $(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
} > "$STAGE/SOURCES.txt"
cd "$OUTDIR"
tar -cJf "${PKG}.tar.xz" "$PKG"
sha256sum "${PKG}.tar.xz" > "${PKG}.tar.xz.sha256"
cat "${PKG}.tar.xz.sha256"
echo "Done: $OUTDIR/${PKG}.tar.xz"
