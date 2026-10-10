EXE      ?= Gyatso
EVALFILE ?= Gyatso/Net/GyatsoNet1024x16x32.bin
SRC       = Gyatso/src/main.nim
NIM      ?= nim
NETFILE   = Gyatso/Net/GyatsoNet1024x16x32.bin

ifeq ($(OS),Windows_NT)
    ifeq ($(MSYSTEM),)
        DETECTED_OS := Windows
        EXE_SUFFIX  := .exe
        NO_PLT      :=
        LD_LLD      := -fuse-ld=lld
        NULL_DEV    := NUL
        FILE_COPY   := copy /Y
    else
        DETECTED_OS := Linux
        EXE_SUFFIX  :=
        NO_PLT      := -fno-plt
        LD_LLD      := -fuse-ld=lld
        NULL_DEV    := /dev/null
        FILE_COPY   := cp
    endif
else
    DETECTED_OS := Linux
    EXE_SUFFIX  :=
    NO_PLT      := -fno-plt
    LD_LLD      := -fuse-ld=lld
    NULL_DEV    := /dev/null
    FILE_COPY   := cp
endif

CLANG ?= clang
CPU_DETECT_FLAGS ?= -march=native
ifeq ($(DETECTED_OS),Windows)
    CPU_FEATURES :=
else
    CPU_FEATURES := $(shell printf '\n' | $(CLANG) $(CPU_DETECT_FLAGS) -dM -E -x c - 2>/dev/null)
endif

DETECTED_ARCH_DEFS :=
ifneq (,$(findstring __AVX512F__,$(CPU_FEATURES)))
ifneq (,$(findstring __AVX512BW__,$(CPU_FEATURES)))
    DETECTED_ARCH_DEFS += -d:simd -d:avx2 -d:avx512
    ifneq (,$(findstring __AVX512VNNI__,$(CPU_FEATURES)))
        DETECTED_ARCH_DEFS += -d:avx512vnni
    endif
else ifneq (,$(findstring __AVX2__,$(CPU_FEATURES)))
    DETECTED_ARCH_DEFS += -d:simd -d:avx2
    ifneq (,$(findstring __AVXVNNI__,$(CPU_FEATURES)))
        DETECTED_ARCH_DEFS += -d:avxvnni
    endif
endif
else ifneq (,$(findstring __AVX2__,$(CPU_FEATURES)))
    DETECTED_ARCH_DEFS += -d:simd -d:avx2
    ifneq (,$(findstring __AVXVNNI__,$(CPU_FEATURES)))
        DETECTED_ARCH_DEFS += -d:avxvnni
    endif
else ifneq (,$(findstring __aarch64__,$(CPU_FEATURES)))
    DETECTED_ARCH_DEFS += -d:simd -d:neon
    ifneq (,$(findstring __ARM_FEATURE_DOTPROD,$(CPU_FEATURES)))
        DETECTED_ARCH_DEFS += -d:neonDotprod
    endif
endif

ifneq (,$(findstring __BMI2__,$(CPU_FEATURES)))
    DETECTED_ARCH_DEFS += -d:bmi2
endif

ARCH_DEFS ?= $(strip $(DETECTED_ARCH_DEFS))
ARCH_CFLAGS ?= $(CPU_DETECT_FLAGS)

NIM_FLAGS = \
	--cc:clang \
    --mm:arc \
    --opt:speed \
    -d:release \
    -d:danger \
    $(ARCH_DEFS) \
    --define:useMalloc \
    --panics:on \
    --styleCheck:hint

CFLAGS = -O3 -ffast-math -fstrict-aliasing -funroll-loops \
         -fomit-frame-pointer -flto $(ARCH_CFLAGS) $(NO_PLT)

LDFLAGS = -O3 -flto $(LD_LLD)

.PHONY: all build clean help check-deps

all: build

check-deps:
ifeq ($(DETECTED_OS),Linux)
	@which lld > $(NULL_DEV) 2>&1 || (echo "ERROR: lld not found. Install LLVM (includes lld) from https://releases.llvm.org/" && exit 1)
