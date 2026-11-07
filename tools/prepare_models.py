"""Reproduce the detector bundle from trusted local runs; source trees are read-only."""
import argparse
import hashlib
import importlib.metadata
import json
import platform
import shutil
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
import pandas as pd
from sklearn.impute import SimpleImputer
from sklearn.pipeline import Pipeline
from sklearn.utils.class_weight import compute_sample_weight
from xgboost import XGBClassifier
from skl2onnx import convert_sklearn, update_registered_converter
from skl2onnx.common.data_types import FloatTensorType
from skl2onnx.common.shape_calculator import calculate_linear_classifier_output_shapes
from onnxmltools.convert.xgboost.operator_converters.XGBoost import convert_xgboost

APP = Path(__file__).resolve().parents[1]
ROOT = APP.parents[1]
V1_RUN = "sydney-20261007"
V2_RUN = "20261104T005620Z-3b08cd99"
FEATURES = [f"{sensor}#{stat}" for sensor in ["accelerometer", "gyroscope", "magnetometer"]
            for stat in (["mean", "standard_deviation", "range", "minimum"]
                         if sensor != "magnetometer" else ["standard_deviation", "range", "minimum"])]
LABELS = ["bus", "car", "train"]
NUMERICAL = ["numpy", "pandas", "scikit-learn", "xgboost", "joblib", "scipy", "pyarrow"]
RTOL, ATOL = 1e-5, 1e-6


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, allow_nan=False, separators=(",", ":")) + "\n", encoding="utf-8")
    temp.replace(path)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def verify_files(directory, files):
    for name, expected in files.items():
        path = (directory / name).resolve()
        if not path.is_relative_to(directory.resolve()) or sha(path) != expected:
            raise ValueError(f"Changed source artifact: {path}")


def session(model_bytes):
    options = ort.SessionOptions()
    options.intra_op_num_threads = options.inter_op_num_threads = 1
    return ort.InferenceSession(model_bytes, options, providers=["CPUExecutionProvider"])


def export_pipeline(pipeline):
    # Adapted from transport-mode-benchmark/tools/prepare.py. Explicitly include
    # fitted imputation and indicators: skl2onnx otherwise omits add_indicator.
    update_registered_converter(XGBClassifier, "XGBoostXGBClassifier",
        calculate_linear_classifier_output_shapes, convert_xgboost,
        options={"nocl": [True, False], "zipmap": [True, False]})
    imputer = pipeline[0]
    kept = np.flatnonzero(np.isfinite(imputer.statistics_)).astype(np.int64)
    indicators = imputer.indicator_.features_.astype(np.int64)
    graph = convert_sklearn(pipeline[-1],
        initial_types=[("prepared", FloatTensorType([None, len(kept) + len(indicators)]))],
        options={id(pipeline[-1]): {"zipmap": False}}, target_opset={"": 17, "ai.onnx.ml": 3})
    helper, tensor = onnx.helper, onnx.TensorProto
    initializers = [
        onnx.numpy_helper.from_array(kept, "detector_kept"),
        onnx.numpy_helper.from_array(imputer.statistics_[kept].astype(np.float32), "detector_medians")]
    nodes = [
        helper.make_node("IsNaN", ["features"], ["detector_missing"]),
        helper.make_node("Gather", ["features", "detector_kept"], ["detector_values"], axis=1),
        helper.make_node("Gather", ["detector_missing", "detector_kept"], ["detector_kept_missing"], axis=1),
        helper.make_node("Where", ["detector_kept_missing", "detector_medians", "detector_values"], ["detector_imputed"])]
    if len(indicators):
        initializers.append(onnx.numpy_helper.from_array(indicators, "detector_indicators"))
        nodes += [
            helper.make_node("Gather", ["detector_missing", "detector_indicators"], ["detector_flags"], axis=1),
            helper.make_node("Cast", ["detector_flags"], ["detector_float_flags"], to=tensor.FLOAT),
            helper.make_node("Concat", ["detector_imputed", "detector_float_flags"], ["prepared"], axis=1)]
    else:
        nodes.append(helper.make_node("Identity", ["detector_imputed"], ["prepared"]))
    existing = list(graph.graph.node)
    del graph.graph.node[:]
    graph.graph.node.extend([*nodes, *existing])
    del graph.graph.input[:]
    graph.graph.input.append(helper.make_tensor_value_info("features", tensor.FLOAT, [None, len(FEATURES)]))
    graph.graph.initializer.extend(initializers)
    graph.ir_version = min(graph.ir_version, 10)
    onnx.checker.check_model(graph)
    return graph.SerializeToString()


