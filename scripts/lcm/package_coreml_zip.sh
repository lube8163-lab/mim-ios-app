#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <coreml_dir> <artifact_dir_name> <zip_output_path>"
  exit 1
fi

COREML_DIR="$1"
ARTIFACT_DIR_NAME="$2"
ZIP_OUT="$3"

if [[ ! -d "$COREML_DIR" ]]; then
  echo "error: coreml directory not found: $COREML_DIR"
  exit 1
fi

ZIP_OUT_ABS="$(cd "$(dirname "$ZIP_OUT")" && pwd)/$(basename "$ZIP_OUT")"
mkdir -p "$(dirname "$ZIP_OUT_ABS")"

STAGE_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

ARTIFACT_DIR="$STAGE_DIR/$ARTIFACT_DIR_NAME"
mkdir -p "$ARTIFACT_DIR"
cp -R "$COREML_DIR"/. "$ARTIFACT_DIR"/

(
  cd "$STAGE_DIR"
  /usr/bin/zip -qry "$ZIP_OUT_ABS" "$ARTIFACT_DIR_NAME"
)

SHA256="$(shasum -a 256 "$ZIP_OUT_ABS" | awk '{print $1}')"

echo "[ok] packaged zip: $ZIP_OUT_ABS"
echo "[ok] sha256: $SHA256"
