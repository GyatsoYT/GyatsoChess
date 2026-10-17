EXE      ?= Gyatso
EVALFILE ?= Gyatso/Net/GyatsoNet1024x16x32.bin
SRC       = Gyatso/src/main.nim
DATAGEN_SRC = Gyatso/src/datagen.nim
NIM      ?= nim
NIM_CC   ?= clang
NETFILE   = Gyatso/Net/GyatsoNet1024x16x32.bin
DATAGEN  ?= GyatsoDatagen

ifeq ($(OS),Windows_NT)
    DETECTED_OS := Windows
    EXE_SUFFIX  := .exe
    NO_PLT      :=
    LD_LLD      := -fuse-ld=lld
else
    DETECTED_OS := $(shell uname -s 2>/dev/null || echo Unix)
    EXE_SUFFIX  :=
    NO_PLT      := -fno-plt
    LD_LLD      := -fuse-ld=lld
endif

HOST_CPU_MACROS := $(shell echo | $(NIM_CC) -march=native -dM -E -x c - 2>&1)
ARCH_DEFS :=
ISA_CFLAGS :=

ifneq ($(strip $(and $(findstring __AVX512F__,$(HOST_CPU_MACROS)),$(findstring __AVX512BW__,$(HOST_CPU_MACROS)))),)
    ARCH_DEFS += -d:avx512 -d:simd
    ISA_CFLAGS += -mavx512f -mavx512bw
ifneq ($(findstring __AVX512VNNI__,$(HOST_CPU_MACROS)),)
    ARCH_DEFS += -d:avx512vnni
    ISA_CFLAGS += -mavx512vnni
endif
else ifneq ($(findstring __AVXVNNI__,$(HOST_CPU_MACROS)),)
    ARCH_DEFS += -d:avx2 -d:avxvnni -d:simd
    ISA_CFLAGS += -mavx2 -mavxvnni
else ifneq ($(findstring __AVX2__,$(HOST_CPU_MACROS)),)
    ARCH_DEFS += -d:avx2 -d:simd
    ISA_CFLAGS += -mavx2
else ifneq ($(findstring __ARM_NEON,$(HOST_CPU_MACROS)),)
    ARCH_DEFS += -d:neon -d:simd
ifneq ($(findstring __ARM_FEATURE_DOTPROD,$(HOST_CPU_MACROS)),)
    ARCH_DEFS += -d:neonDotProd
endif
ifneq ($(findstring __aarch64__,$(HOST_CPU_MACROS)),)
    ARCH_DEFS += -d:arm64
endif
endif

ifneq ($(findstring __BMI2__,$(HOST_CPU_MACROS)),)
    ARCH_DEFS += -d:bmi2
    ISA_CFLAGS += -mbmi2
endif

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
         $(ISA_CFLAGS) $(NO_PLT)

LDFLAGS = -O3 -flto $(LD_LLD)

.PHONY: all build datagen-stats clean help check-deps

all: build

check-deps:
	@$(NIM) --version || (echo "ERROR: nim not found." && exit 1)
	@$(NIM_CC) --version || (echo "ERROR: $(NIM_CC) not found." && exit 1)
	@echo "[Makefile] Native CPU feature selection: $(ARCH_DEFS) $(ISA_CFLAGS)"

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

datagen-stats: check-deps
	$(NIM) c \
		$(NIM_FLAGS) \
		-d:nnueStats \
		--passC:"$(CFLAGS)" \
		--passL:"$(LDFLAGS)" \
		-o:$(DATAGEN)$(EXE_SUFFIX) \
		$(DATAGEN_SRC)
	@echo "[Makefile] Done: $(DATAGEN)$(EXE_SUFFIX) (NNUE sparsity statistics enabled)"

clean:
	@echo "[Makefile] Cleaning ..."
	rm -f "$(EXE)" "$(EXE).exe"
	rm -rf nimcache

help:
	@echo "Usage:"
	@echo "  make EXE=GyatsoChess-ABCDEFGH"
	@echo "  make EXE=GyatsoChess-ABCDEFGH EVALFILE=/path/to/net.bin"
	@echo "  make datagen-stats DATAGEN=GyatsoDatagen"
	@echo ""
	@echo "Variables:"
	@echo "  EXE       Output binary name           (default: Gyatso)"
	@echo "  EVALFILE  NNUE network file to embed   (default: $(NETFILE))"
