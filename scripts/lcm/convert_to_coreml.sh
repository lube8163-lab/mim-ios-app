#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <fused_hf_dir> <coreml_output_dir> [extra torch2coreml args...]"
  exit 1
fi

PYTHON_BIN="${PYTHON_BIN:-python3}"
CHUNK_UNET="${CHUNK_UNET:-1}"
QUANTIZE_NBITS="${QUANTIZE_NBITS:-}"
FUSED_HF_DIR="$1"
COREML_OUT_DIR="$2"
shift 2

if [[ ! -d "$FUSED_HF_DIR" ]]; then
  echo "error: fused model directory not found: $FUSED_HF_DIR"
  exit 1
fi

mkdir -p "$COREML_OUT_DIR"

# Backward-compatible fix:
# If merged model has only tokenizer.json (no vocab.json/merges.txt),
# regenerate slow CLIP tokenizer files from base model cache.
"$PYTHON_BIN" -c '
import json
from pathlib import Path
from transformers import CLIPTokenizer

root = Path("'"$FUSED_HF_DIR"'")
tok_dir = root / "tokenizer"
tok_json = tok_dir / "tokenizer.json"
vocab = tok_dir / "vocab.json"
merges = tok_dir / "merges.txt"

if tok_json.exists() and (not vocab.exists() or not merges.exists()):
    model_index = root / "model_index.json"
    base_model = "runwayml/stable-diffusion-v1-5"
    if model_index.exists():
        data = json.loads(model_index.read_text(encoding="utf-8"))
        base_model = data.get("_name_or_path") or base_model

    tok = CLIPTokenizer.from_pretrained(base_model, subfolder="tokenizer", local_files_only=True)
    tok.save_pretrained(tok_dir)

    tok_cfg = tok_dir / "tokenizer_config.json"
    if tok_cfg.exists():
        data = json.loads(tok_cfg.read_text(encoding="utf-8"))
        if data.get("tokenizer_class") != "CLIPTokenizer":
            data["tokenizer_class"] = "CLIPTokenizer"
            tok_cfg.write_text(json.dumps(data, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")

    if model_index.exists():
        data = json.loads(model_index.read_text(encoding="utf-8"))
        tok_entry = data.get("tokenizer")
        if isinstance(tok_entry, list) and len(tok_entry) == 2 and tok_entry[1] != "CLIPTokenizer":
            tok_entry[1] = "CLIPTokenizer"
            data["tokenizer"] = tok_entry
            model_index.write_text(json.dumps(data, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
'

EXTRA_ARGS=()
if [[ "$CHUNK_UNET" == "1" ]]; then
  EXTRA_ARGS+=(--chunk-unet)
fi
if [[ -n "$QUANTIZE_NBITS" ]]; then
  EXTRA_ARGS+=(--quantize-nbits "$QUANTIZE_NBITS")
fi

"$PYTHON_BIN" -m python_coreml_stable_diffusion.torch2coreml \
  --model-version "$FUSED_HF_DIR" \
  -o "$COREML_OUT_DIR" \
  --convert-unet \
  --convert-text-encoder \
  --convert-vae-decoder \
  --convert-vae-encoder \
  "${EXTRA_ARGS[@]}" \
  "$@"

echo "[ok] Core ML assets exported to: $COREML_OUT_DIR"
