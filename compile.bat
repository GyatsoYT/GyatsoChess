@echo off
echo Compiling Gyatso for Windows...
nim c -d:danger --passC:-march=native -o:Gyatso.exe Gyatso/src/main.nim
echo changes made successfully
echo Compilation finished.
pause
