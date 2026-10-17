#!/usr/bin/env bash
# STEP 1 (run on your Mac): download Granite 3.3 2B Instruct and convert it to a
# BIG-ENDIAN F16 GGUF for LinuxONE (s390x is big-endian; ~5 GB output).
# Quantise on the VM afterwards with llama-quantize (setup_granite.sh): converting
# straight to q8_0 + --bigendian here produced a broken model (only commas).
#
#   bash linuxone_server/scripts/granite_convert_on_mac.sh
#   scp ~/granite/granite-3.3-2b-instruct-be.f16.gguf <user>@<linuxone-ip>:~/granite/
set -euo pipefail

WORK="${GRANITE_HOME:-$HOME/granite}"
MODEL_ID="ibm-granite/granite-3.3-2b-instruct"
MODEL_DIR="$WORK/granite-3.3-2b-instruct"
GGUF="$WORK/granite-3.3-2b-instruct-be.f16.gguf"

mkdir -p "$WORK" && cd "$WORK"
[ -d llama.cpp ] || git clone --depth 1 https://github.com/ggml-org/llama.cpp

[ -d venv ] || python3 -m venv venv
# shellcheck disable=SC1091
source venv/bin/activate
pip install -q --upgrade pip
pip install -q -r llama.cpp/requirements/requirements-convert_hf_to_gguf.txt huggingface_hub

python3 - <<PY
from huggingface_hub import snapshot_download
snapshot_download("$MODEL_ID", local_dir="$MODEL_DIR",
                  allow_patterns=["*.json", "*.safetensors", "*.txt", "*.model", "*.tiktoken"])
PY

python3 llama.cpp/convert_hf_to_gguf.py "$MODEL_DIR" --outfile "$GGUF" --outtype f16 --bigendian
deactivate
ls -lh "$GGUF"
echo
echo "Now copy it to the VM:"
echo "  ssh <user>@<linuxone-ip> 'mkdir -p ~/granite'"
echo "  scp $GGUF <user>@<linuxone-ip>:~/granite/"
