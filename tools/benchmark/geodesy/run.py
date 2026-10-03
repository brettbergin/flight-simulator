"""Actual pinned Godot CPU geometry proof against a supplied frame.gd source."""
import argparse
import hashlib
import importlib.util
import json
import math
import platform
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def sha(data):
    return hashlib.sha256(data).hexdigest()


def assert_unchanged(original, staged, current):
    if staged != original or current != original:
        raise ValueError("Frame source changed during staging/proof; result rejected")


def reference():
    # Independent WGS84 constants/equations; authored before projection results.
    a, f = 6378137.0, 1 / 298.257223563
    e2 = f * (2 - f)
    cases = [("equator-prime", 0, 0, 0), ("equator-east90", 0, math.pi / 2, 0),
             ("north-pole-declared-longitude", math.pi / 2, .7, 0),
             ("south-pole-declared-longitude", -math.pi / 2, -1.1, 0),
             ("dateline", 0, math.pi, 0), ("mixed-elevated", .8, -2, 1000),
             ("near-north-pole", math.radians(89.999), math.radians(179.999), 120)]
    points = []
    for name, lat, lon, height in cases:
        n = a / math.sqrt(1 - e2 * math.sin(lat) ** 2)
        points.append(dict(name=name, latitude_rad=lat, longitude_rad=lon, height_m=height,
                           ecef_m=[(n + height) * math.cos(lat) * math.cos(lon),
                                   (n + height) * math.cos(lat) * math.sin(lon),
                                   (n * (1 - e2) + height) * math.sin(lat)]))
    return dict(points=points, seams=[
        dict(name="west-east-dateline", a=[.7, math.radians(179.999), 30], b=[.7, math.radians(-179.999), 30]),
        dict(name="near-pole-longitude-turn", a=[math.radians(89.999), -.8, 30], b=[math.radians(89.999), 1.2, 30])])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frame", type=Path, default=ROOT / "app/proof/render/frame.gd")
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / ".local/render-geodesy")
    parser.add_argument("--expected-frame-sha256")
    args = parser.parse_args()
    frame = args.frame.resolve(strict=True)
    output = args.output.resolve()
    # Test output must stay in ignored .local; never erase or reuse app sources.
    if not output.is_relative_to((ROOT / ".local").resolve()):
        raise ValueError("Geometry output must be inside this checkout's .local")
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise ValueError("Use a fresh geometry evidence directory; preserve prior receipts")
    source = frame.read_bytes()
    source_hash = sha(source)
    if args.expected_frame_sha256 and source_hash != args.expected_frame_sha256:
        raise ValueError("Frame does not match requested source identity")
    lock = json.loads((ROOT / "third_party/dependencies.lock.json").read_text())
    host = "windows" if platform.system() == "Windows" else "linux"
    pin = next(x for x in lock["tools"] if x["id"] == "godot" and x["platform"] == host)
    editor = (args.godot or ROOT / ".local/toolchain/godot" / pin["executable"]).resolve(strict=True)
    marker = json.loads((editor.parent / ".verified.json").read_text())
    if any(marker[k] != pin[k] for k in ("id", "version", "url", "sha256")):
        raise ValueError("Editor pin/verified receipt mismatch")
    spec = importlib.util.spec_from_file_location("flight_bootstrap", ROOT / "tools/bootstrap/bootstrap.py")
    bootstrap = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bootstrap)
    if bootstrap.tree_digest(editor.parent) != marker["tree_sha256"]:
        raise ValueError("Actual extracted editor tree changed")
    version = subprocess.run([str(editor), "--version"], capture_output=True, text=True, check=True, timeout=30).stdout.strip()
    if not version.startswith("4.7.2.stable."):
        raise ValueError("Actual engine version differs from pin")
    (output / "frame.gd").write_bytes(source)
    (output / "check.gd").write_bytes((HERE / "check.gd").read_bytes())
    (output / "reference.json").write_text(json.dumps(reference(), indent=2) + "\n", encoding="utf-8")
    (output / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Private render geodesy proof"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
    result = subprocess.run([str(editor), "--headless", "--path", str(output), "--script", "res://check.gd"], capture_output=True, text=True, timeout=60)
    log = result.stdout + result.stderr
    (output / "godot-log.txt").write_text(log, encoding="utf-8")
    assert_unchanged(source, (output / "frame.gd").read_bytes(), frame.read_bytes())
    if result.returncode or "ERROR:" in log or "SCRIPT ERROR:" in log or "RENDER_GEODESY_RESULT " not in log:
        raise RuntimeError("Actual Godot geometry check failed; inspect ignored godot-log.txt")
    report = json.loads((output / "result.json").read_text())
    if report["failures"] or report["transactions"] != 500 or report["canonical_byte_checks"] != 500:
        raise ValueError("Incomplete geometry proof")
    report.update(frame_source_sha256=source_hash, test_source_sha256=sha((HERE / "check.gd").read_bytes()),
                  reference_sha256=sha((output / "reference.json").read_bytes()),
                  actual_godot_version=version, actual_editor_sha256=sha(editor.read_bytes()),
                  actual_editor_tree_sha256=marker["tree_sha256"], dependency_lock_sha256=sha((ROOT / "third_party/dependencies.lock.json").read_bytes()))
    (output / "receipt.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    # Explicit guard negatives: changed current or staged module invalidates receipt.
    for staged, current in ((source + b"\n", source), (source, source + b"\n")):
        try:
            assert_unchanged(source, staged, current)
        except ValueError:
            continue
        raise AssertionError("Changed-source guard failed to reject")
    print(json.dumps(dict(passed=True, checks=report["checks"], frame_source_sha256=source_hash,
                         max_reference_error_px=report["max_reference_error_px"],
                         max_transaction_error_px=report["max_transaction_error_px"],
                         changed_source_negatives=2)))


if __name__ == "__main__":
    main()
