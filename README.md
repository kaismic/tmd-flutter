# Transport Mode Detector

Flutter prototype with two inference modes: activity recognition followed by
on-device vehicle classification, or continuous ONNX classification assuming a
vehicle. ONNX models distinguish bus, car and train. Model selection works
before and during detection.

## Models

The picker contains exactly 18 XGBoost models, grouped by Sydney version, then
window length (100/120/140 seconds) and seed (42/43/44). The default is
**Sydney V1 · 100s · seed 42**. Selection lasts for the current app session.
Selecting a model during detection preserves the recordings already collected.

- **V1:** the nine validated full-cohort exports from
  `../transport-mode-benchmark/assets/benchmark`, originating from
  `ml/sydney-tmd-v1/runs/sydney-20261007`. The original saved final model is
  100 seconds/seed 42; the benchmark reconstructed the other eight from saved
  winners without repeating tuning.
- **V2:** nine reconstructions from
  `ml/sydney-tmd-v2/runs/20261104T005620Z-3b08cd99`. Each window/seed uses its
  own saved winning parameters and original training-session split, including
  median imputation, missing indicators and balanced training class weights.
  Held-out sessions do not enter training. No tuning is repeated.

The five legacy classifiers are no longer offered. Both Sydney versions use
11 float32 magnitude features, ordered as accelerometer and gyroscope
mean/population standard deviation/range/minimum, then magnetometer population
standard deviation/range/minimum. Original sensor units are preserved.
GPS collection and its dependency/permission declarations have been removed.

## Prepare the model assets

ONNX models, the bundle manifest and native parity fixtures are generated and
ignored by Git. **Prepare the complete bundle before building or testing.**
The source runs and benchmark bundle must be present locally. Their files are
read-only inputs; preparation never changes any training or benchmark repository.

Use Docker to reproduce V2's original **Linux/Python 3.12.16** environment.
A Windows reconstruction with the same numerical package versions did not
reproduce every saved held-out prediction. The exporter checks environment and
source checksums, refits the nine pipelines, checks all saved held-out
predictions, and checks ONNX/Python parity including individual/all-missing
features. Labels must match exactly and probabilities must agree within
`rtol=1e-5, atol=1e-6`. It writes `manifest.json` last, only after all 18
models pass. Do not build from a partially generated bundle.

From this app directory in PowerShell:

```powershell
docker build -f tools/Dockerfile -t tmd-detector-export .
$workspaceRoot = (Resolve-Path ../..).Path
$bundleOutput = Join-Path (Get-Location).Path 'assets/sydney'
New-Item -ItemType Directory -Force -Path $bundleOutput | Out-Null
docker run --rm --mount "type=bind,source=$workspaceRoot,target=/workspace,readonly" --mount "type=bind,source=$bundleOutput,target=/output" tmd-detector-export --output /output
flutter pub get
flutter run
```

An existing original training image can be reused with
`--build-arg BASE_IMAGE=sydney-tmd-v2-study:latest` in the build command. Otherwise
the Dockerfile uses the pinned Python base and installs
`tools/requirements.txt`. The CLI also accepts `--v1-bundle`, `--v2-run` and
`--output` for relocated inputs/output.

The manifest records model/fixture hashes, source run and selection hashes,
training-session identities, winners, parity counts/errors and the actual
export environment. V1 model bytes are copied unchanged. The native fixtures
contain representative feature vectors and missing-feature cases, with no raw
recordings or participant names.

## Detection and warm-up

Use the **Inference** selector while detection is stopped to choose:

1. **Activity recognition first** (default): grant activity-recognition
   permission when starting. Non-vehicle activities pass through directly;
   sensors and ONNX inference run when activity recognition reports a vehicle
   and stop when that activity ends.
2. **Always use ONNX**: assume a vehicle and start sensor collection immediately
   on **Start Detection**, classifying bus, car or train every second until
   stopped. This mode bypasses the activity-recognition API, its permission
   request and its event stream. Walking/still/running/cycling are not model
   outputs in this mode.

