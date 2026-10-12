#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Precompile storage identity reconstruction; never executes selected input files.

The plan is an independently source-reviewed configure declaration, not evidence
that a compiler used those target properties. Actual commands/objects/link inputs
are mandatory postbuild qualifier witnesses and deliberately cannot enter here.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import zipfile

ALLOCATION = "docs/contracts/local-players/compiled-source-allocation-v1.json"
ALLOCATION_SHA256 = "ac04b370a2861213b008680eedb1b62f8a434c61468e2d913c9e05e9a522192a"
SCALARS = (
    "c_compiler_id", "c_compiler_version", "c_compiler_executable_sha256",
    "cxx_compiler_id", "cxx_compiler_version", "cxx_compiler_executable_sha256",
    "generator", "configuration", "c_flags", "c_configuration_flags", "cxx_flags",
    "cxx_configuration_flags", "sqlite_compile_definitions", "sqlite_compile_options",
    "sqlite_include_directories_sha256", "msvc_runtime_c", "msvc_runtime_cxx",
    "precision", "godot_api", "declared_numeric_flags", "platform",
)
POSTBUILD = ("sqlite_c_compile_command_sha256", "sqlite_static_archive_sha256",
             "sqlite_object_roster_sha256", "storage_link_command_sha256")
TEMPLATE = (
    'extends RefCounted\nconst SCHEMA: String = "flight-local-players-component-v1"\n'
    'const COMPONENT_FINGERPRINT: String = "@FLIGHT_LOCAL_PLAYERS_COMPONENT_SHA256@"\n'
    'const BUILD_CONTROL_SHA256: String = "@FLIGHT_LOCAL_PLAYERS_BUILD_CONTROL_SHA256@"\n'
    'const CONTRACT_SHA256: String = "@FLIGHT_LOCAL_PLAYERS_CONTRACT_SHA256@"\n'
)
MAX_TEXT = 16 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def exact_keys(value, keys, label):
    require(type(value) is dict and set(value) == set(keys), label + ": closed keys")


def scalar(value, label, empty=False):
    require(type(value) is str and (empty or bool(value)) and len(value) <= 65536,
            label + ": bounded actual String required")
    require(not any(ord(c) < 32 or ord(c) == 127 for c in value), label + ": control character")
    value.encode("utf-8", "strict")
    return value


def digest(value, label):
    require(type(value) is str and re.fullmatch(r"[0-9a-f]{64}", value) is not None,
            label + ": lowercase SHA256 required")
    return value


def ordinary(path, directory=False):
    path = Path(os.path.abspath(path))
    for part in (*reversed(path.parents), path):
        info = part.lstat()
        require(not stat.S_ISLNK(info.st_mode) and not (getattr(info, "st_file_attributes", 0) & 0x400),
                "symlink/reparse input: " + str(part))
    require(path.is_dir() if directory else path.is_file(), "wrong file kind: " + str(path))
    return path.resolve(strict=True)


def relative(value):
    scalar(value, "relative path")
    p = PurePosixPath(value)
    require(not p.is_absolute() and not any(c in value for c in "\\:\x00") and
            all(x not in ("", ".", "..") for x in value.split("/")) and str(p) == value,
            "unsafe relative path: " + value)
    return value


def under(root, name):
    value = ordinary(root / relative(name))
    require(value.is_relative_to(root), "input escaped root")
    return value


def read(path, maximum=MAX_TEXT):
    require(path.stat().st_size <= maximum, "input exceeds source-reading bound: " + str(path))
    data = path.read_bytes()
    require(len(data) <= maximum, "input grew past bound")
    return data


def lf(data, exact=False):
    text = data.decode("utf-8", "strict")
    require(not text.startswith("\ufeff") and "\x00" not in text, "BOM/NUL text input")
    require("\r" not in text.replace("\r\n", ""), "bare CR text input")
    normalized = text.replace("\r\n", "\n").encode("utf-8")
    require(bool(text.strip()), "empty/unwritten source input")
    if exact:
        require(data == normalized and data.endswith(b"\n"), "normative source must be exact UTF8 LF with final LF")
    return normalized


def pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, "duplicate JSON key: " + key)
        result[key] = value
    return result


