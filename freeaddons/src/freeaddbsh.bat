@echo off
set MSYSTEM=Freeaddons
rem Point HOME at the writable user profile so the (read-only) ISO shell
rem does not try to mkdir /home or copy inputrc on startup.
set HOME=%USERPROFILE%
win32\msys\bin\rxvt -tn %MSYSTEM% -fn "Lucida Console-12" +sb -geometry 92x34 -e /bin/sh --login -i

