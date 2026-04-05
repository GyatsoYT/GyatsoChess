#!/bin/sh

echo "Installing nimsimd dependency..."
nimble install -y nimsimd

echo "GyatsoChess Build System"
echo "========================"
echo "1. Normal Build (Fast, Native)"
echo "2. PGO Build (Slow, Maximum Performance)"
echo
printf "Select build type (1/2): "
read choice

echo
echo "Select Target Architecture Extensions:"
echo "1. Default (auto-detect: NEON on ARM64, scalar elsewhere)"
echo "2. AVX2   (x86-64 with AVX2 support)"
echo "3. AVX512 (x86-64 with AVX-512 support)"
echo "4. NEON   (explicit ARM64 / Apple Silicon)"
printf "Select extensions (1/2/3/4): "
read arch_choice

AVX_FLAGS=""
if [ "$arch_choice" = "2" ]; then
    AVX_FLAGS="-d:avx2"
elif [ "$arch_choice" = "3" ]; then
    AVX_FLAGS="-d:avx2 -d:avx512"
elif [ "$arch_choice" = "4" ]; then
    AVX_FLAGS="-d:neon"
fi

if [ "$choice" = "1" ]; then
    echo
    echo "=== Normal Build ==="
    nim c -d:release -d:danger -d:simd $AVX_FLAGS --cc:clang --mm:arc --define:useMalloc --styleCheck:hint --panics:on --opt:speed --passC:"-O3 -ffast-math -fstrict-aliasing -funroll-loops -fomit-frame-pointer -flto -fno-plt" --passL:"-O3 -flto -fuse-ld=lld" --passC:-march=native -o:Gyatso Gyatso/src/main.nim
    echo "Compilation finished."
    exit 0
elif [ "$choice" = "2" ]; then
    echo
    echo "=== PGO Build Pipeline ==="
    echo
    echo "[Stage 1] Instrumenting..."
    # Build with profile generation
    nim c --cc:clang -d:release -d:danger -d:simd $AVX_FLAGS --mm:arc --define:useMalloc --styleCheck:hint --panics:on --opt:speed --passC:"-O3 -ffast-math -fstrict-aliasing -funroll-loops -fomit-frame-pointer -flto -fno-plt" --passL:"-O3 -flto -fuse-ld=lld" --passC:-march=native --passC:-fprofile-generate --passL:-fprofile-generate -o:Gyatso.out Gyatso/src/main.nim
    if [ $? -ne 0 ]; then
        echo "Build failed!"
        exit 1
    fi

    echo
    echo "[Stage 2] Generating Workload Runner..."
    # Generate Nim runner script
    cat << EOF > pgo_runner_temp.nim
import osproc, streams, strutils, os

proc main() =
  echo "[Runner] Starting Gyatso..."
  var p = startProcess("./Gyatso.out", options={poUsePath, poStdErrToStdOut})
  var inp = p.inputStream
  var outp = p.outputStream

  proc send(cmd: string) =
    echo "[Runner] > " & cmd
    inp.writeLine(cmd)
    inp.flush()

  proc wait(target: string) =
    while true:
      if outp.atEnd: break
      let line = outp.readLine()
      echo line
      if line.contains(target): break

  # Workload
  send("uci")
  wait("uciok")
  send("perft 5")
  wait("Nodes")
  send("perft 6")
  wait("Nodes")
  send("go depth 18")
  wait("bestmove")
  send("quit")
  echo "[Runner] Waiting for engine to exit..."
  p.inputStream.close()
  while not p.outputStream.atEnd:
    try:
      echo p.outputStream.readLine()
    except: break
  discard p.waitForExit()
  p.close()
  echo "Workload done."

main()
EOF

    echo
    echo "[Stage 3] Running Workload..."
    # Compile and run the runner
    nim c -r -d:danger --passC:"-O3" pgo_runner_temp.nim
    if [ $? -ne 0 ]; then
        echo "Workload failed!"
        exit 1
    fi

    echo
    echo "[Stage 4] Merging Profiles..."
    llvm-profdata merge -o default.profdata *.profraw
    if [ $? -ne 0 ]; then
        echo "Merging failed!"
        exit 1
    fi

    echo
    echo "[Stage 5] Final Optimized Build..."
    nim c --cc:clang -d:release -d:danger -d:simd $AVX_FLAGS --mm:arc --define:useMalloc --styleCheck:hint --panics:on --opt:speed --passC:"-O3 -ffast-math -fstrict-aliasing -funroll-loops -fomit-frame-pointer -flto -fno-plt" --passL:"-O3 -flto -fuse-ld=lld" --passC:-march=native --passC:"-fprofile-use -fprofile-correction" --passL:-fprofile-use -o:Gyatso.out Gyatso/src/main.nim
    if [ $? -ne 0 ]; then
        echo "Final build failed!"
        exit 1
    fi

    echo
    echo "[Cleanup] Removing temporary files..."
    rm *.profraw default.profdata pgo_runner_temp.nim pgo_runner_temp

    echo
    echo "=== PGO Build Complete ==="
    exit 0
else
    echo "Invalid choice."
    exit 1
fi