def load_json(data):
    return json.loads(data.decode("utf-8", "strict"), object_pairs_hook=pairs,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError("nonfinite JSON " + value)))


def canonical(value):
    return (json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":"),
                       allow_nan=False) + "\n").encode("utf-8")


def ordered_body(rows):
    return "".join(path + ":" + value + "\n" for path, value in rows).encode("utf-8")


def path_token(path, source_root, build_root):
    # Only the two tokens authorized by the accepted command-binding recipe.
    # Longest actual root first handles a build tree inside the source tree.
    for root, token in sorted(((source_root, "@source_root"), (build_root, "@build_root")),
                              key=lambda item: len(str(item[0])), reverse=True):
        if path.is_relative_to(root):
            tail = path.relative_to(root).as_posix()
            return token if tail == "." else token + "/" + tail
    return path.as_posix()


def file_record(path, expected=None):
    path = ordinary(path)
    data = read(path, 1024 * 1024 * 1024)
    result = {"path": path.as_posix(), "bytes": len(data), "sha256": sha(data)}
    if expected is not None:
        require(result["sha256"] == digest(expected, "file digest"), "file digest mismatch: " + str(path))
    return result, data


def declared_file(value, label):
    exact_keys(value, ("path", "sha256"), label)
    scalar(value["path"], label + " path")
    require(Path(value["path"]).is_absolute(), label + ": absolute path required")
    return file_record(value["path"], value["sha256"])


def cache_values(data):
    result = {}
    for line in lf(data).decode("utf-8").splitlines():
        if not line or line.startswith(("#", "//")):
            continue
        match = re.fullmatch(r"([^#/:][^:]*):[^=]+=(.*)", line)
        require(match is not None, "unsupported CMake cache line")
        key, value = match.groups()
        require(key not in result, "duplicate CMake cache key")
        result[key] = value
    return result


def compiler_sets(data, lang, platform):
    text = lf(data).decode("utf-8")
    result = {}
    for suffix in ("COMPILER", "COMPILER_ID", "COMPILER_VERSION"):
        key = "CMAKE_" + lang + "_" + suffix
        found = re.findall(r"(?m)^set\(" + re.escape(key) + r' "([^"\r\n]*)"\)\s*$', text)
        require(len(found) == 1, "missing/ambiguous literal compiler record: " + key)
        require("$" not in found[0] and ";" not in found[0], "unevaluated compiler record")
        result[suffix] = found[0]
    target_fields = [("SIZEOF_DATA_PTR", "8")]
    if platform == "Windows-x64":
        target_fields.append(("COMPILER_ARCHITECTURE_ID", "x64"))
    else:
        target_fields.extend((("COMPILER_ABI", "ELF"), ("BYTE_ORDER", "LITTLE_ENDIAN"),
                              ("LIBRARY_ARCHITECTURE", "x86_64-linux-gnu")))
    for suffix, expected in target_fields:
        key = "CMAKE_" + lang + "_" + suffix
        found = re.findall(r"(?m)^set\(" + re.escape(key) + r' (?:"([^"\r\n]*)"|([^\s"()]+))\)\s*$', text)
        require(len(found) == 1 and (found[0][0] or found[0][1]) == expected,
                "compiler target must be x64: " + key)
    return result


