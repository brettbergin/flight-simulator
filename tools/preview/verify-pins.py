"""Verify actual cached engine/template trees against the accepted dependency lock."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("bootstrap", ROOT / "tools/bootstrap/bootstrap.py")
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


def verify(toolchain):
    lock_path = ROOT / "third_party/dependencies.lock.json"
    lock = json.loads(lock_path.read_text())
    environment = json.loads((toolchain / "environment.json").read_text(encoding="utf-8-sig"))
    if environment["platform"] != "windows" or environment["lock_sha256"] != bootstrap.digest(lock_path):
        raise ValueError("Toolchain environment/accepted lock mismatch")
    identities = {}
    for name in ("godot", "godot-templates"):
        pin = next(item for item in lock["tools"] if item["id"] == name and item["platform"] in ("windows", "all"))
        directory = toolchain / name
        receipt = json.loads((directory / ".verified.json").read_text())
        if any(receipt[key] != pin[key] for key in ("id", "version", "url", "sha256")):
            raise ValueError(f"{name}: verified archive identity differs from lock")
        actual_tree = bootstrap.tree_digest(directory)
        if actual_tree != receipt["tree_sha256"]:
            raise ValueError(f"{name}: extracted bytes changed")
        executable = directory / (pin["executable"] if name == "godot" else "windows_release_x86_64.exe")
        if not executable.is_file():
            raise ValueError(f"{name}: selected executable missing")
        if name == "godot" and Path(environment["tools"]["godot"]).resolve() != executable.resolve():
            raise ValueError("Environment editor path differs from verified tree")
        identities[name] = {"executable": str(executable.resolve()), "executable_sha256": bootstrap.digest(executable),
                            "tree_sha256": actual_tree, "archive_sha256": pin["sha256"], "version": pin["version"]}
    return {"passed": True, "dependency_lock_sha256": bootstrap.digest(lock_path), "tools": identities}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--toolchain", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(verify(args.toolchain.resolve()), indent=2) + "\n")