def parity_inputs(frame):
    values = frame[FEATURES].to_numpy(dtype=np.float32)
    missing = np.repeat(values[:1], len(FEATURES) + 1, axis=0)
    for index in range(len(FEATURES)):
        missing[index, index] = np.nan
    missing[-1] = np.nan
    return np.concatenate([values, missing])


def assert_predictions(actual_labels, actual_probs, expected_labels, expected_probs):
    np.testing.assert_array_equal(actual_labels, expected_labels)
    np.testing.assert_allclose(actual_probs, expected_probs, rtol=RTOL, atol=ATOL)
    return float(np.max(np.abs(actual_probs - expected_probs)))


def verify(pipeline, model_bytes, values):
    frame = pd.DataFrame(values, columns=FEATURES)
    labels, probabilities = pipeline.predict(frame), pipeline.predict_proba(frame)
    actual_labels, actual_probs = session(model_bytes).run(None, {"features": values})
    error = assert_predictions(actual_labels, actual_probs, labels, probabilities)
    return labels, probabilities, error


def rows(values, labels, probabilities):
    return [{"input": [float(v) if np.isfinite(v) else None for v in vector],
             "label": int(label), "probabilities": probability.tolist()}
            for vector, label, probability in zip(values, labels, probabilities)]


def small_fixture(source):
    # Exercise each class and every individual/all-missing feature case on device.
    selected = []
    for label in range(3):
        match = next((r for r in source if r["label"] == label), None)
        if match is not None:
            selected.append(match)
    selected.extend(r for r in source if any(v is None for v in r["input"]))
    return selected


def descriptor(version, window, seed):
    model_id = f"sydney-v{version}-w{window}-s{seed}"
    return {"id": model_id, "version": version, "family": "xgboost",
            "source_run": V1_RUN if version == 1 else V2_RUN,
            "window_seconds": window, "seed": seed, "asset": f"models/{model_id}.onnx",
            "fixture_asset": f"fixtures/{model_id}.json",
            "ordered_features": FEATURES, "labels": LABELS,
            "input": {"name": "features", "dtype": "float32", "shape": [1, 11]},
            "outputs": {"label": "label", "probabilities": "probabilities"}}


def copy_v1(bundle, output):
    manifest = read(bundle / "manifest.json")
    if manifest["source_run"] != V1_RUN:
        raise ValueError("Unexpected V1 source run")
    expected_ids = {f"sydney-v1-w{w}-s{s}" for w in [100, 120, 140] for s in [42, 43, 44]}
    if {m["id"] for m in manifest["models"]} != expected_ids or len(manifest["models"]) != 9:
        raise ValueError("Expected exactly nine V1 models")
    models = []
    for original in manifest["models"]:
        if original["ordered_features"] != FEATURES or original["labels"] != LABELS:
            raise ValueError("Unexpected V1 feature/label contract")
        verify_files(bundle, {original["asset"]: original["sha256"],
                              original["fixture_asset"]: original["fixture_sha256"]})
        fixture = read(bundle / original["fixture_asset"])["rows"]
        values = np.asarray([[np.nan if v is None else v for v in r["input"]] for r in fixture], dtype=np.float32)
        labels, probabilities = session((bundle / original["asset"]).read_bytes()).run(None, {"features": values})
        error = assert_predictions(labels, probabilities, [r["label"] for r in fixture],
                                   np.asarray([r["probabilities"] for r in fixture]))
        model = descriptor(1, original["window_seconds"], original["seed"])
        shutil.copyfile(bundle / original["asset"], output / model["asset"])
        write(output / model["fixture_asset"], {"rows": small_fixture(fixture)})
        model.update(sha256=sha(output / model["asset"]),
                     fixture_sha256=sha(output / model["fixture_asset"]),
                     parity={"rows": len(values), "max_absolute_error": error, "rtol": RTOL, "atol": ATOL},
                     source_bundle_sha256=sha(bundle / "manifest.json"),
                     source_prepared_sha256=manifest["source_prepared_sha256"])
        models.append(model)
        print(f"{model['id']}: V1 parity {len(values)} rows, max error {error:.3g}", flush=True)
    return models