def configure(plan, source_root, dependency_root):
    exact_keys(plan, ("schema", "compiled_build_scalars", "compiler_files", "configure_provenance",
                      "sqlite_include_directories"), "build plan")
    require(plan["schema"] == "LocalPlayersPrecompilePlan/v1", "plan schema")
    values = plan["compiled_build_scalars"]
    exact_keys(values, SCALARS, "compiled scalars (postbuild witnesses forbidden)")
    for key in SCALARS:
        scalar(values[key], key, empty=key in ("c_flags", "c_configuration_flags", "cxx_flags",
               "cxx_configuration_flags", "sqlite_compile_options"))
    require(values["platform"] in ("Windows-x64", "Linux-x64"), "unsupported storage identity platform")
    windows = values["platform"] == "Windows-x64"
    require(values["generator"] == "Ninja" and values["configuration"] in
            ("Debug", "Release", "RelWithDebInfo", "MinSizeRel"), "unsupported generator/configuration")
    require(values["precision"] == "single" and values["godot_api"] == "4.5", "binding ABI mismatch")
    numeric_flags = "/fp:strict" if windows else "-fno-fast-math -ffp-contract=off -frounding-math"
    require(values["declared_numeric_flags"] == numeric_flags, "platform strict numeric declaration")
    defines = values["sqlite_compile_definitions"].split(";")
    require(len(defines) == 2 and set(defines) ==
            {"SQLITE_THREADSAFE=1", "SQLITE_OMIT_LOAD_EXTENSION=1"}, "SQLite definitions")
    forbidden = re.compile(r"(?i)(?:/fp:(?:fast|precise)|-Ofast|-ffast-math|-ffinite-math-only|"
        r"-funsafe-math-optimizations|-fassociative-math|-freciprocal-math|-fno-signed-zeros|"
        r"-fno-trapping-math|-fno-rounding-math|-ffp-contract=fast|(?:^|[\s;])-m(?:32|x32)(?:[\s;]|$)|"
        r"/MTd?(?:[\s;]|$)|/arch:IA32|\$<)")
    for key in ("c_flags", "c_configuration_flags", "cxx_flags", "cxx_configuration_flags", "sqlite_compile_options"):
        require(not forbidden.search(values[key]), "unsupported numeric/runtime option: " + key)
    exact_keys(plan["compiler_files"], ("c", "cxx"), "compiler_files")
    prov = plan["configure_provenance"]
    exact_keys(prov, ("cache", "c_compiler_record", "cxx_compiler_record"), "configure provenance")
    cache_record, cache_data = declared_file(prov["cache"], "cache")
    cache_path = Path(cache_record["path"])
    require(cache_path.name == "CMakeCache.txt", "cache filename")
    build_root = ordinary(cache_path.parent, True)
    require(build_root != source_root, "in-source build unsupported")
    cache = cache_values(cache_data)
    for key, path in (("CMAKE_CACHEFILE_DIR", build_root), ("CMAKE_HOME_DIRECTORY", source_root),
                      ("FLIGHT_DEPENDENCY_ROOT", dependency_root)):
        require(key in cache and Path(cache[key]).is_absolute() and ordinary(cache[key], True) == path,
                "configure root mismatch: " + key)
    for key, scalar_key in (("CMAKE_GENERATOR", "generator"), ("CMAKE_BUILD_TYPE", "configuration"),
                            ("CMAKE_C_FLAGS", "c_flags"), ("CMAKE_CXX_FLAGS", "cxx_flags"),
                            ("CMAKE_C_FLAGS_" + values["configuration"].upper(), "c_configuration_flags"),
                            ("CMAKE_CXX_FLAGS_" + values["configuration"].upper(), "cxx_configuration_flags")):
        require(key in cache and cache[key] == values[scalar_key], "cache/scalar mismatch: " + key)
    require(cache.get("FLIGHT_BUILD_LOCAL_PLAYERS") == ("ON" if windows else "OFF"),
            "Windows production storage ON / Linux shipping extension OFF required")
    require(cache.get("FLIGHT_BUILD_GODOT_BINDINGS") in (("ON",) if windows else ("ON", "OFF")),
            "binding build option missing/unsupported")
    require(windows or cache.get("BUILD_TESTING") == "ON", "Linux route requires actual pure-core tests")
    require(cache.get("CMAKE_EXPORT_COMPILE_COMMANDS") == "ON", "compile commands required for later qualification")
    for key, expected in (("GODOTCPP_PRECISION", "single"), ("GODOTCPP_TARGET", "template_release"),
                          ("GODOTCPP_USE_STATIC_CPP", "OFF"), ("GODOTCPP_DISABLE_EXCEPTIONS", "OFF")):
        require((cache.get("FLIGHT_BUILD_GODOT_BINDINGS") == "OFF" and key not in cache) or cache.get(key) == expected,
                "binding cache ABI mismatch: " + key)
    if cache.get("FLIGHT_BUILD_GODOT_BINDINGS") == "ON" or "GODOTCPP_BUILD_PROFILE" in cache:
        require("GODOTCPP_BUILD_PROFILE" in cache and Path(cache["GODOTCPP_BUILD_PROFILE"]).is_absolute() and
                ordinary(cache["GODOTCPP_BUILD_PROFILE"]) == under(source_root, "tools/bootstrap/binding-profile.json"),
                "binding profile cache mismatch")
    runtime = cache.get("CMAKE_MSVC_RUNTIME_LIBRARY", "").replace(
        "$<$<CONFIG:Debug>:Debug>", "Debug" if values["configuration"] == "Debug" else "")
    if windows:
        expected_runtime = "MultiThreadedDebugDLL" if values["configuration"] == "Debug" else "MultiThreadedDLL"
        require(runtime == expected_runtime == values["msvc_runtime_c"] == values["msvc_runtime_cxx"], "dynamic CRT mismatch")
    else:
        # This CMake property is not applicable to GNU. Retain any exact cached
        # spelling in hashed cache provenance; never pretend it selected MSVC CRT.
        require(values["msvc_runtime_c"] == values["msvc_runtime_cxx"] == "not-applicable",
                "GNU runtime scalars must explicitly be not-applicable")
        require(cache.get("CMAKE_MSVC_RUNTIME_LIBRARY", "") in
                ("", "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL"), "unexpected ignored MSVC cache property")
    records = {"cache": cache_record}
    for lang, prefix in (("C", "c"), ("CXX", "cxx")):
        record, data = declared_file(prov[prefix + "_compiler_record"], prefix + " compiler record")
        path = Path(record["path"])
        require(path.is_relative_to(build_root / "CMakeFiles") and path.name == "CMake" + lang + "Compiler.cmake",
                "compiler record outside configured build")
        candidates = list((build_root / "CMakeFiles").glob("*/CMake" + lang + "Compiler.cmake"))
        require(len(candidates) == 1 and ordinary(candidates[0]) == path, "ambiguous configured compiler records")
        declared = compiler_sets(data, lang, values["platform"])
        compiler, raw = declared_file(plan["compiler_files"][prefix], prefix + " compiler executable")
        cached_compiler = cache["CMAKE_" + lang + "_COMPILER"]
        require(Path(declared["COMPILER"]).is_absolute() and Path(cached_compiler).is_absolute() and
                ordinary(declared["COMPILER"]) == Path(compiler["path"]) == ordinary(cached_compiler),
                "compiler path mismatch")
        require(declared["COMPILER_ID"] == values[prefix + "_compiler_id"] == ("MSVC" if windows else "GNU"),
                "compiler ID/platform mismatch")
        version = declared["COMPILER_VERSION"]
        require(version == values[prefix + "_compiler_version"], "compiler version mismatch")
        if windows:
            require(re.fullmatch(r"19\.(?:[4-9][0-9])(?:\.[0-9]+){0,2}", version) is not None,
                    "unsupported MSVC version")
        else:
            require(re.fullmatch(r"[0-9]{1,3}(?:\.[0-9]{1,6}){1,3}", version) is not None and
                    int(version.split(".")[0]) >= 13, "GNU >=13 exact version required")
        for suffix in ("COMPILER_ID", "COMPILER_VERSION"):
            key = "CMAKE_" + lang + "_" + suffix
            require(key not in cache or cache[key] == declared[suffix], "cache compiler declaration mismatch")
        require(compiler["sha256"] == values[prefix + "_compiler_executable_sha256"], "compiler scalar SHA mismatch")
        if windows:
            require(raw[:2] == b"MZ" and len(raw) >= 64, "compiler must be actual PE file")
            offset = int.from_bytes(raw[60:64], "little")
            require(offset + 6 <= len(raw) and raw[offset:offset + 6] == b"PE\x00\x00d\x86", "compiler must be PE AMD64")
        else:
            require(len(raw) >= 64 and raw[:7] == b"\x7fELF\x02\x01\x01" and
                    int.from_bytes(raw[16:18], "little") in (2, 3) and raw[18:20] == b">\x00" and
                    raw[20:24] == b"\x01\x00\x00\x00", "compiler must be ELF64 little-endian AMD64 executable/shared binary")
        records[prefix + "_compiler_record"] = record
        records[prefix + "_compiler"] = compiler
    includes = plan["sqlite_include_directories"]
    require(type(includes) is list and len(includes) == 1 and type(includes[0]) is str and
            Path(includes[0]).is_absolute(), "exact declared SQLite include directory required")
    include = ordinary(includes[0], True)
    require(include == ordinary(dependency_root / "sqlite", True), "SQLite include does not select verified header")
    # Canonical precompile include provenance, fixed spelling/order, final LF.
    include_record = {"schema": "LocalPlayersSQLiteIncludeProvenance/v1", "directories": [
        {"path": path_token(include, source_root, build_root),
         "sqlite_header_sha256": sha(read(ordinary(include / "sqlite3.h")))}]}
    include_bytes = canonical(include_record)
    require(sha(include_bytes) == values["sqlite_include_directories_sha256"], "include provenance digest mismatch")
    return values, build_root, records, include_record, include_bytes


