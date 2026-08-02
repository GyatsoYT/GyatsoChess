@echo off
setlocal

echo Installing nimsimd dependency...
call nimble install -y nimsimd

:MENU
cls
echo GyatsoChess Build System
echo ========================
echo 1. Normal Build (Fast, Native)
echo 2. PGO Build (Slow, Maximum Performance)
echo.
set /p choice="Select build type (1/2): "

echo.
echo Select Target Architecture Extensions:
echo 1. Default   (auto-detect: NEON on ARM64, scalar elsewhere)
echo 2. AVX2      (x86-64 AVX2 NNUE + Magic Bitboards)
echo 3. AVX2+BMI2 (x86-64 AVX2 NNUE + BMI2 PEXT/PDEP Bitboards)
echo 4. AVX512    (x86-64 AVX-512 NNUE + BMI2 Bitboards)
echo 5. NEON      (explicit ARM64 / Apple Silicon)
set /p arch_choice="Select extensions (1/2/3/4/5): "

set AVX_FLAGS=
if "%arch_choice%"=="2" set AVX_FLAGS=-d:avx2
if "%arch_choice%"=="3" set AVX_FLAGS=-d:avx2 -d:bmi2
if "%arch_choice%"=="4" set AVX_FLAGS=-d:avx2 -d:bmi2 -d:avx512
if "%arch_choice%"=="5" set AVX_FLAGS=-d:neon

if "%choice%"=="1" goto NORMAL
if "%choice%"=="2" goto PGO
goto MENU

:NORMAL
echo.
echo === Normal Build ===
nim c -d:release -d:danger -d:simd %AVX_FLAGS% --cc:clang --mm:arc --define:useMalloc --styleCheck:hint --panics:on --opt:speed --passC:"-O3 -ffast-math -fstrict-aliasing -funroll-loops -fomit-frame-pointer -flto -fno-plt" --passL:"-O3 -flto -fuse-ld=lld" --passC:-march=native -o:Gyatso.exe Gyatso/src/main.nim
echo.
echo Compilation finished.
pause
exit /b

:PGO
echo.
echo === PGO Build Pipeline ===
echo.
echo [Stage 1] Instrumenting...
rem Build with profile generation
nim c --cc:clang -d:release -d:danger -d:simd %AVX_FLAGS% --mm:arc --define:useMalloc --styleCheck:hint --panics:on --opt:speed --passC:"-O3 -ffast-math -fstrict-aliasing -funroll-loops -fomit-frame-pointer -flto -fno-plt" --passL:"-O3 -flto -fuse-ld=lld" --passC:-march=native --passC:-fprofile-generate --passL:-fprofile-generate -o:Gyatso.exe Gyatso/src/main.nim
if errorlevel 1 goto ERROR

echo.
echo [Stage 2] Generating Workload Runner...
rem Generate Nim runner script
echo import osproc, streams, strutils, os > pgo_runner_temp.nim
echo. >> pgo_runner_temp.nim
echo proc main() = >> pgo_runner_temp.nim
echo   echo "[Runner] Starting Gyatso.exe..." >> pgo_runner_temp.nim
echo   var p = startProcess("Gyatso.exe", options={poUsePath, poStdErrToStdOut}) >> pgo_runner_temp.nim
echo   var inp = p.inputStream >> pgo_runner_temp.nim
echo   var outp = p.outputStream >> pgo_runner_temp.nim
echo. >> pgo_runner_temp.nim
echo   proc send(cmd: string) = >> pgo_runner_temp.nim
echo     echo "[Runner] > " ^& cmd >> pgo_runner_temp.nim
echo     inp.writeLine(cmd) >> pgo_runner_temp.nim
echo     inp.flush() >> pgo_runner_temp.nim
echo. >> pgo_runner_temp.nim
echo   proc wait(target: string) = >> pgo_runner_temp.nim
echo     while true: >> pgo_runner_temp.nim
echo       if outp.atEnd: break >> pgo_runner_temp.nim
echo       let line = outp.readLine() >> pgo_runner_temp.nim
echo       echo line >> pgo_runner_temp.nim
echo       if line.contains(target): break >> pgo_runner_temp.nim
echo. >> pgo_runner_temp.nim
echo   # Workload >> pgo_runner_temp.nim
echo   send("uci") >> pgo_runner_temp.nim
echo   wait("uciok") >> pgo_runner_temp.nim
echo   send("perft 5") >> pgo_runner_temp.nim
echo   wait("Nodes") >> pgo_runner_temp.nim
echo   send("perft 6") >> pgo_runner_temp.nim
echo   wait("Nodes") >> pgo_runner_temp.nim
echo   send("perft 7") >> pgo_runner_temp.nim
echo   wait("Nodes") >> pgo_runner_temp.nim
echo   send("bench") >> pgo_runner_temp.nim
echo   wait("BENCHMARK RESULTS") >> pgo_runner_temp.nim
echo   send("go movetime 30000") >> pgo_runner_temp.nim
echo   wait("bestmove") >> pgo_runner_temp.nim
echo   send("quit") >> pgo_runner_temp.nim
echo   echo "[Runner] Waiting for engine to exit..." >> pgo_runner_temp.nim
echo   p.inputStream.close() >> pgo_runner_temp.nim
echo   while not p.outputStream.atEnd: >> pgo_runner_temp.nim
echo     try: >> pgo_runner_temp.nim
echo       echo p.outputStream.readLine() >> pgo_runner_temp.nim
echo     except: break >> pgo_runner_temp.nim
echo   discard p.waitForExit() >> pgo_runner_temp.nim
echo   p.close() >> pgo_runner_temp.nim
echo. >> pgo_runner_temp.nim
echo main() >> pgo_runner_temp.nim

echo.
echo [Stage 3] Running Workload...
rem Set env var to ensure profile is written clearly (optional but safer)
set LLVM_PROFILE_FILE=default_%%m.profraw
rem Compile and run the runner
nim c -r --cc:clang -d:danger --passC:"-O3" pgo_runner_temp.nim
if errorlevel 1 goto ERROR

echo.
echo [Stage 4] Merging Profiles...
llvm-profdata merge -o default.profdata *.profraw
if errorlevel 1 goto ERROR

echo.
echo [Stage 5] Final Optimized Build...
nim c --cc:clang -d:release -d:danger -d:simd %AVX_FLAGS% --mm:arc --define:useMalloc --styleCheck:hint --panics:on --opt:speed --passC:"-O3 -ffast-math -fstrict-aliasing -funroll-loops -fomit-frame-pointer -flto -fno-plt" --passL:"-O3 -flto -fuse-ld=lld" --passC:-march=native --passC:"-fprofile-use -fprofile-correction" --passL:-fprofile-use -o:Gyatso.exe Gyatso/src/main.nim
if errorlevel 1 goto ERROR

echo.
echo [Cleanup] Removing temporary files...
del *.profraw
del default.profdata
del pgo_runner_temp.*

echo.
echo === PGO Build Complete ===
pause
exit /b

:ERROR
echo.
echo !!! BUILD FAILED !!!
pause
exit /b
