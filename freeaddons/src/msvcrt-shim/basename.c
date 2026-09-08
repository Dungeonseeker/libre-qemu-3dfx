/* basename_shim.c — POSIX basename for -nostdlib links.
 *
 * Replaces the libmingwex basename: linking libmingwex on a modern
 * toolchain drags UCRT-only dependencies (calloc/memcpy via api-sets)
 * that do not exist on Win9x/XP. This implementation needs only strlen
 * (msvcrt) and matches mingw behavior for drive letters and both slash
 * kinds. Callers use the result read-only.
 */
unsigned int strlen(const char *s);

static char dot[] = ".";

char *basename(const char *name)
{
    const char *e, *s;

    if (!name || !*name)
        return dot;
    e = name + strlen(name);
    while (e > name && (e[-1] == '/' || e[-1] == '\\'))
        e--;
    if (e == name)
        return (char *)name;
    s = e;
    while (s > name && s[-1] != '/' && s[-1] != '\\' && s[-1] != ':')
        s--;
    return (char *)s;
}
