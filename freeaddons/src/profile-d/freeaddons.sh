# Freeaddons ISO path setup — sourced by /etc/profile for login shells.
# Adds the ISO root (freeaddons.sh) and win32/wine (freeaddons-get) to
# PATH. The ISO root is located by marker file: the launch directory
# first (rxvt inherits the CD root as CWD), then the filesystem root,
# then DOS drive roots (MSYS maps C:\, D:\, ... as /c, /d, ...).
# Only acts when a Freeaddons tree is found, so an unrelated shell
# stays untouched.
_FAROOT=""
for _d in "$(pwd)" / /c /d /e /f /g; do
    if [ -f "$_d/freeaddons.sh" ]; then
        _FAROOT="$_d"
        break
    fi
done
if [ -n "$_FAROOT" ]; then
    case ":$PATH:" in
        *"$_FAROOT:"*) ;;
        *) export PATH="$PATH:$_FAROOT:$_FAROOT/win32/wine";;
    esac
fi
unset _FAROOT _d
