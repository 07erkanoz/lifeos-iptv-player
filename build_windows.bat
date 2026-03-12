@echo off
set "ProgramFiles(x86)=C:\Program Files (x86)"
cd /d C:\Projeler\HayatDefteri\LifeosTV-flutter
call flutter pub get
call flutter build windows --release
