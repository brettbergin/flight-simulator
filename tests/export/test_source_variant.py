"""Source-tool tests ONLY: fabricated text roster, never JSBSim after-images.

Synthetic inventory pin substitution is confined to this test process. It is
not a reviewed upstream inventory, algorithm trial or usable production recipe.
"""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
import zipfile
sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[2]
HERE = REPO / "tools/export/jsbsim-event-aware"
TEST_WORK = REPO / ".local/source-closure-tests"
TEST_WORK.mkdir(parents=True, exist_ok=True)
tempfile.tempdir = str(TEST_WORK)
sys.path.insert(0, str(HERE))
import materialize as m
from verify import verify
from pack import pack

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

builder = load("candidate_builder", REPO / "tools/export/source-bundle-schema2.py")
extractor = load("candidate_extract", REPO / "tools/export/extract-source-schema2.py")

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n", encoding="utf-8", newline="\n")

class SourceTools(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix="synthetic-source-tools-")
        self.root = Path(self.work.name)
        m.require(self.root.resolve().is_relative_to(TEST_WORK.resolve()), "Test cleanup escaped private fixture directory")
        self.pristine = self.root / "pristine"
        self.patch = self.root / "patch"
        names = [*m.TARGETS, *(f"src/fixture-{i:03}.txt" for i in range(277))]
        for i, name in enumerate(names):
            path = self.pristine / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(f"SYNTHETIC ONLY {i}\n".encode())
        inv = {"upstream_commit": m.COMMIT, "acquisition_sha256": m.ACQUISITION,
               "upstream_file_count": 279, "files": list(m.scan(self.pristine).values())}
        write_json(self.patch / "upstream-file-inventory.json", inv)
        self.original_inventory_sha = m.INVENTORY_SHA
        m.INVENTORY_SHA = m.sha(self.patch / "upstream-file-inventory.json")
        self.value = {"schema_version": 1, "patch_kind": "exact-file-replacement-v1", "source_bundle_schema": 2,
                      "source_variant": m.VARIANT, "upstream_commit": m.COMMIT, "acquisition_sha256": m.ACQUISITION,
                      "upstream_inventory_sha256": m.INVENTORY_SHA,
                      "materializer": {"bytes": (HERE / "materialize.py").stat().st_size, "sha256": m.sha(HERE / "materialize.py")},
                      "modifications": {"author": "SYNTHETIC TEST ONLY", "date": "2026-10-09", "license": "LGPL-2.1-or-later",
                                        "method_revision": "event_aware_constant_power_v1"}, "changes": []}
        for name in m.TARGETS:
            before = self.patch / m.PREFIX / (Path(name).name + ".before")
            after = self.patch / "vendor" / name
            before.parent.mkdir(parents=True, exist_ok=True)
            after.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.pristine / name, before)
            after.write_bytes(before.read_bytes() + b"SYNTHETIC REPLACEMENT\n")
            self.value["changes"].append({"path": name,
                "before": {"member": before.relative_to(self.patch).as_posix(), "bytes": before.stat().st_size, "sha256": m.sha(before)},
                "after": {"member": after.relative_to(self.patch).as_posix(), "bytes": after.stat().st_size, "sha256": m.sha(after)}})
        self.license = self.root / "LICENSE"
        self.license.write_text("SYNTHETIC FIRST PARTY LICENSE\n", encoding="utf-8")
        self.repin()

    def tearDown(self):
        m.INVENTORY_SHA = self.original_inventory_sha
        self.work.cleanup()

    def repin(self):
        path = self.patch / m.PREFIX / "recipe.json"
        write_json(path, self.value)
        self.pin = m.sha(path)

    def create(self):
        out = self.root / "bundle"
        result = builder.create(self.pristine, self.patch, HERE, self.license, out, self.pin)
        self.assertEqual(result["source_verification"]["bundle_files"], 291)
        self.assertEqual(result["source_verification"]["unchanged_vendor_files"], 277)
        return out, result

    def test_materialize_reproduce_pack_extract(self):
        original = m.scan(self.pristine)
        out, result = self.create()
        self.assertEqual(m.scan(self.pristine), original)
        archive = out / (m.VARIANT + "-library-source.zip")
        self.assertEqual(result["source_archive_sha256"], m.sha(out / "source-repeat.zip"))
        with zipfile.ZipFile(archive) as z:
            self.assertEqual(len(z.infolist()), 291)
        receipt = extractor.extract(archive, result["source_archive_sha256"], self.root / "extracted")
        self.assertTrue(receipt["provenance_reconstructed"])
        self.assertEqual(m.scan(out / "source"), m.scan(self.root / "extracted"))

    def test_recipe_rejections_before_output(self):
        mutations = [lambda v: v["changes"][0]["after"].update(sha256=None),
                     lambda v: v["changes"].append(copy.deepcopy(v["changes"][0])),
                     lambda v: v["changes"].reverse(),
                     lambda v: v["changes"][0].update(path="../FGPropeller.cpp"),
                     lambda v: v["materializer"].update(sha256="0" * 64),
                     lambda v: v.update(extra=True),
                     lambda v: v["modifications"].update(date="2026-99-99")]
        original = copy.deepcopy(self.value)
        for i, mutate in enumerate(mutations):
            self.value = copy.deepcopy(original)
            mutate(self.value)
            self.repin()
            output = self.root / f"rejected-{i}"
            with self.assertRaises(ValueError):
                m.materialize(self.pristine, self.patch, output, self.pin)
            self.assertFalse(output.exists())

    def test_changed_complete_pristine_and_already_applied(self):
        extra = self.pristine / "extra.txt"
        extra.write_text("extra", encoding="utf-8")
        with self.assertRaises(ValueError):
            m.materialize(self.pristine, self.patch, self.root / "extra-rejected", self.pin)
        extra.unlink()
        for name in m.TARGETS:
            shutil.copyfile(self.patch / "vendor" / name, self.pristine / name)
        with self.assertRaises(ValueError):
            m.materialize(self.pristine, self.patch, self.root / "already-applied", self.pin)

    def test_reused_and_overlapping_roots(self):
        m.materialize(self.pristine, self.patch, self.root / "once", self.pin)
        with self.assertRaises(ValueError):
            m.materialize(self.pristine, self.patch, self.root / "once", self.pin)
        with self.assertRaises(ValueError):
            m.materialize(self.pristine, self.patch, self.pristine / "nested", self.pin)

    def test_rehashed_manifest_cannot_hide_vendor_or_before_image_change(self):
        out, _ = self.create()
        source = out / "source"
        for name in ("vendor/src/fixture-000.txt", m.PREFIX + "FGPropeller.cpp.before", "vendor/" + m.TARGETS[0]):
            path = source / name
            saved = path.read_bytes()
            path.write_bytes(saved + b"corruption")
            manifest = m.read_json(source / "manifest.json")
            manifest["files"] = [e for p, e in m.scan(source).items() if p != "manifest.json"]
            write_json(source / "manifest.json", manifest)
            with self.assertRaises(ValueError):
                verify(source)
            path.write_bytes(saved)
        extra = source / "vendor/forbidden.xml"
        extra.write_bytes(b"<not-allowed/>")
        with self.assertRaises(ValueError):
            verify(source)

    def test_archive_digest_and_unsafe_member_fail_before_extraction(self):
        out, result = self.create()
        archive = out / (m.VARIANT + "-library-source.zip")
        destination = self.root / "bad"
        with self.assertRaises(ValueError):
            extractor.extract(archive, "0" * 64, destination)
        self.assertFalse(destination.exists())
        bad = self.root / "unsafe.zip"
        with zipfile.ZipFile(archive) as src, zipfile.ZipFile(bad, "x") as dst:
            for i, entry in enumerate(src.infolist()):
                if i == 0:
                    entry.filename = "../escape"
                dst.writestr(entry, src.read(src.infolist()[i]))
        with self.assertRaises(ValueError):
            extractor.extract(bad, m.sha(bad), destination)
        self.assertFalse(destination.exists())

    def test_case_alias_hardlink_and_duplicate_json_rejected(self):
        # Windows cannot create case aliases as distinct ordinary files. Check
        # their actual transport/inventory admission instead.
        path = self.patch / "upstream-file-inventory.json"
        original = path.read_bytes()
        value = m.read_json(path)
        value["files"][1]["path"] = value["files"][0]["path"].upper()
        write_json(path, value)
        m.INVENTORY_SHA = m.sha(path)
        with self.assertRaises(ValueError):
            m.inventory(self.patch)
        path.write_bytes(original)
        m.INVENTORY_SHA = m.sha(path)
        import os
        os.link(self.pristine / "src/fixture-000.txt", self.pristine / "hardlink.txt")
        with self.assertRaises(ValueError):
            m.scan(self.pristine)
        (self.pristine / "hardlink.txt").unlink()
        path = self.patch / m.PREFIX / "recipe.json"
        path.write_bytes(b'{"schema_version":1,"schema_version":1}')
        with self.assertRaises(ValueError):
            m.read_json(path)

    def test_legacy_schema1_original_verifier_route(self):
        # Execute the original unchanged verifier against a separate synthetic
        # schema1 source tree. No repository/vendor source is modified.
        source = self.root / "legacy"
        shutil.copytree(self.pristine, source / "vendor")
        for name in ("CMakeLists.txt", "BUILD.md", "verify.py", "pack.py"):
            shutil.copyfile(REPO / "tools/export/jsbsim" / name, source / name)
        shutil.copyfile(self.patch / "upstream-file-inventory.json", source / "upstream-file-inventory.json")
        shutil.copyfile(self.license, source / "LICENSE.first-party.txt")
        write_json(source / "manifest.json", {"schema_version": 1, "vendor_modified": False,
            "files": list(m.scan(source).values())})
        legacy = load("legacy_source_verify", REPO / "tools/export/jsbsim/verify.py")
        self.assertEqual(legacy.verify(source)["bundle_files"], 286)
        with self.assertRaises(ValueError):
            verify(source)

    def test_extra_transport_and_unsafe_names(self):
        extra = self.patch / "vendor/extra.cpp"
        extra.write_bytes(b"SYNTHETIC UNKNOWN SOURCE\n")
        with self.assertRaises(ValueError):
            m.materialize(self.pristine, self.patch, self.root / "extra-transport", self.pin)
        self.assertFalse((self.root / "extra-transport").exists())
        for name in ("../escape", "a/../b", "/root", "a\\b", "C:/file", "a//b", "NUL.txt", "a./b", "a/./b"):
            with self.assertRaises(ValueError):
                m.safe(name)

    def test_control_and_windows_invalid_names_before_extraction(self):
        for character in [*(chr(value) for value in range(32)), chr(127), *'<>"|?*']:
            with self.assertRaises(ValueError):
                m.safe("fixture" + character + ".cpp")
        out, _ = self.create()
        archive = out / (m.VARIANT + "-library-source.zip")
        # Each ZIP is intentionally rehashed so filename admission, rather than
        # the external byte pin, must reject it before creating a destination.
        # NUL is tested directly above: ZipInfo truncates NUL during authoring.
        with zipfile.ZipFile(archive) as source:
            originals = [(entry, source.read(entry)) for entry in source.infolist()]
        for index, character in enumerate(["\t", "\n", chr(31), chr(127), *'<>"|?*']):
            bad = self.root / f"invalid-name-{index}.zip"
            members = [(copy.copy(entry), data) for entry, data in originals]
            members[0][0].filename = "fixture" + character + ".cpp"
            members.sort(key=lambda pair: pair[0].filename)
            with zipfile.ZipFile(bad, "x") as destination_zip:
                for entry, data in members:
                    destination_zip.writestr(entry, data)
            destination = self.root / f"invalid-extract-{index}"
            with self.assertRaises(ValueError):
                extractor.extract(bad, m.sha(bad), destination)
            self.assertFalse(destination.exists())

if __name__ == "__main__":
    unittest.main(verbosity=2)
