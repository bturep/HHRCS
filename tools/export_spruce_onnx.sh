#!/usr/bin/env bash
# Export MDv1000-spruce (YOLOv5s backbone) to ONNX for Pi deployment.
#
# Run on Mac (not Pi). Requires Python 3.9+ and ~2 GB free RAM.
# Output: md_v5a.onnx (~14 MB FP16 or ~28 MB FP32) in current directory.
#
# Usage:
#   bash export_spruce_onnx.sh [--fp32]
#
# Default output is FP16 (~14 MB, matches the 12-15 MB spec).
# Pass --fp32 for full precision (~28 MB) if precision matters more than size.

set -euo pipefail

SPRUCE_PT_URL="https://github.com/agentmorris/MegaDetector/releases/download/v1000.0/md_v1000.0.0-spruce.pt"
SPRUCE_PT="md_v1000.0.0-spruce.pt"
ONNX_OUT="md_v5a.onnx"
IMG_SIZE=640
HALF=true

for arg in "$@"; do
  if [[ "$arg" == "--fp32" ]]; then
    HALF=false
  fi
done

echo "=== HHRCS: MegaDetector Spruce → ONNX ==="
echo "  Model: $SPRUCE_PT_URL"
echo "  Output: $ONNX_OUT  ($([ "$HALF" = true ] && echo FP16 || echo FP32), ${IMG_SIZE}px)"
echo ""

# 1. Download spruce.pt if not present
if [[ ! -f "$SPRUCE_PT" ]]; then
  echo "Downloading $SPRUCE_PT (~14 MB)..."
  curl -L -o "$SPRUCE_PT" "$SPRUCE_PT_URL"
  echo "Downloaded: $(du -sh $SPRUCE_PT | cut -f1)"
else
  echo "Found existing $SPRUCE_PT ($(du -sh $SPRUCE_PT | cut -f1))"
fi

# 2. Set up a scratch venv — torch requires Python ≤ 3.13; use 3.12 if available
PYTHON_BIN="python3"
for candidate in python3.12 python3.11 python3.10 /usr/local/bin/python3.12; do
  if command -v "$candidate" &>/dev/null; then
    VER=$("$candidate" -c 'import sys; print(sys.version_info[:2])')
    if [[ "$VER" != "(3, 14)"* && "$VER" != *"14"* ]]; then
      PYTHON_BIN="$candidate"
      break
    fi
    # Accept 3.12/3.11/3.10 — reject 3.14 since no torch wheel exists yet
    if [[ "$VER" == "(3, 12)"* || "$VER" == "(3, 11)"* || "$VER" == "(3, 10)"* ]]; then
      PYTHON_BIN="$candidate"
      break
    fi
  fi
done
# Fallback: check brew-installed 3.12 directly
if [[ "$PYTHON_BIN" == "python3" ]]; then
  for p in /usr/local/bin/python3.12 /opt/homebrew/bin/python3.12; do
    [[ -x "$p" ]] && PYTHON_BIN="$p" && break
  done
fi
echo "Using Python: $PYTHON_BIN ($($PYTHON_BIN --version))"

if [[ ! -d ".venv_export" ]]; then
  echo ""
  echo "Creating export venv..."
  "$PYTHON_BIN" -m venv .venv_export
  .venv_export/bin/pip install --quiet --upgrade pip
  # yolov5 export.py needs torch + onnx
  .venv_export/bin/pip install --quiet torch torchvision onnx onnxsim
fi

# 3. Clone yolov5 repo (needed for export.py) if not already present
if [[ ! -d "yolov5" ]]; then
  echo "Cloning ultralytics/yolov5 (shallow)..."
  git clone --depth 1 https://github.com/ultralytics/yolov5.git
  .venv_export/bin/pip install --quiet -r yolov5/requirements.txt
fi

# 4. Run export
echo ""
echo "Exporting to ONNX (img-size=${IMG_SIZE}, half=${HALF})..."
HALF_FLAG=$([ "$HALF" = true ] && echo "--half" || echo "")
.venv_export/bin/python yolov5/export.py \
  --weights "$SPRUCE_PT" \
  --include onnx \
  --img $IMG_SIZE \
  --opset 12 \
  $HALF_FLAG \
  --simplify

EXPORTED="${SPRUCE_PT%.pt}.onnx"
if [[ -f "$EXPORTED" ]]; then
  cp "$EXPORTED" "$ONNX_OUT"
  SIZE=$(du -sh "$ONNX_OUT" | cut -f1)
  SHA=$(shasum -a 256 "$ONNX_OUT" | awk '{print $1}')
  echo ""
  echo "=== Export complete ==="
  echo "  File:   $ONNX_OUT"
  echo "  Size:   $SIZE"
  echo "  SHA256: $SHA"
  echo ""
  echo "Now SCP to Pi:"
  echo "  scp $ONNX_OUT pi@192.168.1.68:/home/pi/hhrcs/models/md_v5a.onnx"
else
  echo "ERROR: export.py did not produce $EXPORTED"
  exit 1
fi
