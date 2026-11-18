@echo off
setlocal
set "PATH=%~dp0media;%PATH%"
"%~dp0python\python.exe" -I -m opendirector.cli %*
exit /b %errorlevel%
