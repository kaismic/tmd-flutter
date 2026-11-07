import sys
from pathlib import Path
import numpy as np
import pandas as pd
import pytest
from sklearn.impute import SimpleImputer
from sklearn.pipeline import Pipeline
from xgboost import XGBClassifier

APP = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(APP / "tools"))
import prepare_models as prep
from feature_fixtures import cases


def test_export_preserves_missing_indicators_and_dropped_columns():
    rng = np.random.default_rng(42)
    values = rng.normal(size=(90, 11)).astype(np.float32)
    values[::3, 1] = np.nan
    values[:, 2] = np.nan
    labels = np.arange(90) % 3
    frame = pd.DataFrame(values, columns=prep.FEATURES)
    pipeline = Pipeline([("imputer", SimpleImputer(strategy="median", add_indicator=True)),
                         ("model", XGBClassifier(n_estimators=5, max_depth=2,
                             objective="multi:softprob", n_jobs=1, random_state=42))])
    pipeline.fit(frame, labels)
    inputs = prep.parity_inputs(frame)
    actual_labels, _, error = prep.verify(pipeline, prep.export_pipeline(pipeline), inputs)
    assert len(actual_labels) == 102
    assert error < 1e-6


def test_parity_gate_rejects_labels_and_probabilities():
    with pytest.raises(AssertionError):
        prep.assert_predictions([1], np.array([[.1, .8, .1]]), [0], np.array([[.1, .8, .1]]))
    with pytest.raises(AssertionError):
        prep.assert_predictions([1], np.array([[.1, .7, .2]]), [1], np.array([[.1, .8, .1]]))


def test_source_checksum_gate_rejects_changes(tmp_path):
    (tmp_path / "source.json").write_text("{}")
    with pytest.raises(ValueError, match="Changed source"):
        prep.verify_files(tmp_path, {"source.json": "wrong"})


def test_numpy_fixtures_are_current():
    assert prep.read(APP / "test/fixtures/features.json") == cases()


def test_complete_bundle_and_native_fixtures():
    output = APP / "assets/sydney"
    manifest = prep.read(output / "manifest.json")
    assert len(manifest["models"]) == 18
    assert len({m["id"] for m in manifest["models"]}) == 18
    assert manifest["maximum_window_seconds"] == 140
    for model in manifest["models"]:
        prep.verify_files(output, {model["asset"]: model["sha256"],
                                  model["fixture_asset"]: model["fixture_sha256"]})
        assert model["ordered_features"] == prep.FEATURES
        assert model["labels"] == prep.LABELS
        assert model["source_run"] == (prep.V1_RUN if model["version"] == 1 else prep.V2_RUN)
        fixture = prep.read(output / model["fixture_asset"])["rows"]
        assert any(all(v is None for v in row["input"]) for row in fixture)
        values = np.array([[np.nan if v is None else v for v in r["input"]] for r in fixture], dtype=np.float32)
        labels, probabilities = prep.session((output / model["asset"]).read_bytes()).run(None, {"features": values})
        prep.assert_predictions(labels, probabilities, [r["label"] for r in fixture],
                                np.array([r["probabilities"] for r in fixture]))
        if model["version"] == 2:
            assert model["heldout_parity"]["rows"] > 0
            assert model["training_sessions"]
