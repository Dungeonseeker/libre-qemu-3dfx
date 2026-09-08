#!/bin/sh
# Freeaddons system installer — behavior-compatible with the donor
# vmaddons.sh flow: installs glide wrappers for the running Windows
# version, then swaps the system ddraw/dsound for ddthru trampolines
# backed by ddrawwq/dsoundwq copies of the originals.

export MSYSTEM=MSYS
export PATH=$PWD/win32/msys/bin:$PATH
WINOS=`uname | sed "s/.*_//"`
echo "Windows $WINOS"

if [ "$WINOS" == "98-4.10" ] || [ "$WINOS" == "ME-4.90" ]; then
    DDTHRU=DDTHRU/98ME
    SYSTEMDIR=$WINBOOTDIR/SYSTEM
    CACHE=../SYSBCKUP
    if [ ! -d $SYSTEMDIR/$CACHE ]; then
        echo "ERROR: Missing SYSBCKUP"
        exit 1
    fi
    cp -f win32/wrapfx/fxmemmap.vxd $SYSTEMDIR/
    cp -f win32/wrapfx/glide*.dll $SYSTEMDIR/
    cp -f win32/wrapfx/glide*.ovl $WINBOOTDIR/
fi
if [ "$WINOS" == "NT-5.0" ]; then
    DDTHRU=DDTHRU/2K
    SYSTEMDIR=$SYSTEMROOT/system32
    CACHE=dllcache
    if [ ! -d $SYSTEMDIR/$CACHE ]; then
        echo "ERROR: Missing %SystemRoot%\dllcache"
        exit 1
    fi
    cp -f win32/wrapfx/fxptl.sys $SYSTEMDIR/drivers/
    cp -f win32/wrapfx/glide*.dll $SYSTEMDIR/
    ./win32/wrapfx/instdrv
fi
if [ "$WINOS" == "NT-5.1" ]; then
    DDTHRU=DDTHRU/XP
    SYSTEMDIR=$SYSTEMROOT/system32
    CACHE=dllcache
    if [ ! -d $SYSTEMDIR/$CACHE ]; then
        echo "ERROR: Missing %SystemRoot%\dllcache"
        exit 1
    fi
    cp -f win32/wrapfx/fxptl.sys $SYSTEMDIR/drivers/
    cp -f win32/wrapfx/glide*.dll $SYSTEMDIR/
    ./win32/wrapfx/instdrv
fi
if [ -z "$DDTHRU" ]; then
    echo "ERROR: Unknown Windows OS"
    exit 1
fi
if objdump -x $SYSTEMDIR/dsound.dll | grep DLL\ Name: | grep -i ddraw; then
    echo "Please upgrade DirectX Runtime to DirectX 8.1 (4.08.01.0881) or newer"
    exit 1
fi

echo "SYSTEMDIR at $SYSTEMDIR"
if [ -f $SYSTEMDIR/ddrawwq.dll ]; then
    diff $SYSTEMDIR/ddrawwq.dll $SYSTEMDIR/$CACHE/ddrawwq.dll
    if [ $? -ne 0 ]; then
        echo ERROR: DDRAWWQ already exist but mismatch
        exit 1
    fi
else
    cp -f $SYSTEMDIR/ddraw.dll $SYSTEMDIR/$CACHE/ddrawwq.dll
fi
if [ -f $SYSTEMDIR/dsoundwq.dll ]; then
    diff $SYSTEMDIR/dsoundwq.dll $SYSTEMDIR/$CACHE/dsoundwq.dll
    if [ $? -ne 0 ]; then
        echo ERROR: DSOUNDWQ already exist but mismatch
        exit 1
    fi
else
    cp -f $SYSTEMDIR/dsound.dll $SYSTEMDIR/$CACHE/dsoundwq.dll
fi
cp -f win32/wine/$DDTHRU/ddraw.dll $SYSTEMDIR/$CACHE/ddraw.dll
cp -f $SYSTEMDIR/$CACHE/ddrawwq.dll $SYSTEMDIR/
cp -f $SYSTEMDIR/$CACHE/ddraw.dll $SYSTEMDIR/
cp -f win32/wine/$DDTHRU/dsound.dll $SYSTEMDIR/$CACHE/dsound.dll
cp -f $SYSTEMDIR/$CACHE/dsoundwq.dll $SYSTEMDIR/
cp -f $SYSTEMDIR/$CACHE/dsound.dll $SYSTEMDIR/
echo "SUCCESS: $DDTHRU installed"