def reconstruct_v2(run, output):
    identity, prepared = read(run / "identity.json"), read(run / "prepared.json")
    if run.name != V2_RUN or digest(identity) != prepared["identity"]:
        raise ValueError("Unexpected V2 run identity")
    # Only prepared inputs used by reconstruction are needed; raw snapshot files
    # are never read, since saved feature tables are the exact training inputs.
    needed = ["experiment.json", "splits.json", "features-100.parquet", "features-120.parquet", "features-140.parquet"]
    verify_files(run, {name: prepared["files"][name] for name in needed})
    versions = {name: importlib.metadata.version(name) for name in NUMERICAL}
    if versions != {name: identity["environment"][name] for name in NUMERICAL}:
        raise ValueError(f"Install tools/requirements.txt; numerical versions differ: {versions}")
    config = identity["configuration"]
    if (config["feature_names"] != FEATURES or config["labels"] != dict(zip(LABELS, range(3)))
            or config["windows_seconds"] != [100, 120, 140]
            or config["seeds"] != [42, 43, 44] or config["model_families"] != ["xgboost"]):
        raise ValueError("Unexpected V2 model contract")
    evaluated = read(run / "evaluated.json")
    if evaluated["prepared"] != sha(run / "prepared.json"):
        raise ValueError("Evaluation does not match preparation")
    frames = {w: pd.read_parquet(run / f"features-{w}.parquet") for w in [100, 120, 140]}
    splits = read(run / "splits.json")["outer"]
    if len(splits) != 3:
        raise ValueError("Expected one outer split per seed")
    models = []
    for index, fold in enumerate(splits):
        seed = fold["seed"]
        if seed not in [42, 43, 44] or fold["id"] != "session-split":
            raise ValueError("Unexpected outer split")
        directory = run / f"outer/fold-{index:03d}-seed-{seed}"
        if directory.relative_to(run).as_posix() not in evaluated["bundles"]:
            raise ValueError("Outer bundle not evaluated")
        verify_files(directory, read(directory / "complete.json")["files"])
        selection = read(directory / "selection.json")
        saved = pd.read_parquet(directory / "predictions.parquet")
        if set(fold["train_sessions"]) & set(fold["test_sessions"]):
            raise ValueError("Train/test leakage")
        for window, frame in frames.items():
            train = frame[frame.session_id.isin(fold["train_sessions"])]
            test = frame[frame.session_id.isin(fold["test_sessions"])]
            winner = selection["winners"][str(window)]
            params = {k: v for k, v in winner["params"].items() if k != "family"}
            estimator = XGBClassifier(**params, objective="multi:softprob", eval_metric="mlogloss",
                tree_method="hist", device="cpu", random_state=seed, n_jobs=identity["threads"])
            pipeline = Pipeline([("imputer", SimpleImputer(strategy="median", add_indicator=True)),
                                 ("model", estimator)])
            pipeline.fit(train[FEATURES], train.label,
                         model__sample_weight=compute_sample_weight("balanced", train.label))
            expected = saved[(saved["window"] == window) & (saved["result"] == str(window))]
            keys = ["session_id", "window_start_ms", "window_end_ms"]
            aligned = test.merge(expected[keys + ["prediction", "probability_0", "probability_1", "probability_2"]],
                                 on=keys, how="left", validate="one_to_one")
            if len(aligned) != len(expected) or aligned.prediction.isna().any():
                raise ValueError("Held-out prediction alignment differs")
            heldout_error = assert_predictions(
                pipeline.predict(aligned[FEATURES]), pipeline.predict_proba(aligned[FEATURES]),
                aligned.prediction.to_numpy(), aligned[["probability_0", "probability_1", "probability_2"]].to_numpy())
            model_bytes = export_pipeline(pipeline)
            values = parity_inputs(frame)
            labels, probabilities, error = verify(pipeline, model_bytes, values)
            model = descriptor(2, window, seed)
            (output / model["asset"]).write_bytes(model_bytes)
            write(output / model["fixture_asset"], {"rows": small_fixture(rows(values, labels, probabilities))})
            model.update(sha256=sha(output / model["asset"]),
                fixture_sha256=sha(output / model["fixture_asset"]),
                source_prepared_sha256=sha(run / "prepared.json"),
                source_selection_sha256=sha(directory / "selection.json"),
                training_sessions=fold["train_sessions"], training_windows=len(train), winner=winner,
                heldout_parity={"rows": len(aligned), "max_absolute_error": heldout_error},
                parity={"rows": len(values), "max_absolute_error": error, "rtol": RTOL, "atol": ATOL})
            models.append(model)
            print(f"{model['id']}: held-out {len(aligned)} rows / error {heldout_error:.3g}; "
                  f"ONNX {len(values)} rows / error {error:.3g}", flush=True)
    return models


