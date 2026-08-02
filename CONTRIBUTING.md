# Gyatso Chess — Contributor Guide

Thank you for your interest in contributing to **Gyatso Chess**! Whether you want to improve the codebase or donate CPU cores for testing, your help is greatly appreciated.

---

## Table of Contents

- [Code Contribution Guide](#code-contribution-guide)
  - [Getting Started](#getting-started)
  - [Development Workflow](#development-workflow)
  - [Coding Standards & Nim Style](#coding-standards--nim-style)
  - [Benchmarking & Testing](#benchmarking--testing)
  - [Submitting a Pull Request](#submitting-a-pull-request)
- [OpenBench Hardware Contributor Guide](#openbench-hardware-contributor-guide)
  - [Before You Start — Core Donation Rules](#before-you-start--core-donation-rules)
  - [MSYS2 Setup (Windows)](#msys2-setup-windows)
  - [WSL Setup (Windows)](#wsl-setup-windows)
  - [Native Linux Setup](#native-linux-setup)
  - [Running the Worker](#running-the-worker)
  - [P/E Core Pinning](#pe-core-pinning)
  - [Troubleshooting](#troubleshooting)

---

# Code Contribution Guide

## Getting Started

1. **Prerequisites:**
   - [Nim Compiler](https://nim-lang.org/install.html) (1.6+)
   - Clang C compiler & LLD linker
   - Git & Python 3

2. **Fork and Clone:**
   ```bash
   git clone https://github.com/YourUsername/GyatsoChess.git
   cd GyatsoChess
   ```

3. **Install Dependencies:**
   ```bash
   nimble install nimsimd -y
   ```

---

## Development Workflow

1. Create a feature branch:
   ```bash
   git checkout -b feature/my-feature-name
   ```
2. Build locally:
   - On Windows: run `compile.bat`
   - On Linux/macOS: run `./compile.sh` or `make`
3. Run internal tests:
   ```bash
   # Run benchmark
   ./Gyatso bench

   # Run move generator test / perft
   ./Gyatso perft 5
   ```

---

## Coding Standards & Nim Style

- Follow standard **Nim style conventions**: `camelCase` for variables and procedures, `PascalCase` for types, `UPPER_SNAKE` for constants.
- Prefer explicit typing where appropriate to maintain performance clarity.
- Keep performance-critical procedures marked `{.inline.}` or `{.gcsafe.}` as needed.
- Avoid dynamic allocations inside the search tree loop — reuse search stack buffers or thread-local variables.

---

## Benchmarking & Testing

Any change to search, move ordering, or evaluation **must** be validated:

1. **Bench Comparison:**
   Run `bench` before and after your changes to verify node count stability or measure node throughput.
   ```bash
   ./Gyatso bench
   ```
2. **SPRT Testing:**
   For search/eval patches, run local SPRT (Sequential Probability Ratio Test) matches using tools like `fastchess` or `cutechess-cli` against the base version to prove Elo gains before opening a PR.

---

## Submitting a Pull Request

1. **Commit Messages:** Write clear, concise commit messages explaining *what* and *why*.
2. **Pull Request Description:**
   - Clearly describe the proposed change.
   - Include `bench` results (nodes & NPS before vs. after).
   - Attach local SPRT test results showing Elo gain if applicable.
3. **Review:** Maintainers will review your PR and provide feedback.

---

# OpenBench Hardware Contributor Guide

Help test Gyatso Chess by donating CPU cores to the OpenBench testing server at **[gyatsoyt.pythonanywhere.com](http://gyatsoyt.pythonanywhere.com)**.

---

## Before You Start — Core Donation Rules

- **Donate P cores only.** If your CPU has both P cores and E cores (Intel 12th gen+), only run the worker on P cores. Mixed P+E testing produces invalid SPRT results. See [P/E Core Pinning](#pe-core-pinning) below.
- **Minimum 2 cores.** Less than 2 cores is not useful for fast SPRT testing.
- **Keep the worker running while plugged in.** Laptop throttling under battery degrades test results.
- **One worker per machine.** Don't run multiple workers on the same physical machine.

---

## MSYS2 Setup (Windows)

MSYS2 is the recommended Windows environment as it provides the Unix build toolchain required by fastchess and the OpenBench client.

### Step 1 — Install MSYS2

Download and install from **[https://www.msys2.org](https://www.msys2.org)**.

Open **MSYS2 UCRT64** from the Start menu (specifically UCRT64).

### Step 2 — Install build tools and Nim

```bash
pacman -S mingw-w64-ucrt-x86_64-gcc \
          mingw-w64-ucrt-x86_64-clang \
          mingw-w64-ucrt-x86_64-lld \
          mingw-w64-ucrt-x86_64-nim \
          mingw-w64-ucrt-x86_64-nimble \
          mingw-w64-ucrt-x86_64-python-psutil \
          make git
```

### Step 3 — Verify Nim and Clang

```bash
nim --version
clang --version
ld.lld --version
```

If `clang` and `lld` versions don't match, upgrade `lld` and force `/ucrt64/bin` onto `PATH`:

```bash
pacman -S mingw-w64-ucrt-x86_64-lld
export PATH="/ucrt64/bin:$PATH"
echo 'export PATH="/ucrt64/bin:$PATH"' >> ~/.bashrc
```

### Step 4 — Install nimsimd

```bash
nimble install nimsimd -y
```

### Step 5 — Set up Python venv for the OB client

```bash
/ucrt64/bin/python3.14 -m venv ~/obenv
source ~/obenv/bin/activate
pip install requests py-cpuinfo
ln -s /ucrt64/lib/python3.14/site-packages/psutil \
      ~/obenv/lib/python3.14/site-packages/psutil
ln -s /ucrt64/lib/python3.14/site-packages/psutil-7.2.2.dist-info \
      ~/obenv/lib/python3.14/site-packages/psutil-7.2.2.dist-info
python -c "import psutil, requests, cpuinfo; print('OK')"
```

### Step 6 — Register on the OB server

Go to **[http://gyatsoyt.pythonanywhere.com/register/](http://gyatsoyt.pythonanywhere.com/register/)** and create an account. Message **Gyatso** on Discord to enable your account.

### Step 7 — Clone the OB client and Run

```bash
cd ~
git clone https://github.com/GyatsoYT/GyatsoBench
source ~/obenv/bin/activate
cd ~/GyatsoBench
python client/client.py \
  -S http://gyatsoyt.pythonanywhere.com \
  -U YourUsername \
  -P "YourPassword" \
  -T <cores> \
  -N 1
```

Replace `<cores>` with your available P core count (e.g. `-T 8`).

---

## WSL Setup (Windows)

### Step 1 — Install WSL & Dependencies

```powershell
wsl --install
```
Restart if prompted, then open **Ubuntu** and run:

```bash
sudo apt update
sudo apt install -y git make curl clang llvm lld g++ \
                   python3 python3-pip python3-requests \
                   python3-psutil build-essential
```

### Step 2 — Install Nim & Dependencies

```bash
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
echo 'export PATH=$HOME/.nimble/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
nimble install nimsimd -y
pip3 install py-cpuinfo --break-system-packages
```

### Step 3 — Clone and Run Worker

> ⚠️ **Important:** Always run from `~/GyatsoBench` in the Linux filesystem. Do **not** run inside `/mnt/c/` or `/mnt/d/`.

```bash
cd ~
git clone https://github.com/GyatsoYT/GyatsoBench
cd ~/GyatsoBench
python3 client/client.py \
  -S http://gyatsoyt.pythonanywhere.com \
  -U YourUsername \
  -P "YourPassword" \
  -T <cores> \
  -N 1
```

---

## Native Linux Setup

### Step 1 — Install Dependencies

- **Debian / Ubuntu:**
  ```bash
  sudo apt update && sudo apt install -y git make curl clang llvm lld g++ python3 python3-pip python3-requests python3-psutil build-essential
  ```
- **Arch Linux:**
  ```bash
  sudo pacman -S git make clang lld python python-requests python-psutil
  ```
- **Fedora:**
  ```bash
  sudo dnf install git make clang lld python3 python3-requests python3-psutil
  ```

### Step 2 — Nim & OB Client Setup

```bash
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
source ~/.bashrc
nimble install nimsimd -y
pip3 install py-cpuinfo --break-system-packages

cd ~
git clone https://github.com/GyatsoYT/GyatsoBench
cd ~/GyatsoBench
python3 client/client.py -S http://gyatsoyt.pythonanywhere.com -U YourUsername -P "YourPassword" -T <cores> -N 1
```

---

## P/E Core Pinning

On CPUs with mixed Performance and Efficiency cores (Intel 12th gen and newer):

### Linux / WSL (`taskset`)

```bash
# Pin to cores 0-7 (P-cores)
taskset -c 0-7 python3 client/client.py \
  -S http://gyatsoyt.pythonanywhere.com \
  -U YourUsername -P "YourPassword" -T 8 -N 1
```

### Windows (Task Manager / PowerShell)

In PowerShell:
```powershell
# Set affinity mask for P-cores (e.g. 0xFF for cores 0-7)
$p = Get-Process python
$p.ProcessorAffinity = 0xFF
```

---

## Troubleshooting

| Issue | Resolution |
| :--- | :--- |
| `No module named requests` | Activate your venv first (`source ~/obenv/bin/activate`). |
| `ld.lld: error: Invalid record` | Clang/LLD version mismatch. Update `lld` via `pacman -S mingw-w64-ucrt-x86_64-lld`. |
| `GyatsoChess \| Missing ['nim']` | Nim is missing from PATH. Install Nim or check environment variables. |
| `shutil.move` permission error (WSL) | Do not run from `/mnt/c/` or `/mnt/d/`. Clone and run inside `~/GyatsoBench`. |
| `Bench Mismatch` | Node count doesn't match engine binary. Re-run `./Gyatso bench` to confirm output. |
| Stuck on "Requesting Workload" | Normal behavior when no SPRT tests are currently active on the server. |

---

*Engine Repository:* [https://github.com/GyatsoYT/GyatsoChess](https://github.com/GyatsoYT/GyatsoChess)
