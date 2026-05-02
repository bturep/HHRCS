#!/usr/bin/env python3
"""
HHRCS SpeciesNet classification pass (Mac-side, off-device).

Scans a directory of detection sidecar JSONs for clips where classification
is null, extracts keyframes using MegaDetector bbox crops, runs SpeciesNet
with BC geographic prior, and writes the classification block back.

Usage:
    python speciesnet_pass.py <sidecars_dir>
    python speciesnet_pass.py /Volumes/SSD/sessions/hhrcs_20260424_054300/sidecars

Requirements:
    pip install speciesnet pillow
    ffmpeg on PATH (brew install ffmpeg)

Geographic prior:
    Country: CAN (ISO 3166-1 alpha-3)
    Region:  BC (British Columbia)
    Coordinates: 48.515, -123.408 (Prospect Lake, Saanich)
"""

import argparse
import json
import logging
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("speciesnet_pass")

# Deployment location constants
_COUNTRY = "CAN"
_ADMIN1 = "BC"
_LAT = 48.515
_LON = -123.408

# Taxonomic rank detection: SpeciesNet prediction strings use space-separated
# lower-case binomials or single words for higher ranks.
_TWO_WORD_RANKS = {"species"}
_SINGLE_WORD_RANK_MAP = {
    # map known higher-rank indicator words; others fall through to "unknown"
    "animalia": "kingdom", "mammalia": "class", "aves": "class",
    "reptilia": "class", "amphibia": "class",
    "cervidae": "family", "bovidae": "family", "canidae": "family",
    "felidae": "family", "mustelidae": "family", "leporidae": "family",
    "ardeidae": "family", "anatidae": "family", "accipitridae": "family",
    "corvidae": "family",
    "artiodactyla": "order", "carnivora": "order", "rodentia": "order",
    "lagomorpha": "order", "chiroptera": "order", "passeriformes": "order",
    "odocoileus": "genus", "cervus": "genus", "alces": "genus",
    "canis": "genus", "vulpes": "genus", "lynx": "genus",
    "lepus": "genus", "sylvilagus": "genus",
}


def _infer_taxon_level(prediction: str) -> str:
    words = prediction.strip().lower().split()
    if len(words) >= 2:
        return "species"
    if len(words) == 1:
        return _SINGLE_WORD_RANK_MAP.get(words[0], "genus")
    return "unknown"


def _extract_crop(clip_path: str, frame_ts: str, clip_start: str, bbox: list, out_path: Path) -> bool:
    """
    Extract and crop one frame from a video clip.

    clip_path:  absolute path to H264/MP4
    frame_ts:   ISO-8601 UTC timestamp of the target frame
    clip_start: ISO-8601 UTC timestamp of clip start
    bbox:       [x1, y1, x2, y2] normalized 0-1
    out_path:   where to write the cropped JPEG

    Returns True on success.
    """
    try:
        from datetime import datetime as dt
        ts = dt.fromisoformat(frame_ts)
        start = dt.fromisoformat(clip_start)
        offset_secs = (ts - start).total_seconds()
        if offset_secs < 0:
            offset_secs = 0.0
    except Exception as exc:
        log.warning(f"Timestamp parse failed: {exc} — using offset 0")
        offset_secs = 0.0

    # Extract frame with ffmpeg
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
        tmp_path = tmp.name
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-ss", f"{offset_secs:.3f}",
        "-i", clip_path,
        "-frames:v", "1",
        "-q:v", "2",
        tmp_path,
    ]
    result = subprocess.run(cmd, capture_output=True)
    if result.returncode != 0:
        log.error(f"ffmpeg failed: {result.stderr.decode()[:200]}")
        return False

    # Crop to bbox
    try:
        img = Image.open(tmp_path).convert("RGB")
        W, H = img.size
        x1, y1, x2, y2 = bbox
        left = int(x1 * W)
        top = int(y1 * H)
        right = int(x2 * W)
        bottom = int(y2 * H)
        # Guard against degenerate boxes
        if right <= left or bottom <= top:
            log.warning("Degenerate bbox — using full frame")
            img.save(out_path, "JPEG", quality=92)
        else:
            img.crop((left, top, right, bottom)).save(out_path, "JPEG", quality=92)
        Path(tmp_path).unlink(missing_ok=True)
        return True
    except Exception as exc:
        log.error(f"Crop failed: {exc}")
        return False