endif
	@$(NIM) --version > $(NULL_DEV) 2>&1 || (echo "ERROR: nim not found." && exit 1)
	@$(CLANG) --version > $(NULL_DEV) 2>&1 || (echo "ERROR: clang not found." && exit 1)

build: check-deps
ifdef EVALFILE
ifneq ($(EVALFILE),$(NETFILE))
	@echo "[Makefile] Copying custom EVALFILE: $(EVALFILE) -> $(NETFILE)"
	$(FILE_COPY) "$(EVALFILE)" "$(NETFILE)"
endif
endif
ifeq ($(DETECTED_OS),Windows)
	powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$$detectFlags = '$(CPU_DETECT_FLAGS)'.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries); $$featureText = (& '$(CLANG)' @detectFlags -dM -E -x c NUL) -join [Environment]::NewLine; $$defs = @(); if ('$(ARCH_DEFS)' -ne '') { $$defs = '$(ARCH_DEFS)'.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries) } else { if ($$featureText.Contains('__AVX512F__') -and $$featureText.Contains('__AVX512BW__')) { $$defs += @('-d:simd', '-d:avx2', '-d:avx512'); if ($$featureText.Contains('__AVX512VNNI__')) { $$defs += '-d:avx512vnni' } } elseif ($$featureText.Contains('__AVX2__')) { $$defs += @('-d:simd', '-d:avx2'); if ($$featureText.Contains('__AVXVNNI__')) { $$defs += '-d:avxvnni' } } elseif ($$featureText.Contains('__aarch64__')) { $$defs += @('-d:simd', '-d:neon'); if ($$featureText.Contains('__ARM_FEATURE_DOTPROD')) { $$defs += '-d:neonDotprod' } }; if ($$featureText.Contains('__BMI2__')) { $$defs += '-d:bmi2' } }; $$nimArgs = @('c', '--cc:clang', '--mm:arc', '--opt:speed', '-d:release', '-d:danger') + $$defs + @('--define:useMalloc', '--panics:on', '--styleCheck:hint', '--passC:$(CFLAGS)', '--passL:$(LDFLAGS)', '-o:$(EXE)$(EXE_SUFFIX)', '$(SRC)'); Write-Output ('[Makefile] Building $(EXE) on $(DETECTED_OS)...'); Write-Output ('[Makefile] SIMD defines: ' + ($$defs -join ' ')); Write-Output ('[Makefile] C target flags: $(ARCH_CFLAGS)'); & '$(NIM)' @nimArgs; if ($$LASTEXITCODE -eq 0) { Write-Output ('[Makefile] Done: $(EXE)$(EXE_SUFFIX)') }; exit $$LASTEXITCODE"
else
	@echo "[Makefile] Building $(EXE) on $(DETECTED_OS)..."
	@echo "[Makefile] SIMD defines: $(ARCH_DEFS)"
	@echo "[Makefile] C target flags: $(ARCH_CFLAGS)"
	$(NIM) c \
		$(NIM_FLAGS) \
		--passC:"$(CFLAGS)" \
		--passL:"$(LDFLAGS)" \
		-o:$(EXE)$(EXE_SUFFIX) \
		$(SRC)
	@echo "[Makefile] Done: $(EXE)$(EXE_SUFFIX)"
endif

clean:
	@echo "[Makefile] Cleaning ..."
ifeq ($(DETECTED_OS),Windows)
	@if exist "$(EXE)" del /F /Q "$(EXE)"
	@if exist "$(EXE).exe" del /F /Q "$(EXE).exe"
	@if exist nimcache rmdir /S /Q nimcache
else
	rm -f "$(EXE)" "$(EXE).exe"
	rm -rf nimcache
endif

help:
	@echo "Usage:"
	@echo "  make EXE=GyatsoChess-ABCDEFGH"
	@echo "  make EXE=GyatsoChess-ABCDEFGH EVALFILE=/path/to/net.bin"
	@echo ""
	@echo "Variables:"
	@echo "  EXE       Output binary name           (default: Gyatso)"
	@echo "  EVALFILE  NNUE network file to embed   (default: $(NETFILE))"
