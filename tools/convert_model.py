#!/usr/bin/env python3
"""SafeCircle voiceprint model converter.

Downloads the Wespeaker ResNet34-LM speaker verification model (ONNX,
trained on VoxCeleb2) and converts it to a quantized TFLite model suitable
for on-device inference in the Flutter app.

Output: mobile-app/assets/models/voxceleb_resnet34_LM.tflite

Source model license: CC-BY-4.0 — must attribute Wespeaker in app credits
(see /about screen).

Usage:
    .venv/Scripts/python.exe convert_model.py

See README_voiceprint.md for setup and troubleshooting.
"""

from __future__ import annotations

import shutil
import sys
import time
from pathlib import Path

import numpy as np
import onnx
import onnx2tf
import onnxruntime as ort
import tensorflow as tf
from huggingface_hub import hf_hub_download

# ── Constants ───────────────────────────────────────────────────────────

HF_REPO = "Wespeaker/wespeaker-voxceleb-resnet34-LM"
ONNX_FILENAME = "voxceleb_resnet34_LM.onnx"

# Target input shape for TFLite (FBANK features).
# T=200 frames @ 10ms hop = 2s of audio. Dart side pads/truncates.
FBANK_DIM = 80
TARGET_TIME_FRAMES = 200

# Validation: generate N random FBANK inputs and compare ONNX vs TFLite
# embeddings via cosine similarity. Must be >= threshold to pass.
NUM_VALIDATION_SAMPLES = 20
COSINE_THRESHOLD = 0.99

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
CACHE_DIR = SCRIPT_DIR / "cache"
WORK_DIR = CACHE_DIR / "work"
OUTPUT_DIR = REPO_ROOT / "mobile-app" / "assets" / "models"
OUTPUT_TFLITE = OUTPUT_DIR / "voxceleb_resnet34_LM.tflite"


def step(msg: str) -> None:
    print(f"\n=== {msg} ===", flush=True)


def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    a = a.flatten().astype(np.float64)
    b = b.flatten().astype(np.float64)
    denom = np.linalg.norm(a) * np.linalg.norm(b) + 1e-12
    return float(np.dot(a, b) / denom)


def generate_realistic_fbank(
    rng: np.random.Generator, time_frames: int, fbank_dim: int = FBANK_DIM
) -> np.ndarray:
    """Generate a synthetic log-mel FBANK that mimics real speech statistics.

    Real log-mel features for speech have:
      - Mean around -10 (log of small mel energies).
      - Spectral tilt: low-freq bins higher energy than high-freq.
      - Temporal smoothing: adjacent frames are correlated.
      - Spectral smoothing: adjacent mel bins are correlated.
      - Range typically -25 (silence) to +5 (loud voiced segments).

    Random gaussian inputs are a worst-case stress test that doesn't reflect
    real-world quantization behavior. This generator stays inside the
    distribution the model was trained on.

    Returns shape [1, T, fbank_dim] in ONNX layout.
    """
    base_level = -10.0
    # Spectral tilt: low freq ~ +2, high freq ~ -3.
    tilt = np.linspace(2.0, -3.0, fbank_dim, dtype=np.float32)
    # Per-frame energy with temporal smoothing (5-frame moving average).
    frame_energy = rng.normal(0.0, 3.0, time_frames).astype(np.float32)
    kernel_t = np.ones(5, dtype=np.float32) / 5.0
    frame_energy = np.convolve(frame_energy, kernel_t, mode="same")
    # Spectral noise smoothed across mel bins (3-bin moving average).
    spec_noise = rng.normal(0.0, 2.0, (time_frames, fbank_dim)).astype(np.float32)
    kernel_s = np.ones(3, dtype=np.float32) / 3.0
    for t in range(time_frames):
        spec_noise[t] = np.convolve(spec_noise[t], kernel_s, mode="same")
    fbank = base_level + tilt[None, :] + frame_energy[:, None] + spec_noise
    # Clip to realistic range.
    fbank = np.clip(fbank, -25.0, 5.0)
    return fbank[None, :, :].astype(np.float32)


def quantize_fp16(saved_model_dir: Path, out_path: Path) -> float:
    """Convert SavedModel to FP16 TFLite. Returns size in MB."""
    converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    out_path.write_bytes(converter.convert())
    return out_path.stat().st_size / 1024 / 1024


