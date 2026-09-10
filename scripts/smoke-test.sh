#!/bin/sh
# smoke-test.sh - two minute release validation for libre-qemu-3dfx.
#
# Validates a portable QEMU build plus freeaddons.iso without needing a
# Windows license or a guest install:
#   1. binaries exist and report --version
#   2. SDL display backend is compiled in
#   3. host accel (kvm, hvf, whpx, tcg) is recognized
#   4. AVX class instructions stay inside runtime dispatched helpers
#   5. freeaddons.iso exists with the expected payload
#
# Usage:
#   sh scripts/smoke-test.sh [--qemu-dir=DIR] [--iso=PATH] [--skip-avx]
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QEMU_DIR=""
ISO="$ROOT/freeaddons/freeaddons.iso"
SKIP_AVX=0

for arg in "$@"; do
    case "$arg" in
        --qemu-dir=*) QEMU_DIR="${arg#--qemu-dir=}" ;;
        --iso=*) ISO="${arg#--iso=}" ;;
        --skip-avx) SKIP_AVX=1 ;;
        --help|-h)
            echo "Usage: $0 [--qemu-dir=DIR] [--iso=PATH] [--skip-avx]"
            exit 0
            ;;
        *) echo "Unknown arg: $arg" >&2; exit 1 ;;
    esac
done

if [ -z "$QEMU_DIR" ]; then
    for d in "$ROOT"/dist-qemu-portable/libre-*/ "$ROOT"/build-qemu-*/; do
        [ -d "$d" ] || continue
        case "$d" in *logs*) continue ;; esac
        QEMU_DIR="$d"
    done
fi
if [ -z "$QEMU_DIR" ] || [ ! -d "$QEMU_DIR" ]; then
    echo "FAIL: no QEMU build dir found (tried dist-qemu-portable and build-qemu-*)"
    exit 1
fi
echo "Testing: $QEMU_DIR"

PASS=0
FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

BIN_I386="$QEMU_DIR/qemu-system-i386"
BIN_X64="$QEMU_DIR/qemu-system-x86_64"
if [ -x "$BIN_I386" ] && [ -x "$BIN_X64" ]; then
    ok "binaries present"
else
    bad "binaries missing in $QEMU_DIR"
fi

if "$BIN_X64" --version 2>/dev/null | grep -q "QEMU emulator"; then
    ok "qemu-system-x86_64 runs ($("$BIN_X64" --version 2>/dev/null | head -1))"
else
    bad "qemu-system-x86_64 --version failed"
fi
if "$BIN_I386" --version 2>/dev/null | grep -q "QEMU emulator"; then
    ok "qemu-system-i386 runs"
else
    bad "qemu-system-i386 --version failed"
fi

if "$BIN_X64" -display help 2>&1 | grep -qi sdl; then
    ok "SDL display backend compiled in"
else
    bad "SDL display backend missing (guest video needs -display sdl)"
fi

ACCEL_OUT=$("$BIN_X64" -accel help 2>&1 || true)
if echo "$ACCEL_OUT" | grep -Eq "kvm|hvf|whpx|tcg"; then
    ok "accel recognized ($(echo "$ACCEL_OUT" | grep -Eo "kvm|hvf|whpx|tcg" | tr '\n' ' '))"
else
    bad "no known accel backend reported"
fi
if [ -e /dev/kvm ]; then
    ok "/dev/kvm present"
else
    echo "INFO: /dev/kvm absent (fine on non Linux hosts or without KVM)"
fi

if [ "$SKIP_AVX" = "1" ]; then
    echo "INFO: AVX check skipped"
else
    AVX_FAIL=0
    for bin in "$BIN_I386" "$BIN_X64"; do
        [ -x "$bin" ] || continue
        BAD=$(objdump -d "$bin" 2>/dev/null | awk '/^[0-9a-f]+ <.*>:$/ {sym=$2} /vmovaps|vmovups|vpxor|vpadd|vbroadcast|ymm[0-9]|zmm[0-9]/ {print sym}' | grep -v -e "<buffer_zero_avx2>:" -e "<xbzrle_encode_buffer_avx512>:" || true)
        if [ -n "$BAD" ]; then
            bad "AVX outside dispatched helpers in $(basename "$bin")"
            echo "$BAD" | head -5
            AVX_FAIL=1
        fi
    done
    [ "$AVX_FAIL" = "0" ] && ok "AVX confined to runtime dispatched helpers"
fi

if [ -f "$ISO" ]; then
    ok "freeaddons.iso present ($(du -h "$ISO" | cut -f1))"
    if command -v xorriso > /dev/null 2>&1; then
        ISO_LIST=$(xorriso -indev "$ISO" -find / -maxdepth 3 2>/dev/null || true)
        for want in SOURCES.txt wrapfx freeaddons.bat; do
            if echo "$ISO_LIST" | grep -q "$want"; then
                ok "iso holds $want"
            else
                bad "iso missing $want"
            fi
        done
    else
        echo "INFO: xorriso absent, skipping iso payload listing"
    fi
else
    bad "freeaddons.iso missing (run freeaddons/scripts/assemble-iso.sh)"
fi

echo ""
echo "Smoke test: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
