#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BASE_MODEL="${BASE_MODEL:-runwayml/stable-diffusion-v1-5}"
LCM_LORA_MODEL="${LCM_LORA_MODEL:-latent-consistency/lcm-lora-sdv1-5}"
ARTIFACT_NAME="${ARTIFACT_NAME:-sd15_lcm_coreml_v1}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/build/lcm}"
ZIP_OUT="${ZIP_OUT:-$WORK_DIR/${ARTIFACT_NAME}.zip}"
LORA_SCALE="${LORA_SCALE:-1.0}"
DTYPE="${DTYPE:-float16}"
CHUNK_UNET="${CHUNK_UNET:-1}"
QUANTIZE_NBITS="${QUANTIZE_NBITS:-}"
SKIP_ENV_SETUP="${SKIP_ENV_SETUP:-0}"
PYTHON311_BIN="${PYTHON311_BIN:-python3.11}"
MERGE_VENV_DIR="${MERGE_VENV_DIR:-$WORK_DIR/.venv-merge}"
COREML_VENV_DIR="${COREML_VENV_DIR:-$WORK_DIR/.venv-coreml}"

MERGED_DIR="$WORK_DIR/merged_hf"
COREML_DIR="$WORK_DIR/coreml"

mkdir -p "$WORK_DIR"

ensure_venv() {
  local py_bin="$1"
  local venv_dir="$2"
  if [[ ! -x "$venv_dir/bin/python3" ]]; then
    "$py_bin" -m venv "$venv_dir"
  fi
}

install_merge_env() {
  local py="$1"
  "$py" -m pip install --upgrade pip
  "$py" -m pip install -r "$ROOT_DIR/scripts/lcm/requirements-lcm.txt"
}

install_coreml_env() {
  local py="$1"
  "$py" -m pip install --upgrade pip
  "$py" -m pip install git+https://github.com/apple/ml-stable-diffusion
}

if [[ "$SKIP_ENV_SETUP" == "1" ]]; then
  MERGE_PYTHON="${MERGE_PYTHON:-python3}"
  COREML_PYTHON="${COREML_PYTHON:-python3}"
else
  ensure_venv "$PYTHON311_BIN" "$MERGE_VENV_DIR"
  ensure_venv "$PYTHON311_BIN" "$COREML_VENV_DIR"

  install_merge_env "$MERGE_VENV_DIR/bin/python3"
  install_coreml_env "$COREML_VENV_DIR/bin/python3"

  MERGE_PYTHON="$MERGE_VENV_DIR/bin/python3"
  COREML_PYTHON="$COREML_VENV_DIR/bin/python3"
fi

echo "[1/3] merge SD1.5 + LCM LoRA"
"$MERGE_PYTHON" "$ROOT_DIR/scripts/lcm/merge_sd15_lcm.py" \
  --base-model "$BASE_MODEL" \
  --lora-model "$LCM_LORA_MODEL" \
  --output-dir "$MERGED_DIR" \
  --lora-scale "$LORA_SCALE" \
  --dtype "$DTYPE"

echo "[2/3] convert fused model to Core ML"
PYTHON_BIN="$COREML_PYTHON" \
CHUNK_UNET="$CHUNK_UNET" \
QUANTIZE_NBITS="$QUANTIZE_NBITS" \
"$ROOT_DIR/scripts/lcm/convert_to_coreml.sh" "$MERGED_DIR" "$COREML_DIR"

# StableDiffusionPipeline on iOS expects tokenizer files at resource root.
for tok_file in merges.txt vocab.json; do
  if [[ -f "$MERGED_DIR/tokenizer/$tok_file" ]]; then
    cp -f "$MERGED_DIR/tokenizer/$tok_file" "$COREML_DIR/$tok_file"
  fi
done

echo "[3/3] package zip + sha256"
"$ROOT_DIR/scripts/lcm/package_coreml_zip.sh" "$COREML_DIR" "$ARTIFACT_NAME" "$ZIP_OUT"

echo "[done] artifact ready: $ZIP_OUT"
