"""Compile every renderer resource and reject headless GPU claims using pinned Godot.

This is a functional CI check, never a graphics performance measurement.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]
SUFFIXES = {".gd", ".tscn", ".glb"}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def snapshot():
    result = {}
    for directory in ("render", "pipeline"):
        for file in sorted((ROOT / "app/proof" / directory).rglob("*")):
            if file.suffix not in SUFFIXES:
                continue
            if file.is_symlink() or not file.is_file():
                raise ValueError("Renderer resources must be regular files")
            result[file.relative_to(ROOT / "app/proof").as_posix()] = file.read_bytes()
    if not result or "render/panel.gd" not in result or "render/render.tscn" not in result:
        raise ValueError("Incomplete renderer resource snapshot")
    return result


def unchanged(original, staged, current):
    if original != staged or original != current:
        raise ValueError("Renderer resource changed during staging/proof")


def run(editor, arguments, log_path):
    try:
        result = subprocess.run([str(editor), *map(str, arguments)], capture_output=True,
                                encoding="utf-8", errors="replace", timeout=60)
    except subprocess.TimeoutExpired as error:
        def decode(value):
            return value.decode("utf-8", errors="replace") if isinstance(value, bytes) else (value or "")
        log_path.write_text(decode(error.stdout) + decode(error.stderr), encoding="utf-8")
        raise RuntimeError("Bounded Godot process timed out; raw log retained") from error
    text = result.stdout + result.stderr
    log_path.write_text(text, encoding="utf-8")
    return result.returncode, text


def clean(text):
    return not any(marker in text for marker in ("ERROR:", "SCRIPT ERROR:", "FATAL", "leaked at exit", "Assertion failed"))


def project_config(main_scene=False):
    return ('config_version=5\n[application]\nconfig/name="Headless rejection check"\n'
            + ('run/main_scene="res://render/render.tscn"\n' if main_scene else '')
            + '[rendering]\nrenderer/rendering_method="gl_compatibility"\n')


def loader(project, paths):
    # Explicit resource loads compile lazy scripts before the GPU guard is run.
    # No scene is instantiated and no renderer _ready/_draw callbacks execute.
    source = '''extends SceneTree
func _initialize() -> void:
    var file := FileAccess.open("res://compile-resources.json", FileAccess.READ)
    var resources: Array = JSON.parse_string(file.get_as_text())
    for path in resources:
        var resource = load("res://" + path)
        if resource == null or (path.ends_with(".gd") and (not resource is Script or not resource.can_instantiate())):
            push_error("RENDER_COMPILE_FAILED: " + path)
            quit(1)
            return
    print("RENDER_COMPILE_PROOF " + JSON.stringify({"passed": true, "resources": resources}))
    quit(0)
'''
    (project / "compile-all.gd").write_text(source, encoding="utf-8")
    (project / "compile-resources.json").write_text(json.dumps(paths) + "\n", encoding="utf-8")
    return sha(source.encode("utf-8"))


def pinned_editor(candidate, output):
    lock_bytes = (ROOT / "third_party/dependencies.lock.json").read_bytes()
    lock = json.loads(lock_bytes)
    host = "windows" if platform.system() == "Windows" else "linux"
    pin = next(item for item in lock["tools"] if item["id"] == "godot" and item["platform"] == host)
    editor = candidate.resolve(strict=True)
    if editor.name != pin["executable"]:
        raise ValueError("Selected editor executable differs from host pin")
    marker = json.loads((editor.parent / ".verified.json").read_text())
    if any(marker[key] != pin[key] for key in ("id", "version", "url", "sha256")):
        raise ValueError("Editor pin/verified receipt mismatch")
    spec = importlib.util.spec_from_file_location("flight_bootstrap", ROOT / "tools/bootstrap/bootstrap.py")
    bootstrap = importlib.util.module_from_spec(spec)
    sys.dont_write_bytecode = True
    spec.loader.exec_module(bootstrap)
    tree_sha256 = bootstrap.tree_digest(editor.parent)
    if tree_sha256 != marker["tree_sha256"]:
        raise ValueError("Actual extracted editor tree changed")
    code, version_log = run(editor, ["--version"], output / "godot-version.log")
    version = version_log.strip()
    if code or not clean(version_log) or not version.startswith(pin["version"].replace("-", ".") + "."):
        raise ValueError("Actual editor version differs from pin")
    identity = {"version": version, "executable": editor.name, "executable_sha256": sha(editor.read_bytes()),
                "tree_sha256": tree_sha256, "archive_sha256": pin["sha256"], "platform": host}
    return editor, identity, bootstrap, lock_bytes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / ".local/render-headless" / uuid.uuid4().hex)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to((ROOT / ".local").resolve()):
        raise ValueError("Output must remain in repository .local")
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise ValueError("Preserve evidence; use a fresh directory")
    verifier_bytes = Path(__file__).read_bytes()
    editor, identity, bootstrap, lock_bytes = pinned_editor(args.godot, output)
    original = snapshot()
    paths = sorted(original)
    with tempfile.TemporaryDirectory(dir=output, prefix="project-") as directory:
        project = Path(directory)
        for path, data in original.items():
            target = project / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        (project / "project.godot").write_text(project_config(True), encoding="utf-8")
        compile_sha256 = loader(project, paths)
        # Match the accepted native cold-import workaround for the upstream
        # first-discovery shutdown race; no engine/vendor patch is introduced.
        code, text = run(editor, ["--headless", "--path", project, "--editor", "--quit-after", "120", "--frame-delay", "100"], output / "import.log")
        if code or not clean(text):
            raise RuntimeError("Renderer resource import failed")
        code, text = run(editor, ["--headless", "--path", project, "--script", "res://compile-all.gd"], output / "compile.log")
        proofs = [json.loads(line.removeprefix("RENDER_COMPILE_PROOF ")) for line in text.splitlines() if line.startswith("RENDER_COMPILE_PROOF ")]
        if code or not clean(text) or proofs != [{"passed": True, "resources": paths}]:
            raise RuntimeError("Explicit renderer script/resource compilation failed")
        code, text = run(editor, ["--headless", "--path", project], output / "rejection.log")
        expected = "ERROR: RENDER_PROOF_FAILED: GPU benchmark cannot be headless"
        if (code != 1 or text.count(expected) != 1 or text.count("ERROR:") != 1
                or any(marker in text for marker in ("SCRIPT ERROR:", "FATAL", "leaked at exit", "Assertion failed", "RENDER_PROBE ", "RENDER_DEVICE ", "RENDERED_ORIGIN_PAIR "))):
            raise RuntimeError("Headless execution did not reject GPU claims cleanly")
        unchanged(original, {path: (project / path).read_bytes() for path in paths}, snapshot())
    # A separate synthetic lazy-panel project proves the exact defect cannot
    # return a successful compilation receipt. Never mutate production inputs.
    with tempfile.TemporaryDirectory(dir=output, prefix="invalid-panel-") as directory:
        negative = Path(directory)
        (negative / "render").mkdir()
        bad_panel = b"extends Node2D\nfunc _draw() -> void:\n    @@ INVALID_LAZY_PANEL_NEGATIVE\n"
        (negative / "render/panel.gd").write_bytes(bad_panel)
        (negative / "project.godot").write_text(project_config(), encoding="utf-8")
        loader(negative, ["render/panel.gd"])
        code, text = run(editor, ["--headless", "--path", negative, "--script", "res://compile-all.gd"], output / "invalid-panel.log")
        if code == 0 or "RENDER_COMPILE_FAILED: render/panel.gd" not in text or "RENDER_COMPILE_PROOF " in text:
            raise RuntimeError("Invalid lazy-panel negative falsely passed")
    drift_negatives = 0
    for staged, current in (({**original, "render/panel.gd": b"changed"}, original),
                            (original, {**original, "render/panel.gd": b"changed"}),
                            (original, {key: value for key, value in original.items() if key != "render/panel.gd"})):
        try:
            unchanged(original, staged, current)
        except ValueError:
            drift_negatives += 1
            continue
        raise AssertionError("Resource drift negative falsely passed")
    unchanged(original, original, snapshot())
    if (bootstrap.tree_digest(editor.parent) != identity["tree_sha256"]
            or (ROOT / "third_party/dependencies.lock.json").read_bytes() != lock_bytes
            or Path(__file__).read_bytes() != verifier_bytes):
        raise ValueError("Editor, dependency lock or verifier changed during proof")
    receipt = {"schema_version": 1, "passed": True, "utc": datetime.now(timezone.utc).isoformat(),
               "scope": "explicit script/resource compile and headless rejection only; no GPU benchmark",
               "godot": identity, "dependency_lock_sha256": sha(lock_bytes), "verifier_sha256": sha(verifier_bytes),
               "loader_sha256": compile_sha256, "sources_sha256": {path: sha(data) for path, data in original.items()},
               "source_inventory": [{"path": path, "bytes": len(original[path]), "sha256": sha(original[path])} for path in paths],
               "compiled_resources": paths, "expected_exit_code": 1,
               "negative_proofs": {"invalid_lazy_panel_rejected": True, "synthetic_panel_sha256": sha(bad_panel),
                                   "source_drift_rejections": drift_negatives}}
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt))


if __name__ == "__main__":
    main()
