"""Isolated evergreen resource/visual proof. Never opens the game project."""
import argparse
from datetime import datetime, timezone
from fractions import Fraction
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import stat
import struct
import subprocess
import sys

ROOT = Path(__file__).absolute().parents[4]
HERE = Path(__file__).absolute().parent
ROSTER = (
    ("tall-narrow", 0, "OriginalTallNarrowL0"), ("tall-narrow", 1, "OriginalTallNarrowL1"),
    ("broad-tiered", 0, "OriginalBroadTieredL0"), ("broad-tiered", 1, "OriginalBroadTieredL1"),
    ("irregular-mature", 0, "OriginalIrregularMatureL0"), ("irregular-mature", 1, "OriginalIrregularMatureL1"),
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def ordinary(path, *, exists=True, directory=False):
    """Check spelling AND every existing ancestor before resolving aliases."""
    path = Path(path)
    require(path.is_absolute(), "absolute paths required")
    require(".." not in path.parts, "parent traversal is forbidden")
    for part in reversed((path, *path.parents)):
        try:
            info = part.lstat()
        except FileNotFoundError:
            require(part == path and not exists, "missing ancestor/input")
            continue
        require(not stat.S_ISLNK(info.st_mode) and not (getattr(info, "st_file_attributes", 0) & 0x400), "symlink/reparse path forbidden")
    if exists:
        require(path.is_dir() if directory else path.is_file(), "wrong input path type")
    else:
        require(not path.exists(), "output must not exist; preserve earlier attempts")
    return path.resolve(strict=exists)


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def identity(path):
    ordinary(path)
    return {"bytes": path.stat().st_size, "sha256": sha(path)}


def write_json(path, value):
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, sort_keys=True, indent=2, allow_nan=False)
        stream.write("\n")


def run(command, folder, name, timeout):
    stdout, stderr = folder / (name + ".stdout.log"), folder / (name + ".stderr.log")
    write_json(folder / (name + ".command.json"), [str(item) for item in command])
    with stdout.open("xb") as out, stderr.open("xb") as err:
        child = subprocess.Popen([str(item) for item in command], stdout=out, stderr=err, cwd=folder)
        try:
            code = child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait(timeout=30)
            raise ValueError(f"{name} timed out; logs retained") from None
    require(stdout.stat().st_size <= 16 * 1024 * 1024 and stderr.stat().st_size <= 16 * 1024 * 1024, "diagnostic log bound exceeded")
    text = stdout.read_text(encoding="utf-8", errors="replace") + stderr.read_text(encoding="utf-8", errors="replace")
    require(code == 0, f"{name} exit {code}; logs retained")
    require(not any(token in text for token in ("SCRIPT ERROR:", "ERROR:", "FATAL", "Assertion failed", "WARNING:")), f"{name} emitted diagnostics; review retained logs")
    return text


def read_json(path):
    require(path.stat().st_size <= 4 * 1024 * 1024, "receipt too large")
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "duplicate receipt key")
            result[key] = value
        return result
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=pairs,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError("nonfinite JSON")))


def engine_version(receipt):
    engine = receipt["engine"]
    return f'{engine["major"]}.{engine["minor"]}.{engine["patch"]}.{engine["status"]}.{engine["build"]}.{engine["hash"][:9]}'


def exact_triangle_nonzero(a, b, c):
    ab = tuple(b[i] - a[i] for i in range(3))
    ac = tuple(c[i] - a[i] for i in range(3))
    return any((ab[1] * ac[2] - ab[2] * ac[1],
                ab[2] * ac[0] - ab[0] * ac[2],
                ab[0] * ac[1] - ab[1] * ac[0]))


def math_controls():
    zero = (Fraction(0), Fraction(0), Fraction(0))
    tiny = Fraction(1, 1 << 40)
    # Exact hand controls, unrelated to any generated or imported asset.
    require(exact_triangle_nonzero(zero, (tiny, Fraction(0), Fraction(0)),
                                   (Fraction(0), Fraction(0), tiny)), "tiny exact triangle hand control")
    require(not exact_triangle_nonzero(zero, zero, (tiny, Fraction(0), Fraction(0))), "zero triangle hand control")
    require(not exact_triangle_nonzero(zero, (tiny, Fraction(0), Fraction(0)),
                                       (2 * tiny, Fraction(0), Fraction(0))), "collinear triangle hand control")


