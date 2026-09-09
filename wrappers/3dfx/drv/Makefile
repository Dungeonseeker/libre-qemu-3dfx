FXLIB=../../fxlib
CROSS?=
CC=$(CROSS)gcc
CFLAGS=-march=i686 -mtune=generic
CFLAGS+=-pipe -I$(FXLIB) -Wall -Wextra -Werror -mcrtdll=msvcrt

WATCOM_PATH=$(shell dirname `which wcc386 2>/dev/null` 2>/dev/null)
WCL=$(if $(WATCOM_PATH),$(WATCOM_PATH)/wcl386,wcl386)
WLD=$(if $(WATCOM_PATH),$(WATCOM_PATH)/wlink,wlink)

OUTDIR?=build

all: instdrv.exe fxmemmap.vxd fxptl.sys

instdrv.exe: instdrv.c
	@if [ ! -d ../$(OUTDIR) ]; then exit 1; fi
	@echo "  LD  $@"
	@$(CC) $(CFLAGS) -s -o ../$(OUTDIR)/$@ $< ../$(OUTDIR)/fxlibnt.o

fxmemmap.vxd: fxmemmap.c
	@if [ ! -d ../$(OUTDIR) ]; then exit 1; fi
	@echo "  WCC $@"
	@$(WCL) -zq -s -5r -fpi87 $< -c -fo=../$(OUTDIR)/fxmemmap.obj
	@echo "  WLD $@"
	@$(WLD) format windows vxd dynamic name ../$(OUTDIR)/$@ file ../$(OUTDIR)/fxmemmap.obj export _The_DDB.1 > /dev/null

fxptl.sys: fxptl.c
	@if [ ! -d ../$(OUTDIR) ]; then exit 1; fi
	@echo "  DRV $@"
	@$(CC) -I/usr/i686-w64-mingw32/include/ddk -shared -nostdlib \
		-Wl,--subsystem,native -Wl,--entry,DriverEntry@8 \
		-Wl,--file-alignment,0x200 -Wl,--section-alignment,0x200 \
		-o ../$(OUTDIR)/$@ $< -lntoskrnl

clean:
	@rm -f ../$(OUTDIR)/instdrv.exe ../$(OUTDIR)/fxmemmap.vxd ../$(OUTDIR)/fxmemmap.obj ../$(OUTDIR)/fxptl.sys

distclean: clean