def _run_speciesnet(image_path: Path) -> dict:
    """
    Run SpeciesNet on a single image via CLI.
    Returns parsed prediction dict or {} on failure.
    """
    instances = [
        {
            "filepath": str(image_path),
            "country": _COUNTRY,
            "admin1_region": _ADMIN1,
            "latitude": _LAT,
            "longitude": _LON,
        }
    ]
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".json", delete=False
    ) as f_in:
        json.dump({"instances": instances}, f_in)
        in_path = f_in.name

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".json", delete=False
    ) as f_out:
        out_path = f_out.name

    cmd = [
        sys.executable, "-m", "speciesnet.scripts.run_model",
        "--instances-json", in_path,
        "--predictions-json", out_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        log.error(f"SpeciesNet failed:\n{result.stderr[:400]}")
        return {}

    try:
        data = json.loads(Path(out_path).read_text())
        preds = data.get("predictions", [])
        return preds[0] if preds else {}
    except Exception as exc:
        log.error(f"SpeciesNet output parse failed: {exc}")
        return {}
    finally:
        Path(in_path).unlink(missing_ok=True)
        Path(out_path).unlink(missing_ok=True)


def _build_classification(pred: dict) -> dict:
    """
    Convert SpeciesNet prediction dict into the HHRCS sidecar classification block.
    Stores at whatever taxonomic level SpeciesNet returned — no forced species-level.
    """
    prediction = pred.get("prediction", "")
    score = pred.get("prediction_score", 0.0)
    source = pred.get("prediction_source", "unknown")
    model_ver = pred.get("model_version", "unknown")

    # Build top-N raw predictions for audit trail
    classifications = pred.get("classifications", {})
    classes = classifications.get("classes", [])
    scores = classifications.get("scores", [])
    raw_preds = [
        {"label": c, "score": round(s, 4)}
        for c, s in zip(classes, scores)
    ]

    # Infer taxonomic level from prediction string shape
    taxon_level = _infer_taxon_level(prediction) if prediction else "unknown"

    # Attempt common name: SpeciesNet doesn't always provide one in the base
    # output — store None rather than guess
    common_name = pred.get("common_name", None)

    return {
        "species": prediction,
        "common_name": common_name,
        "confidence": round(float(score), 4),
        "taxonomic_level": taxon_level,
        "prediction_source": source,
        "model_version": str(model_ver),
        "classified_at": datetime.now(timezone.utc).isoformat(),
        "raw_predictions": raw_preds,
    }


def process_sidecar(sidecar_path: Path) -> bool:
    """
    Process one sidecar file. Returns True if classification was written.
    """
    try:
        data = json.loads(sidecar_path.read_text())
    except Exception as exc:
        log.error(f"Cannot read {sidecar_path}: {exc}")
        return False

    if data.get("classification") is not None:
        log.debug(f"Skip (already classified): {sidecar_path.name}")
        return False

    clip_path = data.get("clip_path")
    if not clip_path or not Path(clip_path).exists():
        log.warning(
            f"Skip (clip_path absent or missing): {sidecar_path.name} — "
            f"clip_path={clip_path!r}"
        )
        return False

    trigger = data.get("trigger", {})
    bbox = trigger.get("bbox")
    frame_ts = trigger.get("frame_timestamp")
    started_at = data.get("started_at")

    if not bbox or not frame_ts:
        log.warning(f"Skip (missing trigger.bbox or frame_timestamp): {sidecar_path.name}")
        return False

    log.info(f"Processing: {sidecar_path.name}")

    with tempfile.TemporaryDirectory() as tmpdir:
        crop_path = Path(tmpdir) / "trigger_crop.jpg"
        ok = _extract_crop(clip_path, frame_ts, started_at or frame_ts, bbox, crop_path)
        if not ok:
            log.error(f"Frame extraction failed: {sidecar_path.name}")
            return False

        pred = _run_speciesnet(crop_path)

    if not pred:
        log.error(f"SpeciesNet returned no prediction: {sidecar_path.name}")
        return False

    classification = _build_classification(pred)
    data["classification"] = classification
    sidecar_path.write_text(json.dumps(data, indent=2))
    log.info(
        f"Classified: {sidecar_path.name} → "
        f"{classification['species']!r} ({classification['taxonomic_level']}, "
        f"conf={classification['confidence']:.2f})"
    )
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Run SpeciesNet classification pass on HHRCS sidecar JSONs."
    )
    parser.add_argument(
        "sidecars_dir",
        help="Directory to scan recursively for sidecar JSON files",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Report what would be processed without writing anything",
    )
    args = parser.parse_args()

    root = Path(args.sidecars_dir)
    if not root.exists():
        log.error(f"Directory not found: {root}")
        sys.exit(1)

    sidecars = sorted(root.rglob("*_trigger.json"))
    pending = [
        s for s in sidecars
        if json.loads(s.read_text()).get("classification") is None
    ]

    log.info(f"Found {len(sidecars)} sidecar(s), {len(pending)} unclassified")

    if args.dry_run:
        for s in pending:
            print(s)
        return

    classified = 0
    skipped = 0
    for sidecar_path in pending:
        if process_sidecar(sidecar_path):
            classified += 1
        else:
            skipped += 1

    log.info(f"Done — classified: {classified}, skipped/failed: {skipped}")


if __name__ == "__main__":
    main()