def imported_triangle_gate(receipt):
    require(sys.byteorder == "little", "initial imported-word proof supports little-endian host only")
    rows = receipt.get("resources")
    require(type(rows) is list and len(rows) == 6, "six actual imported readbacks required")
    total_triangles = 0
    for row, (kind, lod, root_name) in zip(rows, ROSTER):
        require(row.get("id") == kind and row.get("lod") == lod and row.get("root") == root_name, "actual import roster mismatch")
        meshes = row.get("meshes")
        require(type(meshes) is list and len(meshes) == 3 and {m.get("name") for m in meshes} == {"Bark", "InnerNeedles", "OuterNeedles"}, "actual mesh readback roster")
        vertices, triangles = 0, 0
        for mesh in meshes:
            n, count = mesh.get("vertices"), mesh.get("indices")
            require(type(n) is int and 1 <= n <= (15000 if lod == 0 else 2700), "actual vertex readback bound")
            require(type(count) is int and 3 <= count <= (15000 if lod == 0 else 2700) and count % 3 == 0, "actual index readback bound")
            positions_hex, indices_hex = mesh.get("positions_f32_le_hex"), mesh.get("indices_i32_le_hex")
            require(type(positions_hex) is str and len(positions_hex) == 24 * n and all(c in "0123456789abcdef" for c in positions_hex), "exact12byte imported position words required")
            require(type(indices_hex) is str and len(indices_hex) == 8 * count and all(c in "0123456789abcdef" for c in indices_hex), "exact4byte imported index words required")
            positions_raw, indices_raw = bytes.fromhex(positions_hex), bytes.fromhex(indices_hex)
            positions = []
            for xyz in struct.iter_unpack("<3f", positions_raw):
                require(all(math.isfinite(value) for value in xyz), "nonfinite actual imported position")
                positions.append(tuple(Fraction.from_float(value) for value in xyz))
            indices = [item[0] for item in struct.iter_unpack("<i", indices_raw)]
            require(all(0 <= index < n for index in indices), "actual imported index outside vertices")
            for offset in range(0, count, 3):
                require(exact_triangle_nonzero(positions[indices[offset]], positions[indices[offset + 1]], positions[indices[offset + 2]]), "exact degenerate actual imported triangle")
            vertices += n
            triangles += count // 3
        require(vertices <= (15000 if lod == 0 else 2700) and triangles <= (5000 if lod == 0 else 900), "actual aggregate geometry ceilings")
        total_triangles += triangles
    return {"passed": True, "method": "exact Fraction cross products from original imported little-endian Float32/Int32 words", "exports": 6, "triangles_checked": total_triangles,
            "hand_controls": "nonzero2^-40 triangle; zero and collinear controls", "tolerance": "none; mathematical nondegeneracy"}


