/* rawmain.c — msvcrt-only exe entry without CRT startup.
 *
 * Links with -nostdlib -e _RawMain@0. Builds argc/argv from
 * GetCommandLineA with minimal quote handling, calls main(), and exits
 * via ExitProcess (returning from a raw entry would crash). No CRT, no
 * UCRT: kernel32 + msvcrt imports only. Works on Win98 through Win11.
 */
typedef void *HANDLE;
typedef unsigned long DWORD;
typedef char *LPSTR;

LPSTR __stdcall GetCommandLineA(void);
void __stdcall ExitProcess(unsigned code);

/* No CRT startup under -nostdlib: nothing registers constructors, so
   this is a safe no-op (never invoked). Satisfies libgcc references. */
void __cdecl ___main(void) { }

extern int main(int argc, char *argv[]);

static char *pargv[64];

void __stdcall RawMain(void)
{
    char *cmd = GetCommandLineA();
    int argc = 0;
    int inquote = 0;
    char *p = cmd;

    /* argv[0] is the program name, like CRT startup provides. */
    pargv[argc++] = p;
    if (*p == '"')
    {
        inquote = 1;
        p++;
        while (*p && (inquote || *p != ' ' || *(p - 1) == '\\'))
        {
            if (*p == '"')
                inquote = !inquote;
            p++;
        }
    }
    else
    {
        while (*p && *p != ' ' && *p != '\t')
            p++;
    }
    if (*p)
    {
        *p = 0;
        p++;
    }
    (void)cmd;

    /* Tokenize the rest in place. */
    while (*p && argc < 63)
    {
        while (*p == ' ' || *p == '\t')
            p++;
        if (!*p)
            break;
        pargv[argc++] = p;
        inquote = 0;
        while (*p)
        {
            if (*p == '"')
            {
                inquote = !inquote;
                /* Shift the quote out. */
                {
                    char *q = p;
                    while (*q)
                    {
                        *q = *(q + 1);
                        q++;
                    }
                }
                continue;
            }
            if (!inquote && (*p == ' ' || *p == '\t'))
                break;
            p++;
        }
        if (*p)
        {
            *p = 0;
            p++;
        }
    }
    pargv[argc] = 0;

    ExitProcess((unsigned)main(argc, pargv));
}
