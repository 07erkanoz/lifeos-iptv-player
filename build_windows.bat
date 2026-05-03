@echo off
REM Resolve to the directory that contains this script, regardless of the
REM caller's CWD or where the project is checked out.
set "ProgramFiles(x86)=C:\Program Files (x86)"
cd /d "%~dp0"
call flutter pub get
call flutter build windows --release
