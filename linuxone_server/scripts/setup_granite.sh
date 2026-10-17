#!/usr/bin/env bash
# STEP 2 (run on the LinuxONE VM): build llama.cpp for s390x and serve Granite.
# Do STEP 1 (scripts/granite_convert_on_mac.sh) first to make the model file.
#
# Why these choices (8 GB RAM VM):
#   - Granite 3 8B needs ~16 GB at FP16, so it doesn't fit. 2B at Q4_K_M is ~1.5 GB.
#   - s390x is big-endian: the Mac converts to a big-endian F16 GGUF, and this
#     script quantises it natively here with llama-quantize (correct byte order).
#   - llama-server exposes an OpenAI-compatible /v1/chat/completions endpoint,
#     which is what pipeline/reasoning.py calls.
#
# Run as a normal user on the VM:  bash scripts/setup_granite.sh
# Re-running is safe; finished steps are skipped.
set -euo pipefail

WORK="${GRANITE_HOME:-$HOME/granite}"
F16="$WORK/granite-3.3-2b-instruct-be.f16.gguf"     # from the Mac
QUANT="${GRANITE_QUANT:-Q4_K_M}"                      # Q4_K_M ~1.5 GB, faster; Q8_0 ~2.7 GB
GGUF="$WORK/granite-3.3-2b-instruct-be.$QUANT.gguf"

mkdir -p "$WORK"
cd "$WORK"

echo "== 1/4 System packages"
if command -v dnf >/dev/null; then
  sudo dnf install -y git cmake gcc gcc-c++ make openblas-devel pkgconf-pkg-config tmux
elif command -v apt-get >/dev/null; then
  sudo apt-get update
  sudo apt-get install -y git cmake build-essential libopenblas-dev pkg-config tmux
elif command -v zypper >/dev/null; then
  sudo zypper install -y git cmake gcc gcc-c++ make openblas-devel pkg-config tmux
fi

echo "== 2/4 Build llama.cpp for s390x (VXE SIMD is on by default)"
if [ ! -x llama.cpp/build/bin/llama-server ] || [ ! -x llama.cpp/build/bin/llama-quantize ]; then
  [ -d llama.cpp ] || git clone --depth 1 https://github.com/ggml-org/llama.cpp
  # GGML_NATIVE=OFF + -march=z16: on a z17 / LinuxONE 5, native detection asks
  # for -march=arch15, which needs GCC 15+. z16 code runs fine on z17 and GCC 13
  # supports it. Vector (VXE) SIMD stays on via GGML_VXE (default ON).
  # -j 2 keeps the compile within 8 GB of RAM.
  cmake -S llama.cpp -B llama.cpp/build -DCMAKE_BUILD_TYPE=Release \
        -DGGML_NATIVE=OFF -DCMAKE_C_FLAGS="-march=z16" -DCMAKE_CXX_FLAGS="-march=z16" \
        -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS -DLLAMA_CURL=OFF
  cmake --build llama.cpp/build --config Release -j 2 --target llama-server llama-quantize llama-cli
fi

echo "== 3/4 Quantise the big-endian F16 model to $QUANT on this machine"
if [ ! -f "$GGUF" ]; then
  if [ ! -f "$F16" ]; then
    echo "Missing $F16"
    echo "Run scripts/granite_convert_on_mac.sh on your Mac, then scp the .f16.gguf into $WORK/"
    exit 1
  fi
  llama.cpp/build/bin/llama-quantize "$F16" "$GGUF" "$QUANT"
fi
ls -lh "$GGUF"

echo "== 4/4 Done"
cat <<EOF

Start Granite (keep it running, e.g. in tmux or as a service):

  $WORK/llama.cpp/build/bin/llama-server -m $GGUF \\
      --host 127.0.0.1 --port 8081 -c 2048 -t \$(nproc) --jinja

Then start the PulsePal API with Granite switched on:

  export GRANITE_URL=http://127.0.0.1:8081/v1/chat/completions
  uvicorn main:app --host 0.0.0.0 --port 8000

Check it end to end:

  python3 scripts/check_granite.py
EOF