def tree_entries(root):
    """Validate each directory BEFORE descent; never enumerate through reparse roots."""
    result = []
    pending = [root]
    aliases = set()
    while pending:
        for path in pending.pop().iterdir():
            info = path.lstat()
            require(stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode), "special dependency entry")
            safe = ordinary(path, stat.S_ISDIR(info.st_mode))
            name = safe.relative_to(root).as_posix()
            require(name.casefold() not in aliases, "dependency tree case alias")
            aliases.add(name.casefold())
            result.append(safe)
            if safe.is_dir():
                pending.append(safe)
    return sorted(result)


def verified_dependency(repo, deps, item):
    root = ordinary(deps / item["id"], True)
    archive = ordinary(repo / ".local/download-cache" / (digest(item["sha256"], "archive SHA") + ".archive"))
    archive_record, _ = file_record(archive, item["sha256"])
    marker = load_json(read(ordinary(root / ".verified.json")))
    exact_keys(marker, ("id", "version", "url", "sha256", "tree_sha256"), "bootstrap source receipt")
    for key in ("id", "version", "url", "sha256"):
        require(marker[key] == item[key], "dependency receipt mismatch: " + key)
    digest(marker["tree_sha256"], "receipt tree SHA")
    expected = {}
    expected_dirs = set()
    aliases = set()
    archive_names = set()
    total = 0
    with zipfile.ZipFile(archive) as zipped:
        require(len(zipped.infolist()) <= 100000, "dependency archive member cap")
        for entry in zipped.infolist():
            name = entry.filename.rstrip("/")
            relative(name)
            require(name.casefold() not in archive_names, "archive duplicate/case alias entry")
            archive_names.add(name.casefold())
            require(name.split("/")[0] == item["archive_root"], "archive root mismatch")
            require(not stat.S_ISLNK(entry.external_attr >> 16), "archive symlink")
            tail = name[len(item["archive_root"]):].lstrip("/")
            if tail:
                for parent in PurePosixPath(tail).parents:
                    if str(parent) != ".":
                        expected_dirs.add(str(parent))
            if entry.is_dir():
                if tail:
                    expected_dirs.add(tail)
                continue
            relative(tail)
            require(tail.casefold() not in aliases and tail != ".verified.json", "archive duplicate/case alias/marker")
            aliases.add(tail.casefold())
            total += entry.file_size
            require(total <= 4 * 1024 ** 3 and entry.file_size <= 512 * 1024 ** 2, "dependency expansion bound")
            with zipped.open(entry) as stream:
                h = hashlib.sha256()
                count = 0
                while chunk := stream.read(1024 * 1024):
                    count += len(chunk)
                    require(count <= entry.file_size, "archive member excess")
                    h.update(chunk)
            require(count == entry.file_size, "archive member truncation")
            expected[tail] = h.hexdigest()
    actual = {}
    actual_dirs = set()
    entries = tree_entries(root)
    for safe in entries:
        if safe.is_dir():
            actual_dirs.add(safe.relative_to(root).as_posix())
            continue
        name = safe.relative_to(root).as_posix()
        if name == ".verified.json":
            continue
        actual[name] = sha(read(safe, 512 * 1024 ** 2))
    require(bool(expected) and actual == expected and actual_dirs == expected_dirs,
            "extracted dependency differs from locked archive: " + item["id"])
    # Bootstrap sorts concrete Paths, then hashes relative name + raw digest.
    h = hashlib.sha256()
    for path in entries:
        if path.is_file() and path.name != ".verified.json":
            h.update(path.relative_to(root).as_posix().encode("utf-8"))
            h.update(bytes.fromhex(actual[path.relative_to(root).as_posix()]))
    require(h.hexdigest() == marker["tree_sha256"], "bootstrap tree digest mismatch")
    return {"archive": archive_record, "receipt": marker, "files": [
        {"path": name, "sha256": actual[name]} for name in sorted(actual)]}


