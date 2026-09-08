#!/bin/sh
# gen-msvcrt-implib.sh — build a real msvcrt.dll import library for the
# modern MinGW toolchain (whose libmsvcrt.a forwards to UCRT api-sets,
# unloadable on Win9x/XP).
#
# Usage: gen-msvcrt-implib.sh <out.a> <obj...> -- <syslib...>
#   Collects undefined symbols from <obj> (plus any archives listed with
#   them, e.g. libmingwex.a whose members drag their own CRT deps),
#   subtracts symbols defined in <obj> and symbols provided by <syslib>
#   import libs; every leftover must be a C runtime import and lands in
#   msvcrt.dll via dlltool. Leftovers outside the EXPECTED tripwire list
#   fail loudly so a missing system lib can never silently become a
#   bogus msvcrt import.
set -e
OUT="$1"; shift
OBJS=""
SYSLIBS=""
IN_SYS=0
for a in "$@"; do
    if [ "$a" = "--" ]; then IN_SYS=1; continue; fi
    if [ "$IN_SYS" = "0" ]; then OBJS="$OBJS $a"; else SYSLIBS="$SYSLIBS $a"; fi
done
[ -z "$OUT" ] || [ -z "$OBJS" ] && { echo "Usage: $0 <out.a> <obj...> [-- <syslib...>]"; exit 1; }

NM=i686-w64-mingw32-nm
which $NM > /dev/null 2>&1 || NM=nm
DLLTOOL=i686-w64-mingw32-dlltool

# Expected CRT surface (tripwire — extend deliberately, never blindly).
EXPECTED="fclose fgets fopen fseek lseek open read close stricmp strtok strtol strtoul sprintf sscanf printf fprintf vfprintf vsprintf puts putchar fputs malloc free calloc realloc qsort abort exit atexit getenv clock time rand srand memset memcpy memmove memcmp memchr strlen strcpy strcat strcmp strncmp strncpy strncat strchr strrchr strcspn strspn strpbrk strdup atoi atol _errno _vsnprintf vsnprintf _strdup _write _read _open _close _lseek _fstat fstat _stat stat _findfirst _findnext _findclose fopen_s"

TMPD=`mktemp -d`
trap "rm -rf $TMPD" EXIT INT TERM
$NM -u $OBJS 2>/dev/null | awk '$1=="U"{print $2}' | sort -u > "$TMPD/u.txt"
$NM -g $OBJS 2>/dev/null | awk 'NF==3 && $2!="U"{print $3}' | sort -u > "$TMPD/def.txt"
: > "$TMPD/sys.txt"
for lib in $SYSLIBS; do
    if [ ! -f "$lib" ]; then
        echo "gen-msvcrt-implib: WARNING: syslib not found: $lib (CROSS wrong?)" >&2
        continue
    fi
    $NM -g "$lib" 2>/dev/null | awk 'NF==3 && $2!="U"{print $3}' >> "$TMPD/sys.txt"
done
sort -u -o "$TMPD/sys.txt" "$TMPD/sys.txt"
# C-speed set subtraction via fixed-string matching (per-symbol shell
# loops over ten-thousand-entry import libs hang essentially forever).
basefile() {
    sed -e "s/^__imp__//" -e "s/^_//" -e "s/@[0-9][0-9]*$//" "$1" | sort -u
}
basefile "$TMPD/u.txt" > "$TMPD/u.base"
basefile "$TMPD/def.txt" > "$TMPD/def.base"
basefile "$TMPD/sys.txt" > "$TMPD/sys.base"
grep -Fxv -f "$TMPD/def.base" "$TMPD/u.base" | grep -Fxv -f "$TMPD/sys.base" > "$TMPD/left.txt" || true
# ___main (CRT ctor hook) is provided by the rawmain entry shim and only
# ever needed in exes, which always link it. Drop silently.
grep -Fxv "__main" "$TMPD/left.txt" > "$TMPD/left2.txt" || true
# Compiler/LTO-synthesized libc calls (memcpy et al. materialize at link
# time without any object referencing them — LTO stringop/IPA passes can
# invent any of these): always emit. All are C89 msvcrt.dll exports,
# present even in the Win98 msvcrt 6.0.
for b in memcpy memmove memset memcmp memchr strlen strcmp strncmp strcpy strncpy strcat strncat strchr strrchr strcspn strspn strpbrk strdup calloc malloc realloc free sprintf vsprintf abort atexit; do echo "$b" >> "$TMPD/left2.txt"; done
LEFTOVER=`sort -u "$TMPD/left2.txt" | tr '\n' ' '`

UNEXPECTED=""
for s in $LEFTOVER; do
    echo " $EXPECTED " | grep -q " $s " || UNEXPECTED="$UNEXPECTED $s"
done
if [ -n "$UNEXPECTED" ]; then
    echo "gen-msvcrt-implib: UNEXPECTED imports (not Win32, not known CRT):$UNEXPECTED"
    echo "Add the missing system lib to the link or extend EXPECTED deliberately."
    exit 1
fi
if [ -z "$LEFTOVER" ]; then
    echo "gen-msvcrt-implib: nothing to import"
    exit 1
fi

DEF=`dirname $OUT`/msvcrt_gen.def
{ echo "LIBRARY msvcrt"; echo "EXPORTS"; for s in $LEFTOVER; do echo "    $s"; done; } > "$DEF"
$DLLTOOL -d "$DEF" -l "$OUT"
echo "gen-msvcrt-implib: $OUT <=$LEFTOVER"
