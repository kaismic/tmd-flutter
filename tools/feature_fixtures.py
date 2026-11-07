"""Generate small synthetic NumPy reference cases for the Dart extractor."""
from pathlib import Path
import numpy as np
from prepare_models import write


def cases():
    source = [
        {"name": "short", "sensors": {
            "accelerometer": [[0, 3, 4, 0], [100, 0, 0, 10], [900, 1, 2, 2]],
            "gyroscope": [[0, .1, .2, .3], [500, -.4, .5, .6]],
            "magnetometer": [[0, 30, 40, 10], [500, 20, 20, 10]]}},
        {"name": "missing", "sensors": {"accelerometer": [[0, 0, 0, 9.81]]}},
        {"name": "duplicates", "sensors": {
            "accelerometer": [[0, None, 1, 2], [0, 3, 4, 0], [0, 100, 0, 0], [100, 0, 0, 10]],
            "gyroscope": [[0, 0, 0, 1], [0, 0, 0, 2], [200, 0, 0, 3]],
            "magnetometer": [[0, 2, 0, 0], [0, 3, 0, 0]]}},
        {"name": "constant", "sensors": {
            s: [[i * 20, 3, 4, 0] for i in range(30)]
            for s in ["accelerometer", "gyroscope", "magnetometer"]}},
        {"name": "empty", "sensors": {}},
    ]
    for case in source:
        expected = []
        for sensor in ["accelerometer", "gyroscope", "magnetometer"]:
            seen, magnitudes = set(), []
            for ts, *vector in case["sensors"].get(sensor, []):
                if any(v is None or not np.isfinite(v) for v in vector) or ts in seen:
                    continue
                seen.add(ts)
                magnitudes.append(np.linalg.norm(np.array(vector, dtype=np.float64)))
            if magnitudes:
                values = np.asarray(magnitudes)
                stats = [np.mean(values), np.std(values, ddof=0), np.ptp(values), np.min(values)]
                expected.extend(stats if sensor != "magnetometer" else stats[1:])
            else:
                expected.extend([np.nan] * (3 if sensor == "magnetometer" else 4))
        case["features"] = [float(v) if np.isfinite(v) else None for v in np.asarray(expected, dtype=np.float32)]
    return source


if __name__ == "__main__":
    write(Path(__file__).resolve().parents[1] / "test/fixtures/features.json", cases())