def verify(godot, source, output):
    math_controls()
    root = ordinary(ROOT, directory=True)
    local = ordinary(root / ".local", directory=True)
    godot = ordinary(godot)
    source = ordinary(source, directory=True)
    output = ordinary(output, exists=False)
    tracked = root / "assets_source/environment/original-evergreens-v1"
    require(source == tracked or (source != local and source.is_relative_to(local)), "source must be fixed tracked leaf or repository .local candidate")
    require(output != local and output.is_relative_to(local), "output must be strictly below .local")
    require(not output.is_relative_to(source) and not source.is_relative_to(output), "source/output must be disjoint")
    ordinary(output.parent, directory=True)
    checker, script = ordinary(HERE / "check_trees.py"), ordinary(HERE / "check_import.gd")
    exports = [ordinary(source / f"exports/{kind}-lod{lod}.glb") for kind, lod, _ in ROSTER]
    source_files = [source / "original-evergreens.blend", source / "evergreen-source-v1.json", *exports]
    controls = [checker, script, Path(__file__).absolute(), root / "docs/contracts/world/original-evergreens-v1.md",
                root / "assets_source/environment/original-evergreens-v1/generate_trees.py",
                root / "third_party/licenses/notices/OriginalEvergreens-MIT.txt"]
    all_inputs = {str(path): identity(path) for path in [*source_files, *controls]}
    tools = {"godot": {"path": str(godot), **identity(godot)}, "python": {"path": sys.executable, **identity(ordinary(Path(sys.executable)))}}
    output.mkdir()
    write_json(output / "inputs-before.json", {"sources": all_inputs, "tools": tools})
    # Public checker CLI/exit status only: its JSON output is diagnostic, not an API.
    run([sys.executable, "-I", "-B", "-S", checker, "--source-dir", source], output, "source-check", 180)
    version = run([godot, "--version"], output, "godot-version", 30).strip()
    require(version.startswith("4.7.2.stable."), "Godot must be admitted 4.7.2 stable")
    project = output / "project"
    project.mkdir()
    (project / "trees").mkdir()
    (project / "evidence").mkdir()
    shutil.copyfile(script, project / "check_import.gd")
    require(identity(project / "check_import.gd") == all_inputs[str(script)], "staged reviewed script mismatch")
    roster = []
    for (kind, lod, node), path in zip(ROSTER, exports):
        target = project / "trees" / path.name
        shutil.copyfile(path, target)
        require(identity(target) == all_inputs[str(path)], "staged GLB mismatch")
        # Explicit reviewed importer preset, before the first import. Verify the
        # resulting actual sidecar too; no auto-LOD decimation is permitted.
        target.with_suffix(".glb.import").write_text(
            '[remap]\nimporter="scene"\ntype="PackedScene"\n[params]\nmeshes/generate_lods=false\nmeshes/force_disable_compression=true\n', encoding="utf-8", newline="\n")
        roster.append({"id": kind, "lod": lod, "node": node, "path": "res://trees/" + path.name, **identity(target)})
    write_json(project / "source-identities.json", {"exports": roster, "controls": all_inputs, "tool": tools["godot"], "version": version})
    (project / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="ISOLATED original evergreen study - NOT CURRENT GAME"\n'
        '[display]\nwindow/size/viewport_width=1280\nwindow/size/viewport_height=720\n'
        'window/size/window_width_override=1280\nwindow/size/window_height_override=720\nwindow/size/resizable=false\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\nrenderer/rendering_method.mobile="gl_compatibility"\n',
        encoding="utf-8", newline="\n")
    base = [godot, "--path", project, "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3", "--audio-driver", "Dummy"]
    run([*base, "--headless", "--editor", "--import"], output, "import", 180)
    for target in (project / "trees").glob("*.glb.import"):
        actual_flags = target.read_text(encoding="utf-8").replace(" ", "")
        require('meshes/generate_lods=false' in actual_flags and 'meshes/force_disable_compression=true' in actual_flags,
                "actual import sidecar must disable auto LOD and compression")
    run([*base, "--headless", "--script", "res://check_import.gd", "--", "resources"], output, "resources", 180)
    resources = read_json(project / "evidence/resources.json")
    require(resources.get("passed") is True and resources.get("mode") == "resources", "headless resource checks incomplete")
    require(engine_version(resources) == version, "actual headless engine identity mismatch")
    resource_triangle_gate = imported_triangle_gate(resources)
    run([*base, "--resolution", "1280x720", "--fixed-fps", "60", "--script", "res://check_import.gd", "--", "visible"], output, "visible", 1200)
    visible = read_json(project / "evidence/visible.json")
    require(visible.get("passed") is True and len(visible.get("stills", [])) == 36 and len(visible.get("approaches", [])) == 6, "visible capture roster incomplete")
    require(engine_version(visible) == version and visible.get("mode") == "visible", "actual visible engine identity mismatch")
    require(resources.get("sources") == read_json(project / "source-identities.json") == visible.get("sources"), "actual proof source identities mismatch")
    visible_triangle_gate = imported_triangle_gate(visible)
    images = []
    for image in sorted((project / "evidence").glob("*.png")):
        require(image.stat().st_size <= 8 * 1024 * 1024, "image byte bound exceeded")
        images.append({"path": image.relative_to(output).as_posix(), **identity(image)})
    require(len(images) == 1 + 36 + 6 * 301, "expected background control,36 stills and six301-sample inclusive0..5s sequences")
    require(sum(row["bytes"] for row in images) <= 8 * 1024**3, "capture aggregate byte bound exceeded")
    require(all_inputs == {path: identity(Path(path)) for path in all_inputs}, "source/control changed during proof")
    require(tools["godot"]["sha256"] == sha(godot), "Godot binary changed during proof")
    require(tools["python"]["sha256"] == sha(Path(sys.executable)), "Python binary changed during proof")
    require(identity(project / "check_import.gd") == all_inputs[str(script)], "staged reviewed script changed during proof")
    imported = {path.relative_to(project).as_posix(): identity(path) for path in sorted((project / ".godot/imported").glob("*")) if path.is_file()}
    controls_after = {path.relative_to(project).as_posix(): identity(path) for path in
                      [project / "project.godot", project / "check_import.gd", project / "source-identities.json",
                       *sorted((project / "trees").glob("*.glb.import")),
                       *sorted((project / "evidence").glob("*.json")), *sorted((project / "evidence").glob("*.jsonl"))]}
    receipt = {"kind": "isolated-original-evergreen-study-v1", "utc": datetime.now(timezone.utc).isoformat(),
               "resources_passed": True, "captures_complete": True, "visual_acceptance": "Root review required; no automatic aesthetic/temporal pass",
               "sources": all_inputs, "tools": tools, "version": version, "imported_files": imported, "proof_control_files": controls_after,
               "resources": resources, "visible": visible, "exact_imported_triangle_gates": {"headless": resource_triangle_gate, "visible": visible_triangle_gate}, "original_images": images,
               "material_color_correspondence": "source factors passed independent exact1e-6 gate; imported RGB inverse differences are non-gating advisories requiring Root review",
               "scope": "isolated decorative art only; not current game, KAWO placement, flight, botanical or performance acceptance"}
    write_json(output / "receipt.json", receipt)
    print(json.dumps({"receipt": str(output / "receipt.json"), "resources_passed": True, "captures_complete": True, "visual_acceptance": "pending Root review"}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    verify(args.godot, args.source_dir, args.output)






