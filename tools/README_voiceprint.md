# SafeCircle voiceprint model conversion

This folder converts the Wespeaker speaker-verification model from ONNX
to a quantized TFLite file that the Flutter app uses for on-device
voice biometrics.

The conversion runs **once** (or whenever the model is upgraded). The
Flutter app does **not** need Python — it ships the resulting `.tflite`
as an asset.

## What it produces

`mobile-app/assets/models/voxceleb_resnet34_LM.tflite` — Wespeaker
ResNet34-LM, 256-dim speaker embedding, Dynamic Range INT8 quantization.
Expected size ~7-10 MB. Source model license: **CC-BY-4.0** (must
attribute Wespeaker in app credits).

Source: https://huggingface.co/Wespeaker/wespeaker-voxceleb-resnet34-LM

## Prerequisites

- **Python 3.11** (TensorFlow 2.18 does not support 3.13+ in 2026).
  On Windows: `py -3.11 --version` should print `Python 3.11.x`.
- ~2 GB free disk for venv + TF + downloaded model.
- Internet access (downloads model from HuggingFace, ~26 MB).

## Setup (one time)

```bash
cd tools
py -3.11 -m venv .venv
.venv/Scripts/python.exe -m pip install --upgrade pip
.venv/Scripts/python.exe -m pip install \
  "numpy<2" \
  "onnx==1.17.0" \
  "onnxruntime==1.20.1" \
  "tensorflow==2.18.0" \
  "onnx2tf==1.26.3" \
  "huggingface_hub==0.27.0" \
  "tf-keras" \
  "ai-edge-litert"
```

Versions are pinned for reproducibility. Bumping any of them risks
breaking the conversion.

## Run conversion

```bash
cd tools
.venv/Scripts/python.exe convert_model.py
```

Expected output (success):

```
=== 1. Setup directories ===
=== 2. Download ONNX model ===
=== 3. Inspect ONNX inputs/outputs ===
=== 4. Convert ONNX -> TF SavedModel via onnx2tf ===
=== 5. Quantize -> Dynamic Range INT8 TFLite ===
  TFLite size: 7.x MB
=== 6. Validate numeric equivalence (ONNX vs TFLite) ===
  Cosine min:  0.99xxxx
[OK] Conversion complete in NNs
```

Failure modes the script catches:

- **Min cosine < 0.99** → quantization degraded the model. Script
  exits non-zero. Either retry with FP16 (edit `converter.optimizations`
  + add `target_spec.supported_types = [tf.float16]`) or fall back to
  `yangwang825/ecapa-tdnn-vox2` (Apache-2.0).
- **onnx2tf import error** → missing `tf-keras` shim. Re-run setup.
- **Model download 401** → HuggingFace rate-limit. Wait a minute.

## When to re-run

- Source model upgraded by Wespeaker (rare).
- We want to try a different quantization (FP16, full INT8 with
  representative dataset).
- We switch to a different model entirely (fall back to
  ECAPA-tdnn-vox2 etc).

After re-running, **commit the new `.tflite`** and bump the model hash
constant in the Dart code so existing users get re-enrolled
automatically (see `voiceprint_service.dart`).

## What the `.tflite` expects as input

- **Shape**: `[1, 200, 80]` (batch=1, time=200 frames, mel=80).
- **Dtype**: `float32`.
- **Source**: log-mel filterbank features computed in Dart from PCM
  16 kHz mono audio (~2 seconds). Roughly zero-mean unit-variance
  (CMVN-normalized).
- **Output**: `[1, 256]` float32 speaker embedding. Compare via
  cosine similarity against an enrolled embedding.

The mel-spectrogram pre-processing happens **in Dart** (not embedded
in the `.tflite`) for clearer separation and easier debugging. See
`mobile-app/lib/core/services/voiceprint_service.dart`.

## Files

- `convert_model.py` — the conversion script.
- `.venv/` — Python virtual environment (gitignored).
- `cache/` — HuggingFace download cache + intermediate SavedModel
  (gitignored).
- `README_voiceprint.md` — this file.
