EXE      ?= Gyatso
EVALFILE ?= Gyatso/Net/GyatsoNet512HM.bin
SRC       = Gyatso/src/main.nim
NIM      ?= nim
NETFILE   = Gyatso/Net/GyatsoNet512HM.bin

# Detect OS
ifeq ($(OS),Windows_NT)
    DETECTED_OS := Windows
    EXE_SUFFIX  := .exe
    NO_PLT      :=
    LD_LLD      :=
else
    DETECTED_OS := Linux
    EXE_SUFFIX  :=
    NO_PLT      := -fno-plt
    LD_LLD      := -fuse-ld=lld
endif

ARCH_DEFS = -d:avx2 -d:bmi2 -d:simd

NIM_FLAGS = \
	--cc:clang \
    --mm:arc \
    --opt:speed \
    -d:danger \
    $(ARCH_DEFS) \
    --define:useMalloc \
    --panics:on \
    --styleCheck:hint

CFLAGS = -O3 -ffast-math -fstrict-aliasing -funroll-loops \
         -fomit-frame-pointer -flto -march=native \
         -mavx2 -mbmi2 $(NO_PLT)

LDFLAGS = -O3 -flto -fuse-ld=lld

.PHONY: all build clean help check-deps

all: build

check-deps:
ifeq ($(DETECTED_OS),Linux)
	@which lld > /dev/null 2>&1 || (echo "ERROR: lld not found. Install LLVM (includes lld) from https://releases.llvm.org/" && exit 1)
endif
	@$(NIM) --version > /dev/null 2>&1 || (echo "ERROR: nim not found." && exit 1)

build: check-deps
ifdef EVALFILE
ifneq ($(EVALFILE),$(NETFILE))
	@echo "[Makefile] Copying custom EVALFILE: $(EVALFILE) -> $(NETFILE)"
	cp "$(EVALFILE)" "$(NETFILE)"
endif
endif
	@echo "[Makefile] Building $(EXE) on $(DETECTED_OS)..."
	$(NIM) c \
		$(NIM_FLAGS) \
		--passC:"$(CFLAGS)" \
		--passL:"$(LDFLAGS)" \
		-o:$(EXE)$(EXE_SUFFIX) \
		$(SRC)
	@echo "[Makefile] Done: $(EXE)$(EXE_SUFFIX)"

clean:
	@echo "[Makefile] Cleaning ..."
	rm -f "$(EXE)" "$(EXE).exe"
	rm -rf nimcache

help:
	@echo "Usage:"
	@echo "  make EXE=GyatsoChess-ABCDEFGH"
	@echo "  make EXE=GyatsoChess-ABCDEFGH EVALFILE=/path/to/net.bin"
	@echo ""
	@echo "Variables:"
	@echo "  EXE       Output binary name           (default: Gyatso)"
	@echo "  EVALFILE  NNUE network file to embed   (default: $(NETFILE))"