def prepare(v1_bundle, v2_run, output):
    v1_bundle, v2_run, output = [Path(p).resolve() for p in [v1_bundle, v2_run, output]]
    identity = read(v2_run / "identity.json")
    if platform.system() != "Linux" or platform.python_version() != identity["environment"]["python"]:
        raise ValueError("Reconstruct V2 in Linux with its recorded Python version; use tools/Dockerfile")
    if any(output.is_relative_to(source) or source.is_relative_to(output)
           for source in [v1_bundle, v2_run]):
        raise ValueError("Output must be separate from source artifacts")
    (output / "models").mkdir(parents=True, exist_ok=True)
    (output / "fixtures").mkdir(exist_ok=True)
    # A failure must never leave a completion manifest advertising partial models.
    (output / "manifest.json").unlink(missing_ok=True)
    models = copy_v1(v1_bundle, output) + reconstruct_v2(v2_run, output)
    models.sort(key=lambda m: (m["version"], m["window_seconds"], m["seed"]))
    expected = {f"sydney-v{v}-w{w}-s{s}" for v in [1, 2] for w in [100, 120, 140] for s in [42, 43, 44]}
    if {m["id"] for m in models} != expected or len(models) != 18:
        raise ValueError("Incomplete model catalogue")
    write(output / "manifest.json", {"schema_version": 1, "models": models,
        "maximum_window_seconds": max(m["window_seconds"] for m in models),
        "v2_source_environment": read(v2_run / "identity.json")["environment"],
        "export_environment": {"python": platform.python_version(),
            **{n: importlib.metadata.version(n) for n in NUMERICAL +
               ["onnx", "onnxruntime", "skl2onnx", "onnxmltools"]}}})
    print(f"Complete: {output / 'manifest.json'}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--v1-bundle", type=Path, default=ROOT / "apps/transport-mode-benchmark/assets/benchmark")
    parser.add_argument("--v2-run", type=Path, default=ROOT / f"ml/sydney-tmd-v2/runs/{V2_RUN}")
    parser.add_argument("--output", type=Path, default=APP / "assets/sydney")
    args = parser.parse_args()
    prepare(args.v1_bundle, args.v2_run, args.output)