Mode selection lasts for the current app session and is retained after Stop.
Stop detection before changing inference mode; the selector is disabled during
a run and its tooltip explains this. Classification models remain selectable
during inference in both modes, preserving the shared sensor buffer.

Stopping detection clears all recordings. Both modes use the same warm-up,
buffering and error handling described below. Collection requests about
60 Hz accelerometer, 5 Hz gyroscope and 5 Hz magnetometer; actual delivery
depends on the device. A rate cap with delivery-jitter allowance bounds memory.

The app retains the last **140 seconds**, calculated from the longest model
duration in the catalogue. Each one-second tick extracts the selected model's
trailing window from this shared buffer. Timestamps use a monotonic clock.
Readings expire even if a sensor stops delivering data.

Inference starts with available samples instead of waiting for a full window.
There is no time padding or fabricated zero sensor data. Features for absent
sensors are NaN and pass through the model's fitted imputer. With no usable
readings at all, the app shows a waiting state rather than an invented prediction.

The current result shows mode, confidence and model identity throughout
warm-up. **Warm-up incomplete** remains visible until both conditions hold:

1. Collection has run for the selected model's full duration.
2. That trailing window has valid sensor coverage: accelerometer ≥30 Hz,
   gyroscope ≥4 Hz, magnetometer ≥2 Hz, and gaps ≤500 ms, including window
   boundaries.

The duration bar can reach 100% while coverage is still insufficient; the
accompanying text identifies missing/sparse sensors or gaps. Predictions
continue in that condition, and coverage can recover once gaps age out.
Short-window statistics can be less representative than a complete window.

History retains the latest ten results, including early predictions, with each
result's original model and warm-up status. Loading/waiting/error statuses do
not become history predictions. Model loads and native inference are serialized;
timer ticks wait for loading and skip an already-busy prediction. Obsolete
completions after model changes, vehicle exit or stop are discarded. Model-load
errors can be retried by selecting the same model again; inference errors retry
on the next tick.

## Validation

```powershell
flutter test --no-pub
flutter analyze --no-pub
flutter build apk --debug --no-pub
flutter test integration_test/models_test.dart -d DEVICE_ID --no-pub
```

The integration test loads every model through the app's native ONNX wrapper
and checks representative predictions, including missing features. It requires
a connected Android device/emulator; desktop unit tests do not exercise native
sensor acquisition or activity recognition.

For Python conversion/bundle checks and NumPy reference-fixture generation:

```powershell
python -m venv .venv
.venv/Scripts/python -m pip install -r tools/requirements.txt
.venv/Scripts/python -m pytest tests -q
.venv/Scripts/python tools/feature_fixtures.py
```

Reference-fixture generation is needed only when intentionally updating the
extractor contract; its small synthetic outputs are tracked under `test/fixtures`.
The tests cover short/missing/duplicate/constant readings, selected-window
slicing, maximum retention, coverage recovery, one-second scheduling, model
switches, load/prediction failures, stop/restart, native resource cleanup, picker
selection, early-result history and narrow screens. Mode tests cover immediate
ONNX startup, activity-permission bypass, ignored activity events, switching
modes between runs, and cleanup of pending startup/inference on Stop.

The prepared bundle passed **77,640 ONNX parity cases**. V2 reconstruction
matched **7,720 saved held-out predictions/probability vectors exactly**; maximum
ONNX probability error across all exports was **1.7881393e-7**.

Validation on 7 November 2026: **38 Flutter tests** and **5 Python tests** passed;
static analysis reported no issues and the Android debug APK built successfully.
All 18 packaged model and fixture hashes matched the validated bundle. Native
Android inference and live sensor/activity behavior remain unverified: no
Android device was connected, and existing emulator directories had no usable
AVD profiles. Run the integration test above on a device to complete that check.