def construct(repo, deps, plan_path):
    allocation_data = read(under(repo, ALLOCATION))
    require(sha(allocation_data) == ALLOCATION_SHA256, "reviewed allocation bytes changed; explicit source amendment required")
    allocation = load_json(lf(allocation_data, True))
    sources = [row["path"] for row in allocation["ordered_storage_component_sources"]]
    controls = allocation["ordered_storage_build_controls"]
    contracts = allocation["ordered_contract_inputs"]
    identity = allocation["storage_identity"]
    require(tuple(identity["compiled_build_scalar_keys"]) == SCALARS and
            tuple(identity["postbuild_witness_keys"]) == POSTBUILD, "accepted scalar partition mismatch")
    source_rows, control_rows, contract_rows = [], [], []
    bindings = []
    # ALL17 sources checked first; missing code cannot produce an output root.
    for paths, count, rows, exact in ((sources, 17, source_rows, False),
                                     (controls, 15, control_rows, False), (contracts, 11, contract_rows, True)):
        require(len(paths) == count and len(set(p.casefold() for p in paths)) == count, "accepted roster mismatch")
        for name in paths:
            try:
                raw = read(under(repo, name))
            except OSError as error:
                raise ValueError("missing/unreadable allocated input: " + name + ": " + str(error)) from error
            normal = lf(raw, exact)
            rows.append((name, sha(normal)))
            bindings.append({"path": name, "bytes": len(raw), "raw_sha256": sha(raw),
                             "identity_sha256": sha(normal), "normalization": "exact-UTF8-LF" if exact else "CRLF-to-LF-only"})
    template = lf(read(under(repo, "native/persistence/local_players/storage_identity.gd.in")))
    require(template == TEMPLATE.encode("utf-8"), "identity template is not exact reviewed five-line template")
    lock = load_json(read(under(repo, "third_party/dependencies.lock.json")))
    require(lock["schema_version"] == 1 and lock["cpp_standard"] == 20 and lock["precision"] == "single" and
            lock["godot_binding_api"] == "4.5" and lock["windows_crt"] == "dynamic (/MD; /MDd for Debug)", "dependency ABI")
    source_items = {}
    for item in lock["sources"]:
        require(item["id"] not in source_items, "duplicate dependency ID")
        source_items[item["id"]] = item
    require(re.fullmatch(r"[0-9a-f]{40}", source_items["godot-cpp"]["commit"]) is not None and
            re.fullmatch(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [0-9a-f]{64}",
                         source_items["sqlite"]["source_id"]) is not None, "dependency source identifiers")
    dependencies = {key: verified_dependency(repo, deps, source_items[key]) for key in ("sqlite", "godot-cpp")}
    sqlite_c = read(ordinary(deps / "sqlite/sqlite3.c"))
    sqlite_h = read(ordinary(deps / "sqlite/sqlite3.h"))
    for raw in (sqlite_c, sqlite_h):
        text = raw.decode("utf-8", "strict")
        for key, expected in (("SQLITE_VERSION", source_items["sqlite"]["version"]),
                              ("SQLITE_SOURCE_ID", source_items["sqlite"]["source_id"])):
            found = re.findall(r'(?m)^#define ' + key + r' +"([^"\r\n]+)"\r?$', text)
            require(found == [expected], "SQLite source/header identity mismatch: " + key)
    binding = load_json(read(under(repo, "schemas/save/local-players/v1/schema-binding-v1.json")))
    require(sha(read(under(repo, "schemas/save/local-players/v1/schema-v1.sql"))) == binding["schema_fingerprint"] and
            sha(read(under(repo, "schemas/save/local-players/v1/preferences-codec-v1.json"))) == binding["codec_fingerprint"],
            "SQL/codec raw binding mismatch")
    plan_record, plan_data = file_record(plan_path)
    values, build, provenance, includes, include_bytes = configure(load_json(plan_data), repo, deps)
    build_body = ordered_body(control_rows + [(key, values[key]) for key in SCALARS])
    contract_body = ordered_body(contract_rows)
    build_sha, contract_sha = sha(build_body), sha(contract_body)
    component_body = ("flight-local-players-component-v1\n" +
        "storage-build-controls:" + build_sha + "\n" + "storage-contracts:" + contract_sha + "\n" +
        "sqlite-source:" + source_items["sqlite"]["source_id"] + "\n" +
        "sqlite-amalgamation:" + sha(sqlite_c) + "\n" + "sqlite-header:" + sha(sqlite_h) + "\n" +
        "godot-cpp:" + source_items["godot-cpp"]["commit"] + "\n").encode("utf-8") + ordered_body(source_rows)
    component_sha = sha(component_body)
    resource = TEMPLATE.replace("@FLIGHT_LOCAL_PLAYERS_COMPONENT_SHA256@", component_sha).replace(
        "@FLIGHT_LOCAL_PLAYERS_BUILD_CONTROL_SHA256@", build_sha).replace(
        "@FLIGHT_LOCAL_PLAYERS_CONTRACT_SHA256@", contract_sha).encode("utf-8")
    evidence = {"schema": "LocalPlayersPrecompileSourceIdentity/v1", "scope": "source reconstruction; NOT compile/runtime qualification",
        "platform_scope": "Windows storage component, later shipping qualification required" if values["platform"] == "Windows-x64" else
                          "Linux reusable core/codec only; no shipping GDExtension/Win32/store runtime qualification",
        "component_fingerprint": component_sha, "build_control_sha256": build_sha, "contract_sha256": contract_sha,
        "source_root": repo.as_posix(), "build_root": build.as_posix(), "dependency_root": deps.as_posix(),
        "allocation_sha256": ALLOCATION_SHA256, "build_plan": plan_record, "compiled_build_scalars": values,
        "source_bindings": bindings, "dependencies": dependencies, "configure_provenance": provenance,
        "sqlite_include_provenance": includes, "sqlite_include_provenance_utf8": include_bytes.decode("utf-8"),
        "build_digest_body_utf8": build_body.decode("utf-8"), "contracts_digest_body_utf8": contract_body.decode("utf-8"),
        "component_digest_body_utf8": component_body.decode("utf-8"), "postbuild_witnesses_required": list(POSTBUILD),
        "generated_resource": {"path": "local-players-identity.gd", "bytes": len(resource), "sha256": sha(resource)}}
    return resource, canonical(evidence)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ("repo-root", "dependency-root", "build-plan", "output-root"):
        parser.add_argument("--" + option, required=True)
    args = parser.parse_args()
    try:
        repo = ordinary(args.repo_root, True)
        deps = ordinary(args.dependency_root, True)
        plan = ordinary(args.build_plan)
        output = Path(os.path.abspath(args.output_root))
        parent = ordinary(output.parent, True)
        require(not output.exists() and not output.is_symlink(), "output root must be fresh")
        require(parent != deps and not parent.is_relative_to(deps), "output cannot enter dependencies")
        resource, evidence = construct(repo, deps, plan)
        # Immutable reviewed inputs are required. Reconstruct a second time to
        # catch ordinary concurrent edits; this is not a hostile TOCTOU claim.
        require(construct(repo, deps, plan) == (resource, evidence), "inputs changed while reconstructing")
        output.mkdir()  # First write, only after every input and recipe passed.
        for name, data in (("local-players-identity.gd", resource), ("local-players-source-identity.json", evidence)):
            with (output / name).open("xb") as stream:
                stream.write(data)
        print("LOCAL PLAYERS SOURCE IDENTITY WRITTEN (precompile only)")
        return 0
    except (OSError, ValueError, KeyError, TypeError, UnicodeError, zipfile.BadZipFile) as error:
        print("LOCAL PLAYERS SOURCE IDENTITY REJECTED: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
