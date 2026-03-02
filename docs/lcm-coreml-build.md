# SD1.5 + LCM Core ML Build Guide

This guide generates a merged SD1.5 + LCM Core ML model zip that can be hosted for app install.

## 1. Prerequisites

- macOS with Apple Silicon recommended
- Python 3.11 (recommended)
- Xcode command line tools (`xcode-select --install`)
- Hugging Face access for model downloads (if using remote model ids)

`python_coreml_stable_diffusion` currently fails on Python 3.12 in this workflow.
Use Python 3.11 explicitly.

Install Python dependencies:

```bash
python3.11 -m venv .venv-lcm
source .venv-lcm/bin/activate
python3 -m pip install --upgrade pip
python3 -m pip install -r scripts/lcm/requirements-lcm.txt
```

The build script now creates isolated envs under `build/lcm` by default:

- `build/lcm/.venv-merge` for LoRA merge
- `build/lcm/.venv-coreml` for Core ML conversion

## 2. Build

Run from repository root:

```bash
chmod +x scripts/lcm/*.sh
bash -euo pipefail scripts/lcm/build_sd15_lcm_coreml.sh
```

Default output:

- zip: `build/lcm/sd15_lcm_coreml_v1.zip`
- metadata: `build/lcm/merged_hf/lcm_merge_metadata.json`
- default conversion uses `--chunk-unet` for lower runtime memory

Environment overrides:

```bash
BASE_MODEL="runwayml/stable-diffusion-v1-5" \
LCM_LORA_MODEL="latent-consistency/lcm-lora-sdv1-5" \
ARTIFACT_NAME="sd15_lcm_coreml_v1" \
WORK_DIR="$(pwd)/build/lcm" \
LORA_SCALE="1.0" \
DTYPE="float16" \
CHUNK_UNET="1" \
scripts/lcm/build_sd15_lcm_coreml.sh
```

Optional memory-size tradeoff:

```bash
QUANTIZE_NBITS="6" scripts/lcm/build_sd15_lcm_coreml.sh
```

If you already manage environments manually, disable auto setup:

```bash
SKIP_ENV_SETUP=1 \
MERGE_PYTHON="/path/to/merge-env/bin/python3" \
COREML_PYTHON="/path/to/coreml-env/bin/python3" \
scripts/lcm/build_sd15_lcm_coreml.sh
```

## 3. Upload Metadata for App

Capture and store:

- artifact URL
- `sha256` printed by `package_coreml_zip.sh`
- artifact size

Then add a new model entry in app-side model config (for example `sd15_lcm_coreml_v1`).