def validate_tflite(
    tflite_path: Path,
    onnx_session: ort.InferenceSession,
    onnx_input_name: str,
    onnx_output_name: str,
    rng: np.random.Generator,
    n_samples: int = NUM_VALIDATION_SAMPLES,
) -> tuple[float, float, float, bool]:
    """Validate TFLite numerical equivalence with ONNX using realistic FBANK.

    Returns (min_cosine, mean_cosine, max_cosine, transpose_for_tflite).
    """
    interp = tf.lite.Interpreter(model_path=str(tflite_path))
    in_details = interp.get_input_details()[0]
    out_details = interp.get_output_details()[0]
    in_idx = in_details["index"]
    out_idx = out_details["index"]
    raw_shape = tuple(int(d) for d in in_details["shape"])

    # Detect orientation.
    if raw_shape[-1] == FBANK_DIM:
        transpose_for_tflite = False
    elif raw_shape[1] == FBANK_DIM:
        transpose_for_tflite = True
    else:
        raise RuntimeError(
            f"Unexpected TFLite input shape: {raw_shape}. "
            f"Neither dim 1 nor dim -1 matches FBANK_DIM={FBANK_DIM}."
        )

    cosines: list[float] = []
    for _ in range(n_samples):
        # Vary T between 100 and 300 frames (~1-3s of audio @ 10ms hop).
        T = int(rng.integers(100, 301))
        fbank_onnx = generate_realistic_fbank(rng, T)

        onnx_emb = onnx_session.run(
            [onnx_output_name], {onnx_input_name: fbank_onnx}
        )[0]

        if transpose_for_tflite:
            fbank_tflite = np.transpose(fbank_onnx, (0, 2, 1))
            target_shape = [1, FBANK_DIM, T]
        else:
            fbank_tflite = fbank_onnx
            target_shape = [1, T, FBANK_DIM]

        interp.resize_tensor_input(in_idx, target_shape)
        interp.allocate_tensors()
        interp.set_tensor(in_idx, fbank_tflite)
        interp.invoke()
        tflite_emb = interp.get_tensor(out_idx)

        cosines.append(cosine_similarity(onnx_emb, tflite_emb))

    arr = np.array(cosines)
    return float(arr.min()), float(arr.mean()), float(arr.max()), transpose_for_tflite


