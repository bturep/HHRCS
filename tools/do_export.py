#!/usr/bin/env python3
"""
Minimal YOLOv5s → ONNX export for MDv1000-spruce.

Does NOT use yolov5/export.py or its requirements.txt.
Loads the checkpoint via torch.hub (downloads yolov5 architecture modules)
then re-exports with torch.onnx.export.

Usage:
    python do_export.py md_v1000.0.0-spruce.pt md_v1000_spruce.onnx
"""

import sys
import hashlib
import pathlib
import torch

# Add the yolov5 hub cache to sys.path so the checkpoint's pickled model classes resolve.
# torch.hub downloads to ~/.cache/torch/hub/ultralytics_yolov5_master on first run.
_HUB_DIR = pathlib.Path.home() / ".cache" / "torch" / "hub" / "ultralytics_yolov5_master"
if _HUB_DIR.exists() and str(_HUB_DIR) not in sys.path:
    sys.path.insert(0, str(_HUB_DIR))

WEIGHTS  = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "md_v1000.0.0-spruce.pt")
OUT_ONNX = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "md_v1000_spruce.onnx")
IMG_SIZE = 640

print(f"Weights : {WEIGHTS}  ({WEIGHTS.stat().st_size / 1e6:.1f} MB)")
print(f"Output  : {OUT_ONNX}")
print(f"ImgSize : {IMG_SIZE}×{IMG_SIZE}")
print()

# ── Load model ─────────────────────────────────────────────────────────────────
print("Loading checkpoint via torch.hub (downloads yolov5 modules if needed)...")
try:
    # torch.hub.load pulls the architecture from ultralytics/yolov5 on GitHub.
    # 'custom' path lets us supply our own weights file.
    model = torch.hub.load(
        "ultralytics/yolov5",
        "custom",
        path=str(WEIGHTS),
        force_reload=False,
        verbose=False,
    )
    model.eval()
    model.float()
    print(f"Loaded  : {model.__class__.__name__}  nc={model.nc}")
except Exception as e:
    print(f"\nERROR loading via torch.hub: {e}")
    print("\nFallback: loading raw checkpoint...")
    try:
        ckpt = torch.load(str(WEIGHTS), map_location="cpu", weights_only=False)
        # The actual model may be under different keys
        if hasattr(ckpt, "eval"):
            model = ckpt
        elif "model" in ckpt:
            model = ckpt["model"].float()
        elif "ema" in ckpt:
            model = ckpt["ema"].float()
        else:
            raise ValueError(f"Unknown checkpoint keys: {list(ckpt.keys())}")
        model.eval()
        print(f"Loaded  : fallback  type={type(model)}")
    except Exception as e2:
        print(f"FATAL: could not load checkpoint: {e2}")
        sys.exit(1)

# ── Export ─────────────────────────────────────────────────────────────────────
print(f"\nExporting to ONNX opset 12...")
dummy = torch.zeros(1, 3, IMG_SIZE, IMG_SIZE)

# Inspect output shape before export
with torch.no_grad():
    try:
        out = model(dummy)
        # YOLOv5 returns a tuple; the ONNX-exportable output is the first element
        if isinstance(out, (list, tuple)):
            shapes = [o.shape for o in out if hasattr(o, "shape")]
            print(f"Forward pass output shapes: {shapes}")
        else:
            print(f"Forward pass output shape: {out.shape}")
    except Exception as e:
        print(f"Forward pass check failed: {e}")

torch.onnx.export(
    model,
    dummy,
    str(OUT_ONNX),
    opset_version=12,
    input_names=["images"],
    output_names=["output0"],
    dynamic_axes=None,
    verbose=False,
)

# ── Verify ─────────────────────────────────────────────────────────────────────
import onnx
onnx_model = onnx.load(str(OUT_ONNX))
onnx.checker.check_model(onnx_model)
inp  = onnx_model.graph.input[0]
outp = onnx_model.graph.output[0]
print(f"\n=== ONNX verified ===")
print(f"  Input  : {inp.name}  {[d.dim_value for d in inp.type.tensor_type.shape.dim]}")
print(f"  Output : {outp.name}  {[d.dim_value for d in outp.type.tensor_type.shape.dim]}")

# Check NMS baked in — there should be no NonMaxSuppression node for raw output
nms_nodes = [n for n in onnx_model.graph.node if n.op_type == "NonMaxSuppression"]
print(f"  NMS baked in: {'YES (unexpected)' if nms_nodes else 'NO (correct)'}")

size_mb = OUT_ONNX.stat().st_size / 1e6
sha256  = hashlib.sha256(OUT_ONNX.read_bytes()).hexdigest()
print(f"\n  File   : {OUT_ONNX}")
print(f"  Size   : {size_mb:.1f} MB")
print(f"  SHA256 : {sha256}")

if 5 < size_mb < 200:
    print(f"\n  [PASS] Size {size_mb:.1f} MB is in expected range (5–200 MB)")
else:
    print(f"\n  [WARN] Unexpected size {size_mb:.1f} MB — verify this is correct")
