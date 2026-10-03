"""Run actual reviewed Godot import in an isolated ignored project; no GPU claim."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid

from check_fixture import DEFAULT_FIXTURE, ROOT, check, require

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def run(command, logfile):
    result = subprocess.run([str(item) for item in command], capture_output=True, text=True,
                            encoding="utf-8", errors="replace", timeout=60)
    text = result.stdout + result.stderr
    logfile.write_text(text, encoding="utf-8")
    require(result.returncode == 0, f"Godot exit {result.returncode}: {logfile}")
    require(not any(marker in text for marker in ("SCRIPT ERROR:", "ERROR:", "FATAL", "Assertion failed")), f"Godot diagnostics: {logfile}")
    return text

def verify(godot, output):
    godot = godot.resolve(strict=True)
    output = output.resolve()
    require(output.is_relative_to((ROOT / ".local").resolve()), "evidence output must be inside repository .local")
    output.mkdir(parents=True, exist_ok=True)
    require(not any(output.iterdir()), "use a fresh evidence directory; preserve prior receipts")
    version = run([godot, "--version"], output / "godot-version.log").strip()
    require(version.startswith("4.7.2.stable."), f"Expected pinned Godot 4.7.2 stable, got {version}")
    source_paths = [ROOT / "tools/benchmark/pipeline/generate_fixture.py",
                    ROOT / "tools/benchmark/pipeline/check_fixture.py",
                    ROOT / "tools/benchmark/pipeline/verify_pipeline.py",
                    ROOT / "tools/benchmark/pipeline/test_fixture.py",
                    ROOT / "assets_source/proof/pipeline_fixture.blend",
                    ROOT / "assets_source/proof/pipeline_fixture.json",
                    DEFAULT_FIXTURE, ROOT / "app/proof/pipeline/check_import.gd",
                    ROOT / "app/proof/pipeline/check_import.tscn"]
    identities = {p.relative_to(ROOT).as_posix(): sha(p) for p in source_paths}
    manifest = json.loads((ROOT / "assets_source/proof/pipeline_fixture.json").read_text(encoding="utf-8"))
    for key, path in [("generator_sha256", source_paths[0]), ("blend_sha256", source_paths[4]), ("glb_sha256", DEFAULT_FIXTURE)]:
        require(manifest[key] == sha(path), f"source manifest mismatch: {key}")
    binary_result = check(DEFAULT_FIXTURE.read_bytes())
    with tempfile.TemporaryDirectory(prefix="godot-import-", dir=output) as stage_name:
        stage = Path(stage_name)
        (stage / "pipeline").mkdir()
        for name in ("pipeline_fixture.glb", "check_import.gd", "check_import.tscn"):
            shutil.copyfile(ROOT / "app/proof/pipeline" / name, stage / "pipeline" / name)
        (stage / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="Synthetic pipeline import proof"\n'
            'run/main_scene="res://pipeline/check_import.tscn"\n[rendering]\n'
            'renderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
        run([godot, "--headless", "--path", stage, "--editor", "--import"], output / "godot-import.log")
        log = run([godot, "--headless", "--path", stage], output / "godot-check.log")
        markers = [line.removeprefix("GLB_IMPORT_PROOF ") for line in log.splitlines() if line.startswith("GLB_IMPORT_PROOF ")]
        require(len(markers) == 1, "exactly one actual Godot import receipt required")
        actual = json.loads(markers[0])
        engine = actual["engine"]
        observed_version = f'{engine["major"]}.{engine["minor"]}.{engine["patch"]}.{engine["status"]}.{engine["build"]}.{engine["hash"][:9]}'
        require(actual.get("passed") is True and observed_version == version, "actual Godot engine identity")
    require(identities == {p.relative_to(ROOT).as_posix(): sha(p) for p in source_paths}, "sources changed during proof")
    receipt = {"kind": "synthetic-asset-pipeline-proof", "version": 1, "passed": True,
               "utc": datetime.now(timezone.utc).isoformat(), "sources_sha256": identities,
               "godot": {"version": version, "executable": str(godot), "sha256": sha(godot)},
               "binary_glb": binary_result, "actual_godot_import": actual,
               "scope": "headless resource import, SI/basis/parent/PBR color-space and animation only; no GPU, cockpit or aircraft-fidelity acceptance"}
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, indent=2))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / ".local/pipeline-proof" / ("run-" + uuid.uuid4().hex))
    args = parser.parse_args()
    verify(args.godot, args.output)