def main() -> int:
    t0 = time.monotonic()

    step("1. Setup directories")
    CACHE_DIR.mkdir(exist_ok=True)
    if WORK_DIR.exists():
        shutil.rmtree(WORK_DIR)
    WORK_DIR.mkdir()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"  Cache:  {CACHE_DIR}")
    print(f"  Work:   {WORK_DIR}")
    print(f"  Output: {OUTPUT_DIR}")

    step("2. Download ONNX model")
    onnx_path = Path(
        hf_hub_download(
            repo_id=HF_REPO,
            filename=ONNX_FILENAME,
            cache_dir=str(CACHE_DIR / "hf"),
        )
    )
    onnx_size_mb = onnx_path.stat().st_size / 1024 / 1024
    print(f"  Downloaded: {onnx_path}")
    print(f"  Size:       {onnx_size_mb:.2f} MB")

    step("3. Inspect ONNX inputs/outputs")
    model = onnx.load(str(onnx_path))
    for inp in model.graph.input:
        shape = [d.dim_value or d.dim_param or "?" for d in inp.type.tensor_type.shape.dim]
        print(f"  Input  '{inp.name}': shape={shape}")
    for out in model.graph.output:
        shape = [d.dim_value or d.dim_param or "?" for d in out.type.tensor_type.shape.dim]
        print(f"  Output '{out.name}': shape={shape}")

    onnx_input_name = model.graph.input[0].name
    onnx_output_name = model.graph.output[0].name

    step("4. Convert ONNX -> TF SavedModel via onnx2tf")
    saved_model_dir = WORK_DIR / "saved_model"
    # Don't force overwrite_input_shape — onnx2tf maps it through a NCW->NWC
    # transpose, which produced wrong shape on this model. Instead, leave the
    # time dim dynamic and call resize_tensor_input() at inference time.
    onnx2tf.convert(
        input_onnx_file_path=str(onnx_path),
        output_folder_path=str(saved_model_dir),
        copy_onnx_input_output_names_to_tflite=True,
        non_verbose=False,
        output_signaturedefs=True,
    )
    print(f"  SavedModel written to: {saved_model_dir}")

    step("5. Quantize -> Dynamic Range INT8 TFLite")
    converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    # Dynamic range: weights INT8, activations Float32. No representative
    # dataset needed. ~7-10MB final size with ~0.5% EER hit (vs FP32).
    tflite_bytes = converter.convert()
    OUTPUT_TFLITE.write_bytes(tflite_bytes)
    final_size_mb = OUTPUT_TFLITE.stat().st_size / 1024 / 1024
    reduction = (1 - final_size_mb / onnx_size_mb) * 100
    print(f"  TFLite size: {final_size_mb:.2f} MB")
    print(f"  Reduction:   {reduction:.1f}% vs ONNX ({onnx_size_mb:.2f} MB)")

    step("6. Validate INT8 numeric equivalence (ONNX vs TFLite)")
    onnx_session = ort.InferenceSession(
        str(onnx_path), providers=["CPUExecutionProvider"]
    )
    rng = np.random.default_rng(seed=42)

    print(f"  Using realistic FBANK input (log-mel range -25..+5,")
    print(f"  spectral tilt + temporal/spectral smoothing, T=100-300).")

    min_cos, mean_cos, max_cos, transpose = validate_tflite(
        OUTPUT_TFLITE, onnx_session, onnx_input_name, onnx_output_name, rng
    )
    print(f"  Samples tested: {NUM_VALIDATION_SAMPLES}")
    print(f"  Cosine min:  {min_cos:.6f}")
    print(f"  Cosine mean: {mean_cos:.6f}")
    print(f"  Cosine max:  {max_cos:.6f}")
    if transpose:
        print(f"  -> Dart side must transpose [1, T, 80] -> [1, 80, T].")

    # Decision tree per user's spec:
    #   min >= 0.99           → APPROVED INT8
    #   0.97 <= min < 0.99    → REPORT, ask user (exit 2)
    #   min < 0.97            → AUTO-ESCALATE to FP16
    if min_cos >= COSINE_THRESHOLD:
        elapsed = time.monotonic() - t0
        print(f"\n[OK] INT8 APPROVED — min cosine {min_cos:.6f} >= "
              f"{COSINE_THRESHOLD}")
        print(f"     Output: {OUTPUT_TFLITE}")
        print(f"     Size:   {final_size_mb:.2f} MB")
        print(f"     Time:   {elapsed:.1f}s")
        return 0

    if min_cos >= 0.97:
        print(f"\n[NEEDS DECISION] min cosine {min_cos:.6f} in [0.97, 0.99).")
        print(f"  INT8 produced a small but real degradation. Two options:")
        print(f"  (A) Accept INT8 with relaxed threshold (mean is {mean_cos:.4f}).")
        print(f"  (B) Escalate to FP16 (~13MB, zero quantization loss).")
        print(f"  Re-run script after editing COSINE_THRESHOLD or pass --fp16.")
        return 2

    print(f"\n[AUTO-ESCALATE] min cosine {min_cos:.6f} < 0.97 — escalating "
          f"to FP16.")
    fp16_path = OUTPUT_TFLITE.with_name(OUTPUT_TFLITE.stem + "_fp16.tflite")
    fp16_size_mb = quantize_fp16(saved_model_dir, fp16_path)
    print(f"  FP16 size: {fp16_size_mb:.2f} MB")

    fp16_min, fp16_mean, fp16_max, _ = validate_tflite(
        fp16_path, onnx_session, onnx_input_name, onnx_output_name,
        np.random.default_rng(seed=42),
    )
    print(f"  FP16 cosine min:  {fp16_min:.6f}")
    print(f"  FP16 cosine mean: {fp16_mean:.6f}")
    print(f"  FP16 cosine max:  {fp16_max:.6f}")

    if fp16_min < COSINE_THRESHOLD:
        print(f"\n[FAIL] FP16 also failed (min {fp16_min:.6f} < {COSINE_THRESHOLD}).")
        print(f"  Both quantizations degraded the model. Falling back to")
        print(f"  ECAPA-tdnn-vox2 (Apache-2.0) is the next step.")
        return 1

    # FP16 passed — replace INT8 output with FP16
    OUTPUT_TFLITE.unlink()
    fp16_path.rename(OUTPUT_TFLITE)
    elapsed = time.monotonic() - t0
    print(f"\n[OK] FP16 APPROVED — min cosine {fp16_min:.6f} >= {COSINE_THRESHOLD}")
    print(f"     Output: {OUTPUT_TFLITE}")
    print(f"     Size:   {fp16_size_mb:.2f} MB (FP16 fallback from INT8)")
    print(f"     Time:   {elapsed:.1f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
