#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_BASE="$SCRIPT_DIR/output"

# version:branch:ext:msvcrt:mode
VERSIONS=(
    "1.8.7:1.8:tar.bz2:0:legacy"
    "1.9.7:1.9:tar.bz2:0:legacy"
    "2.0.5:2.0:tar.xz:0:legacy"
    "3.0.5:3.0:tar.xz:0:legacy"
    "4.12.1:4.x:tar.xz:0:legacy"
    "5.0.5:5.0:tar.xz:0:legacy"
    "6.0.4:6.0:tar.xz:1:legacy"
    "7.0.2:7.0:tar.xz:0:legacy"
    "8.0.2:8.0:tar.xz:0:modern"
)

FORCE=0
NO_CACHE=""
PROGRESS_PLAIN=0
SILENT=1
FILTER_VERSIONS=()
EXPECT=""
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1; EXPECT=""; continue;;
        --no-cache) NO_CACHE="--no-cache"; EXPECT=""; continue;;
        --progress=plain) PROGRESS_PLAIN=1; EXPECT=""; continue;;
        --debug) SILENT=0; EXPECT=""; continue;;
        --only|--versions) EXPECT="versions"; continue;;
        --flavors) EXPECT="flavors"; continue;; # Ignored in universal mode
        --*) EXPECT=""; continue;;
    esac
    if [ "$EXPECT" = "versions" ]; then
        FILTER_VERSIONS+=("$arg")
    fi
done

fix_ucrtbase_imports() {
    python3 -c "
import sys, os, glob
for path in glob.glob(os.path.join(sys.argv[1], '*.dll')):
    with open(path, 'rb') as f: data = f.read()
    p = data.replace(b'ucrtbase.dll\x00', b'msvcrt.dll\x00\x00\x00')
    if p != data:
        with open(path, 'wb') as f: f.write(p)
        print('  [fix] ucrtbase->msvcrt:', os.path.basename(path))
" "$1"
}

patch_pe_win98() {
    python3 "$SCRIPT_DIR/docker/patch_pe_win98.py" "$1" 2>/dev/null || echo "  WARNING: python3 PE patching failed"
}

for entry in "${VERSIONS[@]}"; do
    IFS=: read WINE_VERSION WINE_BRANCH WINE_EXT BUILD_MSVCRT BUILD_MODE <<< "$entry"

    if [ ${#FILTER_VERSIONS[@]} -gt 0 ]; then
        skip=1
        for fv in "${FILTER_VERSIONS[@]}"; do
            [ "$fv" = "$WINE_VERSION" ] && skip=0
        done
        [ "$skip" = 1 ] && continue
    fi

    OUTDIR="$OUTPUT_BASE/$WINE_VERSION"
    TAG="wine-dll-builder:$WINE_VERSION"

    if [ "$FORCE" = "0" ] && [ -f "$OUTDIR/wined3d.dll" ]; then
        echo "=== Skipping Wine $WINE_VERSION (universal, already built — use --force to rebuild) ==="
        continue
    fi

    echo "=== Building Wine $WINE_VERSION ($BUILD_MODE, universal, silent=$SILENT) ==="
    docker build $NO_CACHE --platform linux/amd64 \
        --build-arg WINE_VERSION=$WINE_VERSION \
        --build-arg WINE_BRANCH=$WINE_BRANCH \
        --build-arg WINE_EXT=$WINE_EXT \
        --build-arg BUILD_MSVCRT=$BUILD_MSVCRT \
        --build-arg BUILD_MODE=$BUILD_MODE \
        --build-arg SILENT=$SILENT \
        $( [ "$PROGRESS_PLAIN" = "1" ] && echo "--progress=plain" ) \
        -t $TAG \
        "$SCRIPT_DIR"
    mkdir -p "$OUTDIR"
    docker create --name extract-$WINE_VERSION $TAG
    docker cp extract-$WINE_VERSION:/output/$WINE_VERSION/. "$OUTDIR/"
    docker rm extract-$WINE_VERSION
    echo "Done: $(ls "$OUTDIR/")"
    fix_ucrtbase_imports "$OUTDIR"
    patch_pe_win98 "$OUTDIR"
    if [ -f "$OUTDIR/msvcrt.dll" ]; then
        python3 "$SCRIPT_DIR/docker/patch_msvcrt.py" "$OUTDIR/msvcrt.dll"
    fi
done

echo ""
echo "=== Summary ==="
for entry in "${VERSIONS[@]}"; do
    IFS=: read WINE_VERSION _ <<< "$entry"
    OUTDIR="$OUTPUT_BASE/$WINE_VERSION"
    if [ -f "$OUTDIR/wined3d.dll" ]; then
        echo "  ✓ $WINE_VERSION (universal)"
    else
        echo "  ✗ $WINE_VERSION (missing)"
    fi
done
