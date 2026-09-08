#!/bin/sh
# fetch-msys.sh — reproducibly stage the Freeaddons win32/msys tree from
# upstream MinGW MSYS 1.0.18 packages (SourceForge).
#
# Usage: fetch-msys.sh <staging-win32-dir> [--record]
#   --record  (re)write MANIFEST.sha256 with the downloaded file hashes.
# Without --record, every download is verified against MANIFEST.sha256.
# Afterwards an import-closure check (objdump DLL deps + runtime-load
# strings scan) fails the run if any non-system DLL is missing.
set -e
DESTDIR="$1"
RECORD=0
[ "$2" = "--record" ] && RECORD=1
[ -z "$DESTDIR" ] && { echo "Usage: $0 <staging-win32-dir> [--record]"; exit 1; }
# Absolute paths throughout: verification subshells cd elsewhere.
SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"
DESTDIR="$(cd "$DESTDIR" 2>/dev/null && pwd || (mkdir -p "$DESTDIR" && cd "$DESTDIR" && pwd))"

SF=https://downloads.sourceforge.net/project/mingw/MSYS
CACHE="$SCRIPTDIR/.pkgcache-msys"
MANIFEST="$SCRIPTDIR/MANIFEST.msys.sha256"
mkdir -p "$CACHE" "$DESTDIR/msys/bin" "$DESTDIR/msys/etc"
# Fresh stage every run (partial runs must not leave stale files behind).
rm -rf "$DESTDIR/msys/bin" "$DESTDIR/msys/etc"
mkdir -p "$DESTDIR/msys/bin" "$DESTDIR/msys/etc"

# package-path-under-$SF (wanted files resolve across all of them).
PKGS="
Base/msys-core/msys-1.0.18-1/msysCORE-1.0.18-1-msys-1.0.18-bin.tar.lzma
Base/msys-core/msys-1.0.18-1/msysCORE-1.0.18-1-msys-1.0.18-ext.tar.lzma
Base/bash/bash-3.1.17-4/bash-3.1.17-4-msys-1.0.16-bin.tar.lzma
Base/coreutils/coreutils-5.97-3/coreutils-5.97-3-msys-1.0.13-bin.tar.lzma
Base/coreutils/coreutils-5.97-3/coreutils-5.97-3-msys-1.0.13-ext.tar.lzma
Base/sed/sed-4.2.1-2/sed-4.2.1-2-msys-1.0.13-bin.tar.lzma
Base/grep/grep-2.5.4-2/grep-2.5.4-2-msys-1.0.13-bin.tar.lzma
Base/findutils/findutils-4.4.2-2/findutils-4.4.2-2-msys-1.0.13-bin.tar.lzma
Base/diffutils/diffutils-2.8.7.20071206cvs-3/diffutils-2.8.7.20071206cvs-3-msys-1.0.13-bin.tar.lzma
Base/less/less-436-2/less-436-2-msys-1.0.13-bin.tar.lzma
Extension/rxvt/rxvt-2.7.2-3/rxvt-2.7.2-3-msys-1.0.14-bin.tar.lzma
msysdev/binutils/binutils-2.19.51-3/binutils-2.19.51-3-msys-1.0.13-bin.tar.lzma
Base/libiconv/libiconv-1.13.1-2/libiconv-1.13.1-2-msys-1.0.13-dll-2.tar.lzma
Base/gettext/gettext-0.18.1.1-1/libintl-0.18.1.1-1-msys-1.0.17-dll-8.tar.lzma
Base/gawk/gawk-3.1.7-2/gawk-3.1.7-2-msys-1.0.13-bin.tar.lzma
Extension/patch/patch-2.6.1-1/patch-2.6.1-1-msys-1.0.13-bin.tar.lzma
Base/tar/tar-1.23-1/tar-1.23-1-msys-1.0.13-bin.tar.lzma
Base/gzip/gzip-1.3.12-2/gzip-1.3.12-2-msys-1.0.13-bin.tar.lzma
Base/termcap/termcap-0.20050421_1-2/libtermcap-0.20050421_1-2-msys-1.0.13-dll-0.tar.lzma
Base/regex/regex-1.20090805-2/libregex-1.20090805-2-msys-1.0.13-dll-1.tar.lzma
Extension/dos2unix/dos2unix-5.3.2-1/dos2unix-5.3.2-1-msys-1.0.17-bin.tar.lzma
"
# Wanted files (resolved from the first package containing each):
WANTS="msys-1.0.dll msys-iconv-2.dll msys-intl-8.dll msys-W11.dll msys-termcap-0.dll msys-regex-1.dll sh.exe bash.exe cmd clsb which.exe profile basename.exe cat.exe cp.exe dd.exe diff.exe dirname.exe expr.exe find.exe grep.exe head.exe id.exe less.exe ls.exe md5sum.exe mkdir.exe mv.exe objdump.exe rxvt.exe sed.exe sort.exe strings.exe tail.exe tee.exe touch.exe tr.exe uname.exe unix2dos.exe gawk.exe patch.exe tar.exe gzip.exe du.exe chmod.exe ln.exe rm.exe sleep.exe od.exe mount.exe umount.exe"

