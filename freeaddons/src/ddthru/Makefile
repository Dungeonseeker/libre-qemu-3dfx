# Freeaddons ddthru trampolines (ddraw.dll / dsound.dll loader stubs).
# One source builds both; the same binaries ship in the 2K/98ME/XP dirs
# (donor variants differ only in build stamps, export sets identical).
# MSVCRT-only, NO_SEH via the shared wined3d-windows PE post-processing.
CC      = i686-w64-mingw32-gcc
DLLTOOL = i686-w64-mingw32-dlltool
CFLAGS  = -std=c99 -O2 -fomit-frame-pointer -D_WIN32 -DWIN32 -DNDEBUG \
          -DWINVER=0x0501 -D__USE_MINGW_ANSI_STDIO=0 -Wall
LDFLAGS = -shared -s -nostdlib -static-libgcc -lgcc -lkernel32 \
          -Wl,-e,_DllMain@12,--disable-auto-image-base,--dynamicbase,--nxcompat
WINE_DOCKER = ../../../wined3d-windows/docker

all: ddraw.dll dsound.dll

ddraw.dll: ddthru.c ddraw.def
	$(CC) $(CFLAGS) -DDDTHRU_DSOUND=0 -o $@ ddthru.c ddraw.def $(LDFLAGS)

dsound.dll: ddthru.c dsound.def
	$(CC) $(CFLAGS) -DDDTHRU_DSOUND=1 -o $@ ddthru.c dsound.def $(LDFLAGS)

# .def files carry undecorated export names (donor tables match).
ddraw.def:
	@printf 'LIBRARY ddraw\nEXPORTS\n' > $@
	@for n in AcquireDDThreadLock CompleteCreateSysmemSurface \
	    D3DParseUnknownCommand DDInternalLock DDInternalUnlock \
	    DirectDrawCreate DirectDrawCreateClipper DirectDrawCreateEx \
	    DirectDrawEnumerateA DirectDrawEnumerateExA DirectDrawEnumerateExW \
	    DirectDrawEnumerateW DllCanUnloadNow DllGetClassObject \
	    GetSurfaceFromDC ReleaseDDThreadLock; do echo "    $$n" >> $@; done

dsound.def:
	@printf 'LIBRARY dsound\nEXPORTS\n' > $@
	@for n in DirectSoundCaptureCreate DirectSoundCaptureCreate8 \
	    DirectSoundCaptureEnumerateA DirectSoundCaptureEnumerateW \
	    DirectSoundCreate DirectSoundCreate8 DirectSoundEnumerateA \
	    DirectSoundEnumerateW DirectSoundFullDuplexCreate \
	    DllCanUnloadNow DllGetClassObject GetDeviceID; do echo "    $$n" >> $@; done

# Same post-processing as the Wine DLLs: NO_SEH + debug strip + symtab relocate.
post: all
	python3 $(WINE_DOCKER)/patch_pe_win98.py .

check: post
	@for d in ddraw.dll dsound.dll; do \
	    i686-w64-mingw32-objdump -p $$d > /dev/null || { echo "BROKEN: $$d"; exit 1; }; \
	    i686-w64-mingw32-objdump -p $$d | grep -qi ucrtbase && { echo "UCRT: $$d"; exit 1; } || true; \
	done
	@echo "ddthru OK"

clean:
	rm -f *.dll *.def *.o

.PHONY: all post check clean
