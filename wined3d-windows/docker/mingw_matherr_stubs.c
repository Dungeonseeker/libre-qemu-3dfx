/*
 * mingw_matherr_stubs.c — no-op stubs for MinGW internal CRT symbols
 *
 * When linking wined3d.dll with -nostdlib -nodefaultlibs, MinGW's libmsvcrt.a
 * math wrappers (cos, pow, sqrtf etc.) reference __mingw_raise_matherr from
 * libmingwex.a, which in turn pulls in _vsnprintf/_vscprintf from msvcrt,
 * creating a circular dependency that cannot be resolved with -nostdlib.
 *
 * Solution: provide no-op stubs here so the linker resolves these symbols
 * from this object file instead, breaking the circular dependency entirely.
 * wined3d on Win98 never triggers math error handling, so these are safe.
 */

#include <stdarg.h>

/* Called by MinGW math wrappers on domain/range errors — not needed on Win98 */
void __mingw_raise_matherr(int type, const char *name,
                            double arg1, double arg2, double retval)
{
    (void)type; (void)name; (void)arg1; (void)arg2; (void)retval;
}

/* _vsnprintf / _vscprintf — stubs for MinGW CRT math references.
 * The real _vsnprintf implementation comes from heap_compat.c. */
int __cdecl _vsnprintf(char *buf, unsigned int count, const char *fmt, void *ap);

int _vscprintf(const char *fmt, va_list ap)
{
    (void)fmt; (void)ap;
    return 0;
}

/* __logl_internal — called by MinGW's log() wrapper in libmsvcrt.a.
 * Uses x87 FPU directly to avoid depending on msvcrt's log(). */
double __logl_internal(double x)
{
    __asm__("fldln2; fxch; fyl2x" : "+t"(x));
    return x;
}

/* __ms_vsnprintf — alias used by MinGW's vsnprintf wrapper in libmsvcrt.a */
int __ms_vsnprintf(char *buf, unsigned int size, const char *fmt, va_list ap)
{
    return _vsnprintf(buf, size, fmt, ap);
}