fetch_one() {
    path="$1"
    url="$SF/$path"
    base=`basename $path`
    if [ ! -f "$CACHE/$base" ]; then
        echo "GET $url"
        curl -sL --retry 3 -o "$CACHE/$base" "$url"
    fi
    if head -c 15 "$CACHE/$base" | grep -qi "<html"; then
        echo "BAD URL (HTML 404 page): $url"
        rm -f "$CACHE/$base"
        exit 1
    fi
    if [ "$RECORD" = "1" ]; then
        sha256sum "$CACHE/$base" | sed "s|$CACHE/||" >> "$MANIFEST.new"
    else
        if [ -f "$MANIFEST" ]; then
            (cd "$CACHE" && sha256sum -c --status <(grep -F "$base" "$MANIFEST")) \
                || { echo "HASH MISMATCH: $base"; exit 1; }
        else
            echo "WARNING: no $MANIFEST — run with --record once, review, commit"
        fi
    fi
}

[ "$RECORD" = "1" ] && rm -f "$MANIFEST.new"
printf '%s\n' "$PKGS" | grep -v '^$' > "$CACHE/.wanted.txt"
# Pass 1: fetch everything, index members per tarball.
> "$CACHE/.index.txt"
while read path; do
    [ -z "$path" ] && continue
    fetch_one "$path"
    base=`basename $path`
    tar -tf "$CACHE/$base" 2>/dev/null | sed "s|^\./||" | sed "s|^|$base:|" >> "$CACHE/.index.txt"
done < "$CACHE/.wanted.txt"
# Pass 2: resolve each wanted file from the first tarball containing it.
find_member() { # $1 = wanted name -> prints "tarball:member"
    want="$1"
    grep -E "[:/]bin/$want$" "$CACHE/.index.txt" | head -n 1
    grep -E "[:/]$want$" "$CACHE/.index.txt" | head -n 1
    grep -E "[:/]etc/$want$" "$CACHE/.index.txt" | head -n 1
    # MSYS ships some tools extensionless (mount, umount, ...).
    base=`echo "$want" | sed "s/\.exe$//"`
    if [ "$base" != "$want" ]; then
        grep -E "[:/]bin/$base$" "$CACHE/.index.txt" | head -n 1
    fi
}
WANTS=`echo "$WANTS" | tr ' ' '\n' | sort -u`
for want in $WANTS; do
    hit=`find_member "$want" | head -n 1`
    [ -z "$hit" ] && { echo "MISSING $want in all packages"; exit 1; }
    base=`echo "$hit" | cut -d: -f1`
    member=`echo "$hit" | cut -d: -f2-`
    case "$want" in
        profile) out="$DESTDIR/msys/etc/profile";;
        *)       out="$DESTDIR/msys/bin/$want";;
    esac
    tar -xf "$CACHE/$base" -O "$member" > "$out"
done
[ "$RECORD" = "1" ] && mv "$MANIFEST.new" "$MANIFEST" && echo "manifest written"

# awk is a hardlink twin of gawk upstream; recreate if the package lacks it.
[ -f "$DESTDIR/msys/bin/awk.exe" ] || \
    cp "$DESTDIR/msys/bin/gawk.exe" "$DESTDIR/msys/bin/awk.exe"

# Freeaddons helper scripts (ours, no upstream needed).
cp "$SCRIPTDIR/../src/msys-shims/reg"  "$DESTDIR/msys/bin/reg"
cp "$SCRIPTDIR/../src/msys-shims/msyspath" "$DESTDIR/msys/bin/msyspath.exe"
mkdir -p "$DESTDIR/msys/etc/profile.d"
cp "$SCRIPTDIR/../src/profile-d/freeaddons.sh" "$DESTDIR/msys/etc/profile.d/"

echo "=== import closure check ==="
FAIL=0
for exe in "$DESTDIR"/msys/bin/*.exe; do
    for dep in $(i686-w64-mingw32-objdump -p "$exe" 2>/dev/null | \
                 grep "DLL Name" | awk '{print $3}'); do
        case "$dep" in
            KERNEL32.dll|USER32.dll|ADVAPI32*|GDI32.dll) continue;;
            msys-*.dll)
                [ -f "$DESTDIR/msys/bin/$dep" ] || \
                    { echo "MISSING DLL: $dep (needed by `basename $exe`)"; FAIL=1; };;
            *) echo "UNEXPECTED DEP: $dep in `basename $exe`"; FAIL=1;;
        esac
    done
done
echo "=== runtime-load scan (LoadLibrary-style) ==="
for ref in $(grep -rhoE "msys-[A-Za-z0-9_-]+\.dll" "$DESTDIR"/msys/bin/ 2>/dev/null | sort -u); do
    [ -f "$DESTDIR/msys/bin/$ref" ] || \
        { echo "MISSING RUNTIME DLL: $ref"; FAIL=1; }
done
[ "$FAIL" = "0" ] && echo "msys closure OK" || exit 1
