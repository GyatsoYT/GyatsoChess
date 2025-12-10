#!/bin/sh
echo "Compiling Gyatso..."
nim c -d:danger --passC:-march=native -o:Gyatso Gyatso/src/main.nim
echo "Compilation finished."
