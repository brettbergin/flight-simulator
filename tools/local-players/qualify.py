#!/usr/bin/env python3
"""Original MIT. Build witnesses and explicit authorized focused NativeChecks/BridgeChecks.

No command-string reconstruction. Root must freeze/pin a per-invocation plan
before launching a compiler/linker. Only the explicit authorized prepare-test-root command creates an isolated test root.
Postbuild witness hashes are not inputs to the compiled storage identity.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import ntpath
import os
from pathlib import Path
import re
import stat
import struct
import subprocess
import sys
import time
import uuid

MAX_JSON = 16 * 1024 * 1024
MAX_ARCHIVE = 256 * 1024 * 1024
HEX = re.compile(r"[0-9a-f]{64}\Z")
IDENTITY_KEYS = set("schema scope platform_scope component_fingerprint build_control_sha256 contract_sha256 source_root build_root dependency_root allocation_sha256 build_plan compiled_build_scalars source_bindings dependencies configure_provenance sqlite_include_provenance sqlite_include_provenance_utf8 build_digest_body_utf8 contracts_digest_body_utf8 component_digest_body_utf8 postbuild_witnesses_required generated_resource".split())
POSTBUILD = ["sqlite_c_compile_command_sha256", "sqlite_static_archive_sha256", "sqlite_object_roster_sha256", "storage_link_command_sha256"]
ALLOCATION_SHA = "a3269f6ff8a4eddcdf4db45d0736e951d885e1c1fc11e7ecd2a0f2e22cd49ab1"
IDENTITY_TOOL_SHA = "e1715ba5683c4d5e95f98e84b6e87a5c3896be66c14ad3ab2b6df1109eca1a61"
OPTION_ENVIRONMENT = ["CL", "_CL_", "LINK", "_LINK_"]
TOOLCHAIN_ENVIRONMENT = ["PATH", "INCLUDE", "LIB", "LIBPATH", "VCINSTALLDIR", "VCTOOLSINSTALLDIR",
                         "WINDOWSSDKDIR", "UNIVERSALCRTSDKDIR", "WINDOWSSDKVERSION", "UCRTVERSION", "SYSTEMROOT"]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def exact_keys(value, keys):
    require(type(value) is dict and set(value) == set(keys), "closed object keys")


def text(value):
    require(type(value) is str and "\0" not in value, "String without NUL required")
    return value


def ordinary(value, directory=False):
    p = Path(os.path.abspath(text(os.fspath(value))))
    # Inspect ancestors before opening; do not resolve through a reparse point.
    for part in reversed((p, *p.parents)):
        s = part.lstat()
        require(not stat.S_ISLNK(s.st_mode) and not getattr(s, "st_file_attributes", 0) & 0x400,
                "symlink/reparse path rejected")
        if part != p:
            require(stat.S_ISDIR(s.st_mode), "ordinary ancestor required")
    s = p.lstat()
    require(stat.S_ISDIR(s.st_mode) if directory else stat.S_ISREG(s.st_mode), "ordinary path kind")
    return p


def file_pin(value):
    p = ordinary(value)
    raw = p.read_bytes()
    return {"path": str(p), "bytes": len(raw), "sha256": digest(raw)}


def identity_file_pin(value):
    """Canonical POSIX path spelling for source-identity producer pins only."""
    p = ordinary(value)
    raw = p.read_bytes()
    return {"path": p.as_posix(), "bytes": len(raw), "sha256": digest(raw)}


def load_json(path, expected_sha=None):
    raw = ordinary(path).read_bytes()
    require(len(raw) <= MAX_JSON, "JSON cap")
    if expected_sha is not None:
        require(type(expected_sha) is str and HEX.fullmatch(expected_sha) and digest(raw) == expected_sha,
                "pinned JSON mismatch")
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "duplicate JSON key")
            result[key] = value
        return result
    def invalid_number(value):
        raise ValueError("nonfinite JSON token: " + value)
    return json.loads(raw.decode("utf-8"), object_pairs_hook=pairs, parse_constant=invalid_number), raw


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")


def write_new(path, raw):
    p = Path(os.path.abspath(path))
    ordinary(p.parent, True)
    with p.open("xb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    return file_pin(p)


def environment_policy(environment):
    """Reject effective MSVC option overrides; retain selected tool provenance.

    The child receives the captured full environment explicitly. Unrelated
    variables (which may contain credentials) are never logged or hashed.
    This is an MSVC policy, not a general GNU environment qualification.
    """
    rows = {}
    for key, value in environment.items():
        require(type(key) is str and type(value) is str and "\0" not in key + value, "environment string")
        canonical = key.upper()
        if canonical in OPTION_ENVIRONMENT + TOOLCHAIN_ENVIRONMENT:
            require(canonical not in rows, "ambiguous case-alias environment")
            rows[canonical] = value
    for name in OPTION_ENVIRONMENT:
        require(rows.get(name, "") == "", "effective option environment must be absent/empty: " + name)
    def record(names):
        return [{"name": name, "present": name in rows, "value": rows.get(name)} for name in names]
    return {"policy": "reject-effective-msvc-option-overrides/v1", "option_environment": record(OPTION_ENVIRONMENT),
            "toolchain_environment": record(TOOLCHAIN_ENVIRONMENT)}


def validate_environment_record(record):
    exact_keys(record, ["policy", "option_environment", "toolchain_environment"])
    require(record["policy"] == "reject-effective-msvc-option-overrides/v1", "environment admission policy")
    reconstructed = {}
    for field, names in [("option_environment", OPTION_ENVIRONMENT), ("toolchain_environment", TOOLCHAIN_ENVIRONMENT)]:
        require(type(record[field]) is list and [row["name"] for row in record[field]] == names, "closed environment roster")
        for row in record[field]:
            exact_keys(row, ["name", "present", "value"])
            require(type(row["present"]) is bool and (type(row["value"]) is str if row["present"] else row["value"] is None), "typed environment row")
            if row["present"]:
                reconstructed[row["name"]] = row["value"]
    require(environment_policy(reconstructed) == record, "environment policy evidence")


def resolve_plan_digest(plan_path, plan_sha=None, digest_file=None):
    """Integrity binding only; this file is NOT native execution authorization."""
    require((plan_sha is None) != (digest_file is None), "exactly one plan digest route required")
    plan = ordinary(plan_path)
    if digest_file is None:
        require(type(plan_sha) is str and HEX.fullmatch(plan_sha) and digest(plan.read_bytes()) == plan_sha, "explicit plan SHA256")
        return plan_sha, None
    path = ordinary(digest_file)
    require(path != plan and path.stat().st_size <= 4096, "bounded separate plan digest file")
    value, raw = load_json(path)
    require(len(raw) <= 4096, "plan digest raw byte cap")
    exact_keys(value, ["schema", "plan_path", "plan_sha256"])
    require(value["schema"] == "LocalPlayersInvocationPlanDigest/v1" and type(value["plan_path"]) is str and
            value["plan_path"] == str(plan), "digest file declared canonical plan path")
    require(type(value["plan_sha256"]) is str and HEX.fullmatch(value["plan_sha256"]) and
            digest(plan.read_bytes()) == value["plan_sha256"], "digest file exact plan bytes")
    pin = {"path": str(path), "bytes": len(raw), "sha256": digest(raw)}
    require(file_pin(path) == pin, "plan digest file changed during admission")
    return value["plan_sha256"], pin


def normalize_roots(value, source, build):
    """Replace only two explicit root spellings, preserving all other spelling."""
    roots = []
    for root, token in [(str(source), "@source_root"), (str(build), "@build_root")]:
        for spelling in {root, root.replace("\\", "/")}:
            roots.append((spelling, token))
    result = value
    for spelling, token in sorted(roots, key=lambda item: len(item[0]), reverse=True):
        result = re.sub(re.escape(spelling) + r"(?=$|[/\\])", lambda _: token, result)
    return result


def windows_response_tokens(value):
    """Strict MSVC double-quote/backslash tokenization; no shell expansion."""
    require("\0" not in value, "response NUL")
    result, i = [], 0
    while i < len(value):
        while i < len(value) and value[i] in " \t\r\n":
            i += 1
        if i == len(value):
            break
        token, quoted = [], False
        while i < len(value) and (quoted or value[i] not in " \t\r\n"):
            if value[i] == "\\":
                begin = i
                while i < len(value) and value[i] == "\\":
                    i += 1
                count = i - begin
                if i < len(value) and value[i] == '"':
                    token.extend("\\" * (count // 2))
                    if count % 2:
                        token.append('"')
                        i += 1
                    else:
                        quoted = not quoted
                        i += 1
                else:
                    token.extend("\\" * count)
            elif value[i] == '"':
                # Deliberately fail closed on ambiguous adjacent-quote dialects.
                require(i + 1 == len(value) or value[i + 1] != '"', "adjacent response quotes unsupported")
                quoted = not quoted
                i += 1
            else:
                token.append(value[i])
                i += 1
        require(not quoted, "unclosed response quote")
        result.append("".join(token))
    return result


def expanded_argv(argv, cwd):
    """Capture response bytes before launch; original argv stays authoritative."""
    records, active, total = [], set(), 0
    def expand(args, depth):
        nonlocal total
        require(depth <= 4 and len(records) <= 64, "response recursion/roster cap")
        result = []
        for arg in args:
            if not arg.startswith("@"):
                result.append(arg)
                continue
            require(len(arg) > 1, "empty response path")
            path = ordinary(Path(cwd) / arg[1:])
            require(path not in active, "response cycle")
            raw = path.read_bytes()
            total += len(raw)
            require(total <= 1024 * 1024 and len(records) < 64, "response byte/roster cap")
            if raw.startswith(b"\xff\xfe"):
                content, encoding = raw[2:].decode("utf-16-le"), "utf-16-le-bom"
            else:
                require(not raw.startswith(b"\xfe\xff"), "big-endian response unsupported")
                content, encoding = raw.decode("utf-8-sig"), "utf-8-bom" if raw.startswith(b"\xef\xbb\xbf") else "utf-8"
            args2 = windows_response_tokens(content)
            records.append({"path": str(path), "bytes": len(raw), "sha256": digest(raw),
                            "encoding": encoding, "text": content, "arguments": args2})
            active.add(path)
            result.extend(expand(args2, depth + 1))
            active.remove(path)
        return result
    require(type(argv) is list and argv and all(type(a) is str and "\0" not in a for a in argv), "argv array")
    return expand(argv, 0), records


def command_record(kind, argv, cwd, source, build, tools, responses, environment):
    norm = lambda value: normalize_roots(value, source, build)
    # Ordered arrays retained. Source/output hashes never enter command hash.
    validate_environment_record(environment)
    env = {"policy": environment["policy"], "option_environment": environment["option_environment"],
           "toolchain_environment": [{**row, "value": norm(row["value"]) if row["value"] is not None else None}
                                     for row in environment["toolchain_environment"]]}
    return {"schema": "LocalPlayersMeasuredCommand/v2", "kind": kind,
            "cwd": norm(str(cwd)), "argv": [norm(a) for a in argv],
            "environment": env,
            "tools": [{"path": norm(p["path"]), "bytes": p["bytes"], "sha256": p["sha256"]} for p in tools],
            "response_files": [{"path": norm(p["path"]), "encoding": p["encoding"],
                                "text": norm(p["text"]), "arguments": [norm(a) for a in p["arguments"]]}
                               for p in responses]}


def load_launch_plan(path, expected_sha, kind, argv):
    plan, raw = load_json(path, expected_sha)
    exact_keys(plan, "schema kind source_root build_root cwd argv tools inputs outputs".split())
    require(plan["schema"] == "LocalPlayersInvocationPlan/v1" and plan["kind"] == kind and plan["argv"] == argv,
            "unreviewed invocation")
    source, build, cwd = (ordinary(plan[k], True) for k in ["source_root", "build_root", "cwd"])
    require(source != build and cwd == Path(os.getcwd()), "plan roots/cwd mismatch")
    require([plan[k] for k in ["source_root", "build_root", "cwd"]] == [str(source), str(build), str(cwd)], "canonical absolute plan roots required")
    require(Path(argv[0]).is_absolute(), "tool argv0 must be absolute")
    if kind == "link":
        require(Path(argv[0]).name.lower() in ["link.exe", "lld-link.exe"], "direct linker required; wrapper is not inner argv proof")
    for key in ["tools", "inputs"]:
        require(type(plan[key]) is list and plan[key], "nonempty planned pin roster")
        for item in plan[key]:
            exact_keys(item, ["path", "bytes", "sha256"])
            require(file_pin(item["path"]) == item, "planned file pin drift")
    require(plan["tools"][0]["path"] == str(ordinary(argv[0])), "first tool pin is argv0")
    require(len({p["path"] for p in plan["tools"]}) == len(plan["tools"]), "duplicate tool")
    require(type(plan["outputs"]) is list and plan["outputs"] and len(set(plan["outputs"])) == len(plan["outputs"]), "output roster")
    for name in plan["outputs"]:
        output = Path(os.path.abspath(name))
        ordinary(output.parent, True)
        require(output.is_relative_to(build) and not output.exists() and not output.is_symlink(), "fresh contained output required")
    return plan, raw, source, build, cwd


def launch(kind, plan_path, plan_sha, receipt_root, argv, digest_file=None):
    plan_sha, digest_pin = resolve_plan_digest(plan_path, plan_sha, digest_file)
    plan, raw, source, build, cwd = load_launch_plan(plan_path, plan_sha, kind, argv)
    expanded, responses = expanded_argv(argv, cwd)
    child_environment = dict(os.environ)
    environment = environment_policy(child_environment)
    parent = ordinary(receipt_root, True)
    run = parent / ("invocation-" + uuid.uuid4().hex)
    run.mkdir()
    record = command_record(kind, argv, cwd, source, build, plan["tools"], responses, environment)
    before = {"schema": "LocalPlayersInvocationBefore/v2", "kind": kind, "plan": file_pin(plan_path), "plan_sha256": digest(raw),
              "plan_digest_file": digest_pin, "environment": environment,
              "source_root": str(source), "build_root": str(build), "cwd": str(cwd), "argv": argv,
              "expanded_argv": expanded, "tools": plan["tools"], "inputs": plan["inputs"],
              "response_files": responses, "expected_outputs": plan["outputs"], "command_record": record,
              "command_sha256": digest(json_bytes(record)), "launcher": file_pin(__file__),
              "start_time_ns": time.time_ns()}
    before_pin = write_new(run / "before.json", json_bytes(before))
    started = time.monotonic_ns()
    child, code, error = None, None, None
    try:
        with (run / "stdout.log").open("xb") as stdout, (run / "stderr.log").open("xb") as stderr:
            require(file_pin(plan_path) == before["plan"], "plan changed before child launch")
            if digest_pin is not None:
                require(resolve_plan_digest(plan_path, digest_file=digest_file) == (plan_sha, digest_pin), "digest file changed before child launch")
            child = subprocess.Popen(argv, cwd=str(cwd), shell=False, stdin=subprocess.DEVNULL,
                                     stdout=stdout, stderr=stderr, env=child_environment)
            code = child.wait()
    except BaseException as exception:
        error = type(exception).__name__ + ": " + str(exception)
        if child is not None:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
            code = child.returncode
    stable, outputs = True, []
    try:
        require(file_pin(plan_path) == before["plan"], "plan changed during invocation")
        if digest_pin is not None:
            require(resolve_plan_digest(plan_path, digest_file=digest_file) == (plan_sha, digest_pin), "digest file changed during invocation")
        for item in [*plan["tools"], *plan["inputs"]]:
            require(file_pin(item["path"]) == item, "input/tool changed during invocation")
        for item in responses:
            require(file_pin(item["path"]) == {k: item[k] for k in ["path", "bytes", "sha256"]}, "response changed during invocation")
        for name in plan["outputs"]:
            outputs.append(file_pin(name))
    except (OSError, ValueError) as exception:
        stable = False
        error = (error + "; " if error else "") + str(exception)
    terminal = {"schema": "LocalPlayersInvocationTerminal/v2", "before": before_pin, "pid": child.pid if child else None,
                "plan_digest_file": digest_pin, "environment": environment,
                "exit_observed": code is not None, "exit_code": code, "elapsed_ns": time.monotonic_ns() - started,
                "inputs_unchanged": stable, "outputs": outputs, "error": error,
                "stdout": file_pin(run / "stdout.log"), "stderr": file_pin(run / "stderr.log"),
                "qualified_command": code == 0 and stable and error is None}
    write_new(run / "terminal.json", json_bytes(terminal))
    print(json.dumps({"invocation": str(run), "exit_code": code, "qualified_command": terminal["qualified_command"]}))
    return 0 if terminal["qualified_command"] else 1


def read_invocation(run):
    root = ordinary(run, True)
    before, before_raw = load_json(root / "before.json")
    terminal, _ = load_json(root / "terminal.json")
    exact_keys(before, "schema kind plan plan_sha256 plan_digest_file environment source_root build_root cwd argv expanded_argv tools inputs response_files expected_outputs command_record command_sha256 launcher start_time_ns".split())
    exact_keys(terminal, "schema before pid plan_digest_file environment exit_observed exit_code elapsed_ns inputs_unchanged outputs error stdout stderr qualified_command".split())
    require(terminal["schema"] == "LocalPlayersInvocationTerminal/v2" and before["schema"] == "LocalPlayersInvocationBefore/v2", "invocation schemas")
    validate_environment_record(before["environment"])
    require(terminal["environment"] == before["environment"], "captured child environment evidence")
    require(terminal["plan_digest_file"] == before["plan_digest_file"], "terminal plan digest binding")
    require(terminal["before"] == file_pin(root / "before.json") and terminal["exit_observed"] is True and
            type(terminal["exit_code"]) is int and terminal["exit_code"] == 0 and terminal["inputs_unchanged"] is True and
            terminal["qualified_command"] is True and terminal["error"] is None, "unqualified invocation")
    require(type(terminal["pid"]) is int and terminal["pid"] > 0 and type(terminal["elapsed_ns"]) is int and terminal["elapsed_ns"] >= 0,
            "observed process/time required")
    require(terminal["stdout"]["path"] == str(root / "stdout.log") and terminal["stderr"]["path"] == str(root / "stderr.log"), "owned invocation logs")
    require(file_pin(before["plan"]["path"]) == before["plan"] and before["plan_sha256"] == before["plan"]["sha256"], "frozen invocation plan drift")
    if before["plan_digest_file"] is not None:
        pin = before["plan_digest_file"]
        exact_keys(pin, ["path", "bytes", "sha256"])
        require(resolve_plan_digest(before["plan"]["path"], digest_file=pin["path"]) == (before["plan_sha256"], pin), "current plan digest integrity artifact")
    plan, _ = load_json(before["plan"]["path"], before["plan_sha256"])
    exact_keys(plan, "schema kind source_root build_root cwd argv tools inputs outputs".split())
    require(plan["schema"] == "LocalPlayersInvocationPlan/v1" and
            all(plan[k] == before[k] for k in ["kind", "source_root", "build_root", "cwd", "argv", "tools", "inputs"]) and
            plan["outputs"] == before["expected_outputs"], "receipt differs from prelaunch plan")
    require([p["path"] for p in terminal["outputs"]] == before["expected_outputs"] and
            len(set(before["expected_outputs"])) == len(before["expected_outputs"]), "closed output roster")
    for item in [terminal["stdout"], terminal["stderr"], *terminal["outputs"], *before["inputs"], *before["tools"]]:
        require(file_pin(item["path"]) == item, "current invocation artifact drift")
    source, build = ordinary(before["source_root"], True), ordinary(before["build_root"], True)
    require(before["kind"] in ["compile", "link"] and source != build and
            [before[k] for k in ["source_root", "build_root", "cwd"]] == [str(source), str(build), str(ordinary(before["cwd"], True))], "canonical invocation roots/kind")
    require(file_pin(before["launcher"]["path"]) == before["launcher"] and before["launcher"] == file_pin(__file__), "actual reviewed launcher bytes")
    require(before["tools"] and before["tools"][0]["path"] == str(ordinary(before["argv"][0])), "compiler/tool argument identity")
    require(before["kind"] != "link" or Path(before["argv"][0]).name.lower() in ["link.exe", "lld-link.exe"], "measured direct linker required")
    require(all(ordinary(p["path"]).is_relative_to(build) for p in terminal["outputs"]), "contained observed outputs")
    expanded, responses = expanded_argv(before["argv"], ordinary(before["cwd"], True))
    require(expanded == before["expanded_argv"] and responses == before["response_files"], "response replay mismatch")
    record = command_record(before["kind"], before["argv"], before["cwd"], source, build, before["tools"], responses, before["environment"])
    require(record == before["command_record"] and digest(json_bytes(record)) == before["command_sha256"], "command record mismatch")
    return before, terminal


def compiler_fields(args):
    defines, includes, outputs, forces = [], [], [], []
    i = 1
    while i < len(args):
        original = args[i]
        # MSVC documents '-' and '/' option prefixes as equivalent. Preserve
        # original argv everywhere; this conversion is admission-only. GNU
        # paired -o/-include remain supported for the separately scoped core.
        arg = "/" + original[1:] if original.startswith("-") and original not in ["-o", "-include"] else original
        separated = {"/D": defines, "-D": defines, "/I": includes, "-I": includes,
                     "/Fo": outputs, "-o": outputs, "/FI": forces, "-include": forces}
        if arg in separated:
            require(i + 1 < len(args), "missing compiler option argument")
            separated[arg].append(args[i + 1]); i += 2; continue
        for prefix, destination in [("/Fo", outputs), ("/FI", forces), ("/D", defines), ("-D", defines), ("/I", includes), ("-I", includes)]:
            if arg.startswith(prefix):
                destination.append(arg[len(prefix):]); break
        i += 1
    return defines, includes, outputs, forces


def actual_source(args, cwd, source):
    # Canonicalize independently captured path operands, never command text.
    values = [a[3:] if a.startswith(("/Tc", "/Tp", "-Tc", "-Tp")) else a for a in args[1:]]
    return sum(Path(os.path.abspath(Path(cwd) / a)) == source for a in values) == 1


def reject_cxx_forcing(args):
    for original in args[1:]:
        arg = "/" + original[1:] if original.startswith("-") else original
        require(arg != "/TP" and not arg.startswith("/Tp"), "SQLite C must not be forced to CXX")


def match_compile_database(database, run, source_file, object_file):
    before, terminal = read_invocation(run)
    require(before["kind"] == "compile", "compile invocation required")
    source, obj = ordinary(source_file), ordinary(object_file)
    require(file_pin(source) in before["inputs"] and file_pin(obj) in terminal["outputs"], "source/object binding")
    rows, raw = load_json(database)
    require(type(rows) is list, "compile database array")
    matches = []
    for row in rows:
        require(type(row) is dict and type(row.get("directory")) is str and type(row.get("file")) is str, "compile row shape")
        directory = ordinary(row["directory"], True)
        path = ordinary(directory / row["file"])
        if path == source:
            matches.append((row, directory))
    require(len(matches) == 1, "exactly one SQLite source row required")
    row, directory = matches[0]
    require(directory == ordinary(before["cwd"], True) and type(row.get("output")) is str and ordinary(directory / row["output"]) == obj,
            "compile row directory/output mismatch")
    if "arguments" in row:
        require(type(row["arguments"]) is list and row["arguments"] == before["argv"], "compile arguments mismatch")
    else:
        require(type(row.get("command")) is str and row["command"], "original CMake command string required")
    # The shell string is bound as original evidence, never parsed or a source
    # of expected argv. Independent frozen plan+actual launcher supply argv.
    args = before["expanded_argv"]
    require(actual_source(args, before["cwd"], source),
            "actual source argument absent")
    reject_cxx_forcing(args)
    require(source.suffix == ".c", "SQLite C source required")
    defines, includes, outputs, _ = compiler_fields(args)
    require(len(outputs) == 1 and ordinary(Path(before["cwd"]) / outputs[0]) == obj, "actual compiler output operand")
    sqlite_defines = [a for a in defines if a.startswith("SQLITE_")]
    require(sorted(sqlite_defines) == sorted(["SQLITE_THREADSAFE=1", "SQLITE_OMIT_LOAD_EXTENSION=1"]), "SQLite definitions mismatch")
    return {"compile_database": file_pin(database), "selected_row_index": rows.index(row),
            "invocation_before": file_pin(Path(run) / "before.json"), "invocation_terminal": file_pin(Path(run) / "terminal.json"),
            "source": file_pin(source), "object": file_pin(obj), "compiler": before["tools"][0],
            "actual_definitions": defines, "actual_includes": includes,
            "actual_arguments": args, "command_sha256": before["command_sha256"]}


def coff_object(raw):
    require(len(raw) >= 20, "short COFF object")
    machine, sections, _, symbols, count, optional, _ = struct.unpack_from("<HHIIIHH", raw)
    require(machine == 0x8664 and sections > 0 and optional == 0 and 20 + sections * 40 <= len(raw), "ordinary x64 COFF required (not import/bigobj)")
    if symbols:
        end = symbols + count * 18
        require(end + 4 <= len(raw), "COFF symbols outside member")
        size = struct.unpack_from("<I", raw, end)[0]
        require(size >= 4 and end + size <= len(raw), "COFF string table outside member")
    else:
        require(count == 0, "COFF symbol count without table")
    for i in range(sections):
        off = 20 + i * 40
        size, ptr, reloc, lines, nreloc, nlines = struct.unpack_from("<IIIIHH", raw, off + 16)
        characteristics = struct.unpack_from("<I", raw, off + 36)[0]
        require(not size or (ptr == 0 and characteristics & 0x80) or
                ptr >= 20 + sections * 40 and ptr + size <= len(raw), "COFF section outside member")
        require(not nreloc or reloc and reloc + nreloc * 10 <= len(raw), "COFF relocations outside member")
        require(not nlines or lines and lines + nlines * 6 <= len(raw), "COFF lines outside member")


def _cstrings(raw, count):
    result, pos = [], 0
    for _ in range(count):
        end = raw.find(b"\0", pos)
        require(end > pos, "missing/empty archive symbol")
        result.append(raw[pos:end]); pos = end + 1
    require(pos == len(raw), "extra archive symbol bytes")
    return result


def read_msvc_archive(raw):
    require(type(raw) in [bytes, bytearray], "archive byte buffer")
    raw = bytes(raw)
    require(len(raw) <= MAX_ARCHIVE and raw.startswith(b"!<arch>\n"), "MSVC archive magic/cap")
    members, pos = [], 8
    while pos < len(raw):
        require(len(members) < 65536 and pos + 60 <= len(raw), "archive member cap/header")
        h = raw[pos:pos + 60]
        require(h[58:60] == b"`\n", "archive header terminator")
        name = h[:16].decode("ascii").rstrip(" ")
        require(re.fullmatch(rb"[0-9]+ *", h[48:58]) is not None, "archive member size")
        size = int(h[48:58]); end = pos + 60 + size
        require(end <= len(raw), "archive member outside file")
        for field in [h[16:28], h[28:34], h[34:40], h[40:48]]:
            require(re.fullmatch(rb"[0-9 ]*", field) is not None, "archive metadata syntax")
        members.append({"offset": pos, "raw_name": name, "data": raw[pos + 60:end]})
        if size % 2:
            require(end < len(raw) and raw[end:end + 1] == b"\n", "archive alignment padding")
            end += 1
        pos = end
    require(pos == len(raw) and len(members) >= 3 and [m["raw_name"] for m in members[:2]] == ["/", "/"], "two MSVC linker members required")
    require(sum(m["raw_name"] == "/" for m in members) == 2 and sum(m["raw_name"] == "//" for m in members) <= 1, "archive special member multiplicity")
    long_names = {}
    if members[2]["raw_name"] == "//":
        data, pos = members[2]["data"], 0
        while pos < len(data):
            end = data.find(b"\0", pos); require(end > pos, "long-name termination")
            long_names[pos] = data[pos:end].decode("utf-8"); pos = end + 1
    objects = []
    for m in members[2:]:
        name = m["raw_name"]
        if name == "//":
            require(m is members[2], "long-name member order"); continue
        if name.startswith("/"):
            require(re.fullmatch(r"/[0-9]+", name) is not None and int(name[1:]) in long_names, "long-name offset boundary")
            name = long_names[int(name[1:])]
        else:
            require(name.endswith("/") and len(name) > 1, "short member name")
            name = name[:-1]
        require(name and not any(ord(c) < 32 for c in name) and name not in [x["name"] for x in objects], "object name/duplicate")
        coff_object(m["data"])
        objects.append({"offset": m["offset"], "name": name, "bytes": len(m["data"]), "sha256": digest(m["data"]), "data": m["data"]})
    offsets = {m["offset"] for m in objects}
    first = members[0]["data"]; require(len(first) >= 4, "first linker size")
    count = struct.unpack_from(">I", first)[0]; require(count <= 1000000 and 4 + count * 4 <= len(first), "first linker count")
    refs = struct.unpack_from(">" + "I" * count, first, 4) if count else []
    require(all(x in offsets for x in refs), "first linker object offset")
    first_symbols = list(zip(_cstrings(first[4 + count * 4:], count), refs))
    second = members[1]["data"]; require(len(second) >= 8, "second linker size")
    count = struct.unpack_from("<I", second)[0]; require(count == len(objects) and 8 + count * 4 <= len(second), "second linker member count")
    refs = list(struct.unpack_from("<" + "I" * count, second, 4)) if count else []
    require(len(set(refs)) == len(refs) and set(refs) == offsets and refs == sorted(refs), "second linker object roster")
    pos = 4 + count * 4; symbols = struct.unpack_from("<I", second, pos)[0]; pos += 4
    require(symbols <= 1000000 and pos + symbols * 2 <= len(second), "second linker symbol count")
    indices = struct.unpack_from("<" + "H" * symbols, second, pos) if symbols else []
    require(all(1 <= i <= count for i in indices), "second linker symbol index")
    names = _cstrings(second[pos + symbols * 2:], symbols)
    require(names == sorted(names), "second linker symbols sorted")
    require(Counter(first_symbols) == Counter((name, refs[index - 1]) for name, index in zip(names, indices)), "linker symbol tables disagree")
    return objects


def sqlite_archive_witness(archive, object_file):
    raw = ordinary(archive).read_bytes()
    objects = read_msvc_archive(raw)
    obj = file_pin(object_file)
    matches = [m for m in objects if m["bytes"] == obj["bytes"] and m["sha256"] == obj["sha256"]]
    require(len(matches) == 1, "SQLite object must occur exactly once byte-for-byte")
    member = matches[0]
    require(ntpath.basename(member["name"]) == Path(object_file).name and
            len([m for m in objects if ntpath.basename(m["name"]) == Path(object_file).name]) == 1,
            "ambiguous SQLite member name")
    roster = [{k: m[k] for k in ["offset", "name", "bytes", "sha256"]} for m in objects]
    return {"archive": file_pin(archive), "object": obj, "members": roster,
            "object_roster_sha256": digest(json_bytes(roster)), "sqlite_member": {k: member[k] for k in ["offset", "name", "bytes", "sha256"]}}


def link_inclusion_witness(run, archive, object_file, dll, map_file):
    before, terminal = read_invocation(run)
    require(before["kind"] == "link", "link invocation required")
    archive = ordinary(archive); dll = ordinary(dll); map_file = ordinary(map_file)
    require(file_pin(archive) in before["inputs"] and file_pin(dll) in terminal["outputs"] and file_pin(map_file) in terminal["outputs"], "link artifact pins")
    cwd = ordinary(before["cwd"], True)
    def arg_path(a):
        return Path(os.path.abspath(cwd / a))
    args = before["expanded_argv"][1:]
    require(sum(arg_path(a) == archive for a in args if not a.startswith(("/", "-")) or Path(a).is_absolute()) == 1,
            "archive must be one actual linker input")
    options = ["/" + a[1:] if a.startswith("-") else a for a in args]
    outs = [a[5:] for a in options if a.lower().startswith("/out:")]
    maps = [a[5:] for a in options if a.lower().startswith("/map:")]
    require(len(outs) == len(maps) == 1 and arg_path(outs[0]) == dll and arg_path(maps[0]) == map_file, "exact linker /OUT and /MAP (both documented prefixes)")
    witness = sqlite_archive_witness(archive, object_file)
    content = map_file.read_bytes(); require(len(content) <= MAX_ARCHIVE, "map cap")
    # MSVC map Publics-by-Value rows, observed Lib:Object origin. Do not infer
    # inclusion from archive presence in argv, DLL strings, or symbol names only.
    rows = []
    pattern = re.compile(r"^\s*[0-9A-Fa-f]{4}:[0-9A-Fa-f]{8,16}\s+(sqlite3_[A-Za-z0-9_]+)\s+[0-9A-Fa-f]{8,16}\s+(?:[fi]\s+)*([^\s]+)\s*$")
    for line in content.decode("utf-8-sig").splitlines():
        m = pattern.fullmatch(line)
        if m:
            rows.append({"symbol": m[1], "origin": m[2]})
    origin = archive.stem + ":" + ntpath.basename(witness["sqlite_member"]["name"])
    require(rows and all(row["origin"] == origin for row in rows), "SQLite map origin mismatch/ambiguous")
    for symbol in ["sqlite3_open_v2", "sqlite3_close_v2", "sqlite3_sourceid"]:
        require(sum(row["symbol"] == symbol for row in rows) == 1, "required SQLite inclusion symbol")
    return {"link_invocation_before": file_pin(Path(run) / "before.json"), "link_invocation_terminal": file_pin(Path(run) / "terminal.json"),
            "link_command_sha256": before["command_sha256"], "dll": file_pin(dll), "map": file_pin(map_file),
            "sqlite_archive": witness, "map_sqlite_rows": rows,
            "scope": "Measured direct-link/archive/map inclusion only; no SQLite runtime/VFS/durability qualification"}


def qualify_identity_inputs(value):
    """Independent raw-input/recipe reconstruction, not a second configure."""
    source, build, deps = (ordinary(value[k], True) for k in ["source_root", "build_root", "dependency_root"])
    allocation_path = source / "docs/contracts/local-players/compiled-source-allocation-v1.json"
    allocation, _ = load_json(allocation_path, ALLOCATION_SHA)
    require(value["allocation_sha256"] == ALLOCATION_SHA, "allocation authority")
    tool = file_pin(source / "tools/local-players/source-identity.py")
    require(tool["sha256"] == IDENTITY_TOOL_SHA, "reviewed source-identity producer required")
    sources = [row["path"] for row in allocation["ordered_storage_component_sources"]]
    controls, contracts = allocation["ordered_storage_build_controls"], allocation["ordered_contract_inputs"]
    require([len(sources), len(controls), len(contracts)] == [17, 15, 11], "accepted allocation counts")
    roster = sources + controls + contracts
    require(type(value["source_bindings"]) is list and [r["path"] for r in value["source_bindings"]] == roster, "ordered 17/15/11 source binding roster")
    rows = []
    for index, row in enumerate(value["source_bindings"]):
        exact_keys(row, ["path", "bytes", "raw_sha256", "identity_sha256", "normalization"])
        name = text(row["path"])
        p = ordinary(source / name)
        require(p.is_relative_to(source), "contained source input")
        raw = p.read_bytes(); content = raw.decode("utf-8")
        require(not content.startswith("\ufeff") and "\0" not in content and content.strip() and "\r" not in content.replace("\r\n", ""), "source text transport")
        normal = content.replace("\r\n", "\n").encode("utf-8")
        exact = index >= 32
        require(not exact or raw == normal and raw.endswith(b"\n"), "normative input exact LF")
        require(row == {"path": name, "bytes": len(raw), "raw_sha256": digest(raw), "identity_sha256": digest(normal),
                        "normalization": "exact-UTF8-LF" if exact else "CRLF-to-LF-only"}, "raw source/identity binding drift")
        rows.append((name, digest(normal)))
    exact_keys(value["compiled_build_scalars"], allocation["storage_identity"]["compiled_build_scalar_keys"])
    scalars = value["compiled_build_scalars"]
    scalar_keys = allocation["storage_identity"]["compiled_build_scalar_keys"]
    require(all(type(v) is str for v in scalars.values()), "typed compiled scalars")
    plan_pin = value["build_plan"]
    require(identity_file_pin(plan_pin["path"]) == plan_pin, "actual precompile plan")
    plan, _ = load_json(plan_pin["path"])
    require(plan["schema"] == "LocalPlayersPrecompilePlan/v1" and plan["compiled_build_scalars"] == scalars, "frozen precompile scalar plan")
    for row in value["configure_provenance"].values():
        require(identity_file_pin(row["path"]) == row, "actual configure/compiler provenance")
    for lang in ["c", "cxx"]:
        compiler = plan["compiler_files"][lang]
        require(file_pin(compiler["path"])["sha256"] == compiler["sha256"] == scalars[lang + "_compiler_executable_sha256"], "independent actual compiler bytes")
    lock, _ = load_json(source / "third_party/dependencies.lock.json")
    items = {i["id"]: i for i in lock["sources"]}
    exact_keys(value["dependencies"], ["sqlite", "godot-cpp"])
    for name, dependency in value["dependencies"].items():
        require(identity_file_pin(dependency["archive"]["path"]) == dependency["archive"] and dependency["archive"]["sha256"] == items[name]["sha256"], "locked actual dependency archive")
        receipt, _ = load_json(deps / name / ".verified.json")
        require(receipt == dependency["receipt"] and all(receipt[k] == items[name][k] for k in ["id", "version", "url", "sha256"]), "dependency bootstrap receipt")
        listed = dependency["files"]
        require(type(listed) is list and listed and len({r["path"] for r in listed}) == len(listed), "dependency file roster")
        expected = set()
        for row in listed:
            exact_keys(row, ["path", "sha256"])
            path = ordinary(deps / name / row["path"])
            require(path.is_relative_to(deps / name) and file_pin(path)["sha256"] == row["sha256"], "dependency raw member")
            expected.add(path)
        actual = set()
        for current, dirs, files in os.walk(ordinary(deps / name, True), followlinks=False):
            for child in dirs:
                ordinary(Path(current) / child, True)
            for child in files:
                p = ordinary(Path(current) / child)
                if p != deps / name / ".verified.json":
                    actual.add(p)
        require(actual == expected, "closed actual dependency file roster")
    include_raw = (json.dumps(value["sqlite_include_provenance"], ensure_ascii=True, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")
    require(include_raw.decode("utf-8") == value["sqlite_include_provenance_utf8"] and digest(include_raw) == scalars["sqlite_include_directories_sha256"], "include provenance raw recipe")
    body = lambda pairs: "".join(k + ":" + v + "\n" for k, v in pairs)
    # Producer canonical JSON sorts object keys; recipe order comes only from
    # accepted allocation, never incidental JSON parser insertion order.
    build_body = body(rows[17:32] + [(key, scalars[key]) for key in scalar_keys])
    contract_body = body(rows[32:])
    component_body = ("flight-local-players-component-v1\n" +
        "storage-build-controls:" + digest(build_body.encode("utf-8")) + "\n" +
        "storage-contracts:" + digest(contract_body.encode("utf-8")) + "\n" +
        "sqlite-source:" + items["sqlite"]["source_id"] + "\n" +
        "sqlite-amalgamation:" + file_pin(deps / "sqlite/sqlite3.c")["sha256"] + "\n" +
        "sqlite-header:" + file_pin(deps / "sqlite/sqlite3.h")["sha256"] + "\n" +
        "godot-cpp:" + items["godot-cpp"]["commit"] + "\n" + body(rows[:17]))
    require([value[k] for k in ["build_digest_body_utf8", "contracts_digest_body_utf8", "component_digest_body_utf8"]] ==
            [build_body, contract_body, component_body], "independently reconstructed three recipe bodies")
    return {"producer": tool, "allocation": file_pin(allocation_path), "plan": plan_pin,
            "scope": "raw source/recipe/header input binding; source producer configure/archive semantics require independent Root admission"}


def identity_header(manifest_path, manifest_sha):
    value, raw = load_json(manifest_path, manifest_sha)
    exact_keys(value, IDENTITY_KEYS)
    require(value["schema"] == "LocalPlayersPrecompileSourceIdentity/v1" and value["postbuild_witnesses_required"] == POSTBUILD, "identity manifest schema/witness partition")
    qualify_identity_inputs(value)
    for field, body in [("component_fingerprint", "component_digest_body_utf8"), ("build_control_sha256", "build_digest_body_utf8"), ("contract_sha256", "contracts_digest_body_utf8")]:
        require(type(value[field]) is str and HEX.fullmatch(value[field]) and type(value[body]) is str and
                value[body].endswith("\n") and "\r" not in value[body] and digest(value[body].encode("utf-8")) == value[field], "identity recipe body/hash")
    resource = ("extends RefCounted\nconst SCHEMA: String = \"flight-local-players-component-v1\"\n"
                f'const COMPONENT_FINGERPRINT: String = "{value["component_fingerprint"]}"\n'
                f'const BUILD_CONTROL_SHA256: String = "{value["build_control_sha256"]}"\n'
                f'const CONTRACT_SHA256: String = "{value["contract_sha256"]}"\n').encode("utf-8")
    exact_keys(value["generated_resource"], ["path", "bytes", "sha256"])
    require(value["generated_resource"] == {"path": "local-players-identity.gd", "bytes": len(resource), "sha256": digest(resource)} and
            ordinary(Path(manifest_path).parent / "local-players-identity.gd").read_bytes() == resource, "identity resource exact bytes")
    header = (f'#define FLIGHT_LOCAL_PLAYERS_COMPONENT_SHA256 "{value["component_fingerprint"]}"\n'
              f'#define FLIGHT_LOCAL_PLAYERS_BUILD_CONTROL_SHA256 "{value["build_control_sha256"]}"\n'
              f'#define FLIGHT_LOCAL_PLAYERS_CONTRACT_SHA256 "{value["contract_sha256"]}"\n').encode("ascii")
    return header, value


def verify_header_compile(run, manifest_path, manifest_sha, header):
    raw, identity = identity_header(manifest_path, manifest_sha)
    require(ordinary(header) == ordinary(Path(identity["build_root"]) / "local-players-generated/compiled_identity.hpp") and ordinary(header).read_bytes() == raw, "forced header location/bytes")
    before, _ = read_invocation(run)
    expected_source = ordinary(Path(identity["source_root"]) / "native/persistence/local_players/src/storage_identity.cpp")
    require(before["kind"] == "compile" and file_pin(expected_source) in before["inputs"] and file_pin(header) in before["inputs"], "identity source/header input pins")
    args = before["expanded_argv"][1:]
    require(actual_source(before["expanded_argv"], before["cwd"], expected_source), "identity source actual argument")
    defines, _, _, flags = compiler_fields(before["expanded_argv"])
    require(len(flags) == 1 and ordinary(Path(before["cwd"]) / flags[0]) == ordinary(header), "exact one forced identity header")
    require(not any(a.startswith("FLIGHT_LOCAL_PLAYERS_") for a in defines), "identity macro override")
    return {"manifest": file_pin(manifest_path), "header": file_pin(header), "source": file_pin(expected_source),
            "command_sha256": before["command_sha256"], "scope": "header input/value binding, not runtime identity observation"}


def native_path_overlap(a, b):
    a, b = ntpath.normcase(a), ntpath.normcase(b)
    return ntpath.commonpath([a, b]) in [a, b] if ntpath.splitdrive(a)[0] == ntpath.splitdrive(b)[0] else False


def native_proof_parent_allowed(source, parent):
    """Match the native factory's source-relative namespace before creation."""
    original_parent = parent
    source, parent = ntpath.normcase(source), ntpath.normcase(parent)
    if native_path_overlap(source, parent):
        if parent == source or ntpath.commonpath([source, parent]) == parent:
            return False
        relative = original_parent[len(source) + 1:]
        return relative == ".local" or relative.startswith(".local\\")
    return parent != ntpath.splitdrive(parent)[0] + "\\"


def native_preparation_authorization(value, supervisor_sha, python_sha):
    """Pure closed admission; no resolver, directory creation or child process."""
    exact_keys(value, ["schema", "operation", "source_root", "proof_parent",
                       "evidence_parent", "supervisor_sha256", "python_sha256"])
    require(value["schema"] == "LocalPlayersNativePreparationAuthorization/v1"
            and value["operation"] == "prepare-isolated-test-root", "closed native preparation operation")
    require(value["supervisor_sha256"] == supervisor_sha and HEX.fullmatch(supervisor_sha)
            and value["python_sha256"] == python_sha and HEX.fullmatch(python_sha), "pinned native supervisor/interpreter")
    for key in ["source_root", "proof_parent", "evidence_parent"]:
        path = text(value[key])
        require(len(path.encode("utf-8")) <= 4096 and not path.startswith(("\\\\", "//"))
                and ntpath.isabs(path) and len(ntpath.splitdrive(path)[0]) == 2
                and ntpath.normpath(path) == path and "/" not in path,
                "ordinary canonical absolute Windows drive path required")
    return value


def native_test_descriptor(root, parent, nonce, root_identity, parent_identity, sentinel):
    """Shape exact independently observed values; never opens a path."""
    require(re.fullmatch("[0-9a-f]{32}", nonce) is not None, "fresh nonce shape")
    require(ntpath.dirname(root).casefold() == parent.casefold()
            and ntpath.basename(root) == "local-players-test-" + nonce, "unique direct child name")
    for path in [root, parent]:
        require(type(path) is str and len(path.encode("utf-8")) <= 4096, "descriptor path bound")
    for volume, file_id in [root_identity, parent_identity]:
        require(type(volume) is int and 0 <= volume <= (1 << 64) - 1
                and type(file_id) is str and re.fullmatch("[0-9a-f]{32}", file_id), "actual FILE_ID_INFO shape")
    expected = ('{"schema":"LocalPlayersTestRootSentinel/v1","nonce":"' + nonce + '"}\n').encode()
    require(type(sentinel) is bytes and sentinel == expected and len(sentinel) <= 1024, "exact sentinel bytes")
    return {"schema": "LocalPlayersTestRootDescriptor/v1", "root": root, "parent": parent,
            "nonce": nonce, "root_volume_serial": str(root_identity[0]), "root_file_id": root_identity[1],
            "parent_volume_serial": str(parent_identity[0]), "parent_file_id": parent_identity[1],
            "sentinel_sha256": digest(sentinel)}


def prepare_native_test_root(authorization_path, authorization_sha):
    """Root-only actual Win32 preparation, never called by build/header stages.

    No SQLite, service, worker, engine or child is opened. Partial attempts are
    retained. The independent native TestRootFactory must re-admit this output;
    this receipt alone grants no native-test or production-store qualification.
    """
    require(os.name == "nt", "actual Windows native preparation only")
    authorization, authorization_raw = load_json(authorization_path, authorization_sha)
    supervisor_pin, python_pin = file_pin(__file__), file_pin(sys.executable)
    native_preparation_authorization(authorization, supervisor_pin["sha256"], python_pin["sha256"])
    admitted_authorization_pin = file_pin(authorization_path)
    require(admitted_authorization_pin["sha256"] == digest(authorization_raw)
            and admitted_authorization_pin["bytes"] == len(authorization_raw), "admitted authorization changed before native prerequisite")
    source = ordinary(authorization["source_root"], True)
    parent = ordinary(authorization["proof_parent"], True)
    evidence_parent = ordinary(authorization["evidence_parent"], True)
    require(ordinary(source / "tools/local-players/qualify.py") == ordinary(__file__), "Root-declared corresponding supervisor source")
    require(native_proof_parent_allowed(str(source), str(parent)), "proof parent must be outside source or within source .local namespace")
    require(evidence_parent != source and not source.is_relative_to(evidence_parent), "evidence parent cannot be source or source ancestor")
    require(parent != Path(parent.anchor) and evidence_parent != Path(evidence_parent.anchor), "drive-root preparation forbidden")
    import ctypes
    from ctypes import wintypes as w
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    shell = ctypes.WinDLL("shell32", use_last_error=True)
    ole = ctypes.WinDLL("ole32", use_last_error=True)
    class FileId(ctypes.Structure):
        _fields_ = [("volume", ctypes.c_ulonglong), ("id", ctypes.c_ubyte * 16)]
    class Tag(ctypes.Structure):
        _fields_ = [("attributes", w.DWORD), ("tag", w.DWORD)]
    class Guid(ctypes.Structure):
        _fields_ = [("a", w.DWORD), ("b", w.WORD), ("c", w.WORD), ("d", ctypes.c_ubyte * 8)]
    kernel.CreateFileW.argtypes = [w.LPCWSTR, w.DWORD, w.DWORD, w.LPVOID, w.DWORD, w.DWORD, w.HANDLE]
    kernel.CreateFileW.restype = w.HANDLE
    kernel.CloseHandle.argtypes = [w.HANDLE]; kernel.CloseHandle.restype = w.BOOL
    kernel.GetFileInformationByHandleEx.argtypes = [w.HANDLE, ctypes.c_int, w.LPVOID, w.DWORD]
    kernel.GetFileInformationByHandleEx.restype = w.BOOL
    kernel.GetFinalPathNameByHandleW.argtypes = [w.HANDLE, w.LPWSTR, w.DWORD, w.DWORD]
    kernel.GetFinalPathNameByHandleW.restype = w.DWORD
    kernel.GetVolumeInformationByHandleW.argtypes = [w.HANDLE, w.LPWSTR, w.DWORD, ctypes.POINTER(w.DWORD),
        ctypes.POINTER(w.DWORD), ctypes.POINTER(w.DWORD), w.LPWSTR, w.DWORD]
    kernel.GetVolumeInformationByHandleW.restype = w.BOOL
    kernel.GetDriveTypeW.argtypes = [w.LPCWSTR]; kernel.GetDriveTypeW.restype = w.UINT
    kernel.CreateDirectoryW.argtypes = [w.LPCWSTR, w.LPVOID]; kernel.CreateDirectoryW.restype = w.BOOL
    kernel.WriteFile.argtypes = [w.HANDLE, w.LPCVOID, w.DWORD, ctypes.POINTER(w.DWORD), w.LPVOID]
    kernel.WriteFile.restype = w.BOOL
    kernel.ReadFile.argtypes = [w.HANDLE, w.LPVOID, w.DWORD, ctypes.POINTER(w.DWORD), w.LPVOID]
    kernel.ReadFile.restype = w.BOOL
    kernel.FlushFileBuffers.argtypes = [w.HANDLE]; kernel.FlushFileBuffers.restype = w.BOOL
    kernel.SetFilePointerEx.argtypes = [w.HANDLE, ctypes.c_longlong, ctypes.POINTER(ctypes.c_longlong), w.DWORD]
    kernel.SetFilePointerEx.restype = w.BOOL
    shell.SHGetKnownFolderPath.argtypes = [ctypes.POINTER(Guid), w.DWORD, w.HANDLE, ctypes.POINTER(w.LPWSTR)]
    shell.SHGetKnownFolderPath.restype = ctypes.c_long
    ole.CoTaskMemFree.argtypes = [w.LPVOID]; ole.CoTaskMemFree.restype = None
    handles = []
    invalid = ctypes.c_void_p(-1).value
    def checked(ok, operation):
        if not ok:
            raise ctypes.WinError(ctypes.get_last_error(), operation)
    def open_handle(path, directory, access=0, creation=3, share=3):
        handle = kernel.CreateFileW(str(path), access, share, None, creation,
            0x00200000 | (0x02000000 if directory else 0), None)
        require(handle not in [None, invalid], "actual CreateFileW failed: " + str(ctypes.get_last_error()))
        handles.append(handle)
        return handle
    def observe(handle, expected_path, directory):
        tag, identity = Tag(), FileId()
        checked(kernel.GetFileInformationByHandleEx(handle, 9, ctypes.byref(tag), ctypes.sizeof(tag)), "FileAttributeTagInfo")
        require(not tag.attributes & 0x400 and bool(tag.attributes & 0x10) == directory, "ordinary native handle kind")
        checked(kernel.GetFileInformationByHandleEx(handle, 18, ctypes.byref(identity), ctypes.sizeof(identity)), "FileIdInfo")
        final = ctypes.create_unicode_buffer(32768)
        length = kernel.GetFinalPathNameByHandleW(handle, final, len(final), 0)
        require(0 < length < len(final) and final.value.startswith("\\\\?\\")
                and not final.value.startswith("\\\\?\\UNC\\"), "physical local final name")
        physical = final.value[4:]
        require(physical.casefold() == str(expected_path).casefold(), "native final path differs from admitted path")
        fs = ctypes.create_unicode_buffer(32)
        checked(kernel.GetVolumeInformationByHandleW(handle, None, 0, None, None, None, fs, len(fs)), "native volume filesystem")
        require(fs.value == "NTFS" and kernel.GetDriveTypeW(ntpath.splitdrive(physical)[0] + "\\") == 3,
                "fixed local NTFS required")
        return (int(identity.volume), bytes(identity.id).hex()), physical
    # FOLDERID_LocalAppData. Flags0 performs no directory creation.
    folder = Guid(0xF1B32785, 0x6FBA, 0x4FCF, (ctypes.c_ubyte * 8)(0x9D,0x55,0x7B,0x8E,0x7F,0x15,0x70,0x91))
    result = w.LPWSTR()
    hr = shell.SHGetKnownFolderPath(ctypes.byref(folder), 0, None, ctypes.byref(result))
    try:
        require(hr >= 0 and bool(result), "actual readonly LocalAppData resolver failed")
        local_app_data = result.value
    finally:
        if result:
            ole.CoTaskMemFree(ctypes.cast(result, w.LPVOID))
    nonce = os.urandom(16).hex()
    run = evidence_parent / ("root-preparation-" + nonce)
    child = parent / ("local-players-test-" + nonce)
    require(not run.exists() and not child.exists(), "fresh native preparation only")
    evidence_created = False
    retained = {"schema": "LocalPlayersNativePreparationReceipt/v1", "nonce": nonce,
        "authorization": admitted_authorization_pin, "supervisor": supervisor_pin, "python": python_pin,
        "root": str(child), "parent": str(parent), "pid": os.getpid(), "qualified_preparation": False,
        "product_store_opened": False, "sqlite_or_worker_or_child_created": False}
    try:
        source_identity, _ = observe(open_handle(source, True), source, True)
        parent_handle = open_handle(parent, True)
        parent_identity, _ = observe(parent_handle, parent, True)
        appdata = ordinary(local_app_data, True)
        _, physical_appdata = observe(open_handle(appdata, True), appdata, True)
        product = ntpath.join(physical_appdata, "FlightSimulator", "Players")
        require(all(not native_path_overlap(str(path), product) for path in [parent, evidence_parent, child, run]),
                "proof/evidence parents and children exclude actual product namespace")
        evidence_handle = open_handle(evidence_parent, True)
        evidence_identity, _ = observe(evidence_handle, evidence_parent, True)
        require(file_pin(authorization_path) == admitted_authorization_pin
                and file_pin(__file__) == supervisor_pin and file_pin(sys.executable) == python_pin,
                "admitted authorization/tools changed before any creation")
        require(child != source and not source.is_relative_to(child)
                and child != run and not child.is_relative_to(run) and not run.is_relative_to(child), "isolated source/evidence containment")
        # Resolve actual product/source/parent exclusions BEFORE any creation,
        # including evidence creation. Rejected authorization has no write side effect.
        run.mkdir()
        evidence_created = True
        checked(kernel.CreateDirectoryW(str(child), None), "fresh isolated CreateDirectoryW")
        root_handle = open_handle(child, True)
        root_identity, _ = observe(root_handle, child, True)
        require(root_identity != parent_identity and root_identity != source_identity
                and root_identity[0] == parent_identity[0], "distinct same-volume actual child")
        sentinel = ('{"schema":"LocalPlayersTestRootSentinel/v1","nonce":"' + nonce + '"}\n').encode()
        sentinel_path = child / ".local-players-test-root.json"
        sentinel_handle = open_handle(sentinel_path, False, access=0xC0000000, creation=1, share=1)
        count = w.DWORD()
        checked(kernel.WriteFile(sentinel_handle, sentinel, len(sentinel), ctypes.byref(count), None), "sentinel WriteFile")
        require(count.value == len(sentinel), "complete actual sentinel write")
        checked(kernel.FlushFileBuffers(sentinel_handle), "sentinel FlushFileBuffers")
        sentinel_identity, _ = observe(sentinel_handle, sentinel_path, False)
        checked(kernel.SetFilePointerEx(sentinel_handle, 0, None, 0), "sentinel rewind")
        readback = ctypes.create_string_buffer(1025)
        checked(kernel.ReadFile(sentinel_handle, readback, len(readback), ctypes.byref(count), None), "sentinel ReadFile")
        require(count.value == len(sentinel) and readback.raw[:count.value] == sentinel, "exact actual sentinel reread")
        require(observe(root_handle, child, True)[0] == root_identity
                and observe(parent_handle, parent, True)[0] == parent_identity
                and observe(evidence_handle, evidence_parent, True)[0] == evidence_identity,
                "native root/parent/evidence identities retained through write")
        descriptor = native_test_descriptor(str(child), str(parent), nonce, root_identity, parent_identity, sentinel)
        require(file_pin(authorization_path) == retained["authorization"] and file_pin(__file__) == supervisor_pin
                and file_pin(sys.executable) == python_pin, "authorization/tool drift")
        # Close every preparation lease before publishing the capability descriptor.
        # Actual native factory later opens its own retained leases and rechecks IDs.
        while handles:
            handle = handles[-1]
            checked(kernel.CloseHandle(handle), "preparation CloseHandle")
            handles.pop()
        descriptor_pin = write_new(run / "descriptor.json", json_bytes(descriptor))
        retained.update({"qualified_preparation": True, "descriptor": descriptor_pin,
            "sentinel_identity": {"volume_serial": str(sentinel_identity[0]), "file_id": sentinel_identity[1]},
            "scope": "Native root/sentinel preparation only; native capability admission, tests and cleanup unproven."})
    except (OSError, ValueError) as error:
        retained["error"] = type(error).__name__ + ": " + str(error)
        raise
    finally:
        close_failures = []
        while handles:
            handle = handles.pop()
            if not kernel.CloseHandle(handle):
                close_failures.append(ctypes.get_last_error())
        if close_failures:
            retained["qualified_preparation"] = False
            retained["close_failures"] = close_failures
        retained["retained_for_independent_admission_no_cleanup"] = True
        if evidence_created:
            write_new(run / "preparation.json", json_bytes(retained))
    require(retained["qualified_preparation"], "actual preparation did not safely close")
    return retained


def load_compile_plan_index(path, digest_path, argv):
    """Select an independently frozen plan by exact argv, never mint from argv.

    Root's index is integrity-pinned before the compiler build starts. Expected
    commands must originate in the reviewed Root policy/configuration producer;
    neither a launcher observation nor a compile database shell string supplies
    expected arguments. Every referenced plan is checked before selection.
    """
    expected_sha, digest_pin = resolve_plan_digest(path, digest_file=digest_path)
    index, raw = load_json(path, expected_sha)
    exact_keys(index, ["schema", "source_root", "build_root", "entries"])
    require(index["schema"] == "LocalPlayersCompilePlanIndex/v1", "compile plan index schema")
    source, build = ordinary(index["source_root"], True), ordinary(index["build_root"], True)
    require(source != build and index["source_root"] == str(source)
            and index["build_root"] == str(build), "canonical index roots")
    require(type(index["entries"]) is list and 1 <= len(index["entries"]) <= 64,
            "bounded nonempty compile plan index")
    matches, commands, paths = [], set(), set()
    for pin in index["entries"]:
        exact_keys(pin, ["path", "bytes", "sha256"])
        require(type(pin["bytes"]) is int and 0 < pin["bytes"] <= MAX_JSON
                and type(pin["sha256"]) is str and HEX.fullmatch(pin["sha256"]), "typed compile plan pin")
        candidate = ordinary(pin["path"])
        require(candidate.is_relative_to(build) and str(candidate) == pin["path"]
                and pin["path"] not in paths, "unique contained compile plan")
        paths.add(pin["path"])
        require(file_pin(candidate) == pin, "frozen compile plan pin drift")
        plan, _ = load_json(candidate, pin["sha256"])
        exact_keys(plan, "schema kind source_root build_root cwd argv tools inputs outputs".split())
        require(plan["schema"] == "LocalPlayersInvocationPlan/v1" and plan["kind"] == "compile"
                and plan["source_root"] == str(source) and plan["build_root"] == str(build), "compile plan roots/kind")
        command = plan["argv"]
        require(type(command) is list and command and all(type(a) is str and "\0" not in a for a in command),
                "closed expected compile argv")
        key = (plan["cwd"], tuple(command))
        require(key not in commands, "duplicate expected compile command")
        commands.add(key)
        if command == argv and plan["cwd"] == os.getcwd():
            matches.append(pin)
    require(len(matches) == 1, "actual compiler argv has no unique independently admitted plan")
    require(file_pin(path)["sha256"] == digest(raw)
            and resolve_plan_digest(path, digest_file=digest_path) == (expected_sha, digest_pin),
            "index admission drift")
    return matches[0], file_pin(path), digest_pin


def launch_planned_compile(index_path, digest_path, receipt_root, argv):
    pin, index_pin, digest_pin = load_compile_plan_index(index_path, digest_path, argv)
    # Keep index evidence separate from command/compiled identity to avoid a
    # plan/index hash cycle. The selected original plan is pinned by launch().
    parent = ordinary(receipt_root, True)
    evidence = parent / ("compile-selection-" + uuid.uuid4().hex)
    evidence.mkdir()
    before = {"schema": "LocalPlayersCompilePlanSelection/v1", "index": index_pin,
              "digest_file": digest_pin, "selected_plan": pin, "argv": argv,
              "cwd": os.getcwd(), "launcher": file_pin(__file__)}
    write_new(evidence / "before.json", json_bytes(before))
    code, error = None, None
    try:
        code = launch("compile", pin["path"], pin["sha256"], receipt_root, argv)
        require(file_pin(index_path) == index_pin and file_pin(digest_path) == digest_pin
                and file_pin(pin["path"]) == pin, "compile index changed during invocation")
    except (OSError, ValueError, KeyError, TypeError, UnicodeError) as exception:
        error = type(exception).__name__ + ": " + str(exception)
    write_new(evidence / "terminal.json", json_bytes({
        "schema": "LocalPlayersCompilePlanSelectionTerminal/v1", "before": file_pin(evidence / "before.json"),
        "selected_plan": pin, "exit_code": code, "error": error,
        "qualified_selection": code == 0 and error is None}))
    return 0 if code == 0 and error is None else 1


# Original MIT. Private authoring fragment embedded in sole public qualify.py.
# All Win32/process code is called only by explicit Root-authorized future modes.
NATIVE_LIMITS = {"codec": 120, "store": 600, "service": 900, "windows": 900, "crash": 7200}
NATIVE_NAMES = ["local_players_" + name for name in NATIVE_LIMITS]
TEST_TARGETS = {
    "codec": ("local_players_codec_native", ["codec.cpp"]),
    "store": ("local_players_store_native", ["native.cpp", "test_capability.cpp"]),
    "service": ("local_players_service_native", ["service.cpp", "test_capability.cpp"]),
    "windows": ("local_players_windows_native", ["windows.cpp", "test_capability.cpp"]),
    "crash": ("local_players_crash_native", ["native.cpp", "test_capability.cpp"]),
    "crash_actor": ("local_players_crash_actor", ["crash_actor.cpp", "test_capability.cpp"]),
    "lock_actor": ("local_players_lock_actor", ["faults/lock_actor.cpp", "test_capability.cpp"]),
    "test_bridge": ("flight_local_players_test_bridge", ["@boundary", "test_capability.cpp", "test_bridge.cpp"]),
}
U64_MAX = (1 << 64) - 1
NATIVE_REMAINING = [
    "Retained-directory partial-delete failure gates remain separate; nineteen transactional crash scenarios do not substitute.",
    "Focused test cases are not complete issue219 coverage; deferred faults/maximums remain separate gates.",
    "Full bridge numeric-family parity, shipping absence and three-context/replacement delivery remain separate.",
    "Installed production-root disposable-account journey220 is not executed by these stages.",
]


def actual_int(value, low, high, label):
    require(type(value) is int and low <= value <= high, label)
    return value


def canonical_u64(value, positive=False):
    require(type(value) is str and re.fullmatch(r"0|[1-9][0-9]{0,19}", value) and int(value) <= U64_MAX
            and (not positive or int(value) > 0), "canonical U64 String")
    return int(value)


def native_pin(value, cap=512 * 1024 * 1024):
    """Streaming actual file pin; no path/bytes normalization or generated value."""
    path = ordinary(value)
    observed = path.stat()
    require(observed.st_nlink == 1 and observed.st_size <= cap, "bounded single-link native input")
    h = hashlib.sha256(); count = 0
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(65536), b""):
            h.update(block); count += len(block)
    require(count == observed.st_size and path.stat().st_size == count, "native input size continuity")
    return {"path": str(path), "bytes": count, "sha256": h.hexdigest()}


def observed_module_pin(value, cap=512 * 1024 * 1024):
    """Real OS module bytes, not qualification input authority.

    Windows system modules may be ordinary NTFS hardlinks. Selected test DLL
    and CRT inputs still pass strict native_pin after runtime filtering.
    """
    path = ordinary(value)
    observed = path.stat()
    require(observed.st_nlink >= 1 and observed.st_size <= cap, "bounded ordinary observed module")
    h = hashlib.sha256(); count = 0
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(65536), b""):
            h.update(block); count += len(block)
    final = path.stat()
    require(count == observed.st_size and all(getattr(final, k) == getattr(observed, k)
            for k in ["st_dev", "st_ino", "st_size", "st_nlink"]), "observed module identity/size continuity")
    return {"path": str(path), "bytes": count, "sha256": h.hexdigest()}


def admit_actual_pin(value, cap=512 * 1024 * 1024):
    exact_keys(value, ["path", "bytes", "sha256"])
    actual_int(value["bytes"], 0, cap, "file bytes INT")
    require(type(value["sha256"]) is str and HEX.fullmatch(value["sha256"]), "file SHA")
    require(native_pin(value["path"], cap) == value, "actual native pin mismatch")
    return ordinary(value["path"])


def strict_json_bytes(raw, cap=65536):
    require(type(raw) is bytes and 0 < len(raw) <= cap and not raw.startswith(b"\xef\xbb\xbf"), "bounded JSON bytes")
    def pairs(rows):
        value = {}
        for key, item in rows:
            require(key not in value, "duplicate frame/control key")
            value[key] = item
        return value
    def bad(token):
        raise ValueError("nonfinite token")
    value = json.loads(raw.decode("utf-8", "strict"), object_pairs_hook=pairs, parse_constant=bad)
    def scalars(item):
        if type(item) is str:
            require("\0" not in item and all(not 0xD800 <= ord(c) <= 0xDFFF for c in item), "scalar UTF8 String")
        elif type(item) is dict:
            for key, child in item.items(): scalars(key); scalars(child)
        elif type(item) is list:
            for child in item: scalars(child)
        elif type(item) is float:
            require(float('-inf') < item < float('inf'), "finite JSON FLOAT")
    scalars(value)
    return value


class NativeApi:
    """Explicit lazily initialized Windows API. No calls during module import."""
    def __init__(self):
        require(os.name == "nt" and struct.calcsize("P") == 8, "Windows-x64 native qualification only")
        import ctypes
        from ctypes import wintypes as w
        self.c, self.w = ctypes, w
        self.k = ctypes.WinDLL("kernel32", use_last_error=True)
        self.invalid = ctypes.c_void_p(-1).value
        class FileTime(ctypes.Structure): _fields_ = [("low", w.DWORD), ("high", w.DWORD)]
        class FileId(ctypes.Structure): _fields_ = [("volume", ctypes.c_ulonglong), ("id", ctypes.c_ubyte * 16)]
        class FileInfo(ctypes.Structure):
            _fields_ = [("attributes", w.DWORD), ("created", FileTime), ("accessed", FileTime), ("written", FileTime),
                        ("volume", w.DWORD), ("size_high", w.DWORD), ("size_low", w.DWORD), ("links", w.DWORD),
                        ("id_high", w.DWORD), ("id_low", w.DWORD)]
        class ProcessEntry(ctypes.Structure):
            _fields_ = [("size", w.DWORD), ("usage", w.DWORD), ("pid", w.DWORD), ("heap", ctypes.c_size_t),
                        ("module", w.DWORD), ("threads", w.DWORD), ("parent", w.DWORD),
                        ("priority", w.LONG), ("flags", w.DWORD), ("name", w.WCHAR * 260)]
        class ModuleEntry(ctypes.Structure):
            _fields_=[('size',w.DWORD),('id',w.DWORD),('pid',w.DWORD),('global_usage',w.DWORD),('process_usage',w.DWORD),
                      ('base',w.LPVOID),('base_size',w.DWORD),('module',w.HMODULE),('name',w.WCHAR*256),('path',w.WCHAR*260)]
        class Overlapped(ctypes.Structure):
            _fields_ = [("internal", ctypes.c_size_t), ("internal_high", ctypes.c_size_t),
                        ("offset", w.DWORD), ("offset_high", w.DWORD), ("event", w.HANDLE)]
        class JobAccounting(ctypes.Structure):
            _fields_ = [("user", ctypes.c_longlong), ("kernel", ctypes.c_longlong),
                        ("period_user", ctypes.c_longlong), ("period_kernel", ctypes.c_longlong),
                        ("page_faults", w.DWORD), ("total_processes", w.DWORD), ("active", w.DWORD), ("terminated", w.DWORD)]
        class SecurityAttributes(ctypes.Structure):
            _fields_=[('length',w.DWORD),('descriptor',w.LPVOID),('inherit',w.BOOL)]
        class Startup(ctypes.Structure):
            _fields_=[('cb',w.DWORD),('reserved',w.LPWSTR),('desktop',w.LPWSTR),('title',w.LPWSTR),
                ('x',w.DWORD),('y',w.DWORD),('xsize',w.DWORD),('ysize',w.DWORD),('xchars',w.DWORD),('ychars',w.DWORD),
                ('fill',w.DWORD),('flags',w.DWORD),('show',w.WORD),('reserved_bytes',w.WORD),('reserved_ptr',w.LPVOID),
                ('stdin',w.HANDLE),('stdout',w.HANDLE),('stderr',w.HANDLE)]
        class StartupEx(ctypes.Structure): _fields_=[('startup',Startup),('attributes',w.LPVOID)]
        class ProcessInfo(ctypes.Structure): _fields_=[('process',w.HANDLE),('thread',w.HANDLE),('pid',w.DWORD),('tid',w.DWORD)]
        self.FileTime, self.FileId, self.FileInfo = FileTime, FileId, FileInfo
        self.ProcessEntry, self.Overlapped, self.JobAccounting = ProcessEntry, Overlapped, JobAccounting
        self.ModuleEntry=ModuleEntry
        self.SecurityAttributes,self.StartupEx,self.ProcessInfo=SecurityAttributes,StartupEx,ProcessInfo
        declarations = {
            "CloseHandle": ([w.HANDLE], w.BOOL),
            "CreateFileW": ([w.LPCWSTR,w.DWORD,w.DWORD,w.LPVOID,w.DWORD,w.DWORD,w.HANDLE], w.HANDLE),
            "GetFileType": ([w.HANDLE], w.DWORD),
            "GetFileInformationByHandle": ([w.HANDLE,ctypes.POINTER(FileInfo)], w.BOOL),
            "GetFileInformationByHandleEx": ([w.HANDLE,ctypes.c_int,w.LPVOID,w.DWORD], w.BOOL),
            "GetFinalPathNameByHandleW": ([w.HANDLE,w.LPWSTR,w.DWORD,w.DWORD], w.DWORD),
            "OpenProcess": ([w.DWORD,w.BOOL,w.DWORD], w.HANDLE),
            "GetProcessTimes": ([w.HANDLE,ctypes.POINTER(FileTime),ctypes.POINTER(FileTime),ctypes.POINTER(FileTime),ctypes.POINTER(FileTime)],w.BOOL),
            "GetExitCodeProcess": ([w.HANDLE,ctypes.POINTER(w.DWORD)],w.BOOL),
            "QueryFullProcessImageNameW": ([w.HANDLE,w.DWORD,w.LPWSTR,ctypes.POINTER(w.DWORD)],w.BOOL),
            "CreateToolhelp32Snapshot": ([w.DWORD,w.DWORD],w.HANDLE),
            "Process32FirstW": ([w.HANDLE,ctypes.POINTER(ProcessEntry)],w.BOOL),
            "Process32NextW": ([w.HANDLE,ctypes.POINTER(ProcessEntry)],w.BOOL),
            "Module32FirstW": ([w.HANDLE,ctypes.POINTER(ModuleEntry)],w.BOOL),
            "Module32NextW": ([w.HANDLE,ctypes.POINTER(ModuleEntry)],w.BOOL),
            "CreateNamedPipeW": ([w.LPCWSTR,w.DWORD,w.DWORD,w.DWORD,w.DWORD,w.DWORD,w.DWORD,w.LPVOID],w.HANDLE),
            "ConnectNamedPipe": ([w.HANDLE,ctypes.POINTER(Overlapped)],w.BOOL),
            "CreateEventW": ([w.LPVOID,w.BOOL,w.BOOL,w.LPCWSTR],w.HANDLE),
            "ReadFile": ([w.HANDLE,w.LPVOID,w.DWORD,ctypes.POINTER(w.DWORD),ctypes.POINTER(Overlapped)],w.BOOL),
            "WriteFile": ([w.HANDLE,w.LPCVOID,w.DWORD,ctypes.POINTER(w.DWORD),ctypes.POINTER(Overlapped)],w.BOOL),
            "GetOverlappedResult": ([w.HANDLE,ctypes.POINTER(Overlapped),ctypes.POINTER(w.DWORD),w.BOOL],w.BOOL),
            "CancelIoEx": ([w.HANDLE,ctypes.POINTER(Overlapped)],w.BOOL),
            "WaitForSingleObject": ([w.HANDLE,w.DWORD],w.DWORD),
            "GetNamedPipeClientProcessId": ([w.HANDLE,ctypes.POINTER(w.ULONG)],w.BOOL),
            "FlushFileBuffers": ([w.HANDLE],w.BOOL),
            "CreateJobObjectW": ([w.LPVOID,w.LPCWSTR],w.HANDLE),
            "AssignProcessToJobObject": ([w.HANDLE,w.HANDLE],w.BOOL),
            "TerminateJobObject": ([w.HANDLE,w.UINT],w.BOOL),
            "TerminateProcess": ([w.HANDLE,w.UINT],w.BOOL),
            "QueryInformationJobObject": ([w.HANDLE,ctypes.c_int,w.LPVOID,w.DWORD,ctypes.POINTER(w.DWORD)],w.BOOL),
            "InitializeProcThreadAttributeList": ([w.LPVOID,w.DWORD,w.DWORD,ctypes.POINTER(ctypes.c_size_t)],w.BOOL),
            "UpdateProcThreadAttribute": ([w.LPVOID,w.DWORD,ctypes.c_size_t,w.LPVOID,ctypes.c_size_t,w.LPVOID,w.LPVOID],w.BOOL),
            "DeleteProcThreadAttributeList": ([w.LPVOID],None),
            "CreateProcessW": ([w.LPCWSTR,w.LPWSTR,w.LPVOID,w.LPVOID,w.BOOL,w.DWORD,w.LPVOID,w.LPCWSTR,ctypes.POINTER(StartupEx),ctypes.POINTER(ProcessInfo)],w.BOOL),
            "ResumeThread": ([w.HANDLE],w.DWORD),
        }
        for name, (args, result) in declarations.items():
            fn = getattr(self.k, name); fn.argtypes = args; fn.restype = result

    def ok(self, value, label):
        if not value: raise self.c.WinError(self.c.get_last_error(), label)
        return value

    def close(self, handle):
        self.ok(self.k.CloseHandle(handle), "checked native CloseHandle")

    def handle(self, value):
        require(value not in [None, self.invalid], "actual native handle creation")
        return value

    def identity(self, handle, path=None, directory=False):
        identity, info = self.FileId(), self.FileInfo()
        self.ok(self.k.GetFileInformationByHandleEx(handle,18,self.c.byref(identity),self.c.sizeof(identity)), "FILE_ID_INFO")
        self.ok(self.k.GetFileInformationByHandle(handle,self.c.byref(info)), "BY_HANDLE_FILE_INFORMATION")
        require(not info.attributes & 0x400 and bool(info.attributes & 0x10) == directory and (directory or info.links == 1), "ordinary retained native file identity")
        final = self.c.create_unicode_buffer(32768)
        length = self.k.GetFinalPathNameByHandleW(handle,final,len(final),0)
        require(0 < length < len(final) and final.value.startswith("\\\\?\\") and not final.value.startswith("\\\\?\\UNC\\"), "local physical final path")
        if path is not None: require(final.value[4:].casefold() == str(path).casefold(), "retained path physical equality")
        return {"volume_serial": str(identity.volume), "file_id": bytes(identity.id).hex()}

    def lease(self, path, directory=False, access=0x80000000, creation=3, share=1):
        path = ordinary(path, directory) if creation == 3 else Path(os.path.abspath(path))
        if creation != 3: ordinary(path.parent, True); require(not path.exists(), "CreateNew fixture freshness")
        handle = self.handle(self.k.CreateFileW(str(path),access,share,None,creation,0x200000 | (0x2000000 if directory else 0),None))
        try: identity = self.identity(handle,path,directory)
        except BaseException:
            self.close(handle); raise
        return handle, identity

    def crash_directory_lease(self, path):
        path=ordinary(path,True)
        handle=self.handle(self.k.CreateFileW('\\\\?\\'+str(path),0,7,None,3,0x2200000,None))
        try: identity=self.identity(handle,path,True)
        except BaseException:
            self.close(handle);raise
        return handle,identity

    def crash_metadata(self, handle, path):
        """Actual zero-data-access handle observation; no inferred file facts."""
        info, identity = self.FileInfo(), self.FileId()
        self.ok(self.k.GetFileInformationByHandle(handle,self.c.byref(info)), 'crash FILE_INFORMATION')
        self.ok(self.k.GetFileInformationByHandleEx(handle,18,self.c.byref(identity),self.c.sizeof(identity)), 'crash FILE_ID_INFO')
        final=self.c.create_unicode_buffer(32768)
        length=self.k.GetFinalPathNameByHandleW(handle,final,len(final),0)
        require(0<length<len(final),'crash actual final path length')
        observed={'attributes':int(info.attributes),'links':int(info.links),
            'file_type':int(self.k.GetFileType(handle)), 'final_path':final.value,
            'volume_serial':str(identity.volume),'file_id':bytes(identity.id).hex(),
            'bytes':(int(info.size_high)<<32)|int(info.size_low)}
        return admit_crash_metadata(observed,str(path))

    def crash_file(self, path, relative, allow_denied):
        """Hash the actual read handle, or retain only exact sharing-denial metadata.

        Zero access/share7 observes an exclusively owned file without releasing,
        replacing or changing any production owner. OPEN_REPARSE_POINT prevents
        following a final reparse point. All successful handles close checked.
        """
        path=ordinary(path); metadata_handle=None; read_handle=None
        try:
            metadata_handle=self.handle(self.k.CreateFileW('\\\\?\\'+str(path),0,7,None,3,0x200000,None))
            before=self.crash_metadata(metadata_handle,path)
            self.c.set_last_error(0)
            attempted=self.k.CreateFileW('\\\\?\\'+str(path),0x80000000,7,None,3,0x200000,None)
            error=int(self.c.get_last_error())  # capture immediately, before any native call
            if attempted in [None,self.invalid]:
                require(error==32 and allow_denied,f'only source-eligible ERROR_SHARING_VIOLATION32: relative={relative!r}; actual_win32_error={error}; allow_denied={allow_denied!r}')
                require(self.crash_metadata(metadata_handle,path)==before,'denied metadata continuity')
                return crash_file_row(relative,before,None,error,allow_denied)
            read_handle=attempted
            require(self.crash_metadata(read_handle,path)==before,'read/metadata same physical file')
            h=hashlib.sha256(); count=0; buffer=self.c.create_string_buffer(65536)
            while True:
                completed=self.w.DWORD()
                self.ok(self.k.ReadFile(read_handle,buffer,len(buffer),self.c.byref(completed),None),'crash actual content read')
                require(completed.value<=len(buffer),'crash actual read bound')
                if not completed.value: break
                count+=int(completed.value)
                require(count<=before['bytes'] and count<=512*1024*1024,'crash actual content cap')
                h.update(buffer.raw[:completed.value])
            require(count==before['bytes'] and self.crash_metadata(read_handle,path)==before
                    and self.crash_metadata(metadata_handle,path)==before,'actual full-read identity/size continuity')
            return crash_file_row(relative,before,h.hexdigest(),0,allow_denied)
        finally:
            try:
                if read_handle is not None: self.close(read_handle)
            finally:
                if metadata_handle is not None: self.close(metadata_handle)


    def process(self, pid, live=True):
        actual_int(pid,1,0xffffffff,"actual PID")
        handle = self.handle(self.k.OpenProcess(0x101000,False,pid))
        try:
            a,b,c,d = (self.FileTime() for _ in range(4)); code = self.w.DWORD()
            self.ok(self.k.GetProcessTimes(handle,self.c.byref(a),self.c.byref(b),self.c.byref(c),self.c.byref(d)), "actual process creation")
            self.ok(self.k.GetExitCodeProcess(handle,self.c.byref(code)), "actual process liveness")
            if live: require(code.value == 259, "required process no longer live")
            buffer = self.c.create_unicode_buffer(32768); size = self.w.DWORD(len(buffer))
            self.ok(self.k.QueryFullProcessImageNameW(handle,0,buffer,self.c.byref(size)), "actual process executable")
            return {"pid": pid,"creation_filetime": str((a.high << 32) | a.low),"executable": native_pin(buffer.value)}
        finally: self.close(handle)

    def parent(self, pid):
        handle = self.handle(self.k.CreateToolhelp32Snapshot(2,0))
        try:
            row = self.ProcessEntry(); row.size = self.c.sizeof(row)
            more = self.k.Process32FirstW(handle,self.c.byref(row))
            while more:
                if row.pid == pid: return int(row.parent)
                more = self.k.Process32NextW(handle,self.c.byref(row))
            raise ValueError("actual Toolhelp parent absent")
        finally: self.close(handle)

    def ancestry(self, child, expected):
        result = []
        for row in expected:
            parent = self.parent(child)
            observed = self.process(parent)
            require(observed == row, "actual parent/PID/creation/executable chain")
            result.append(observed); child = parent
        return result

    def modules(self,pid):
        handle=self.handle(self.k.CreateToolhelp32Snapshot(0x18,pid))
        try:
            row=self.ModuleEntry(); row.size=self.c.sizeof(row); result=[]
            more=self.k.Module32FirstW(handle,self.c.byref(row)); require(more,"actual module enumeration")
            while more:
                result.append(observed_module_pin(row.path)); more=self.k.Module32NextW(handle,self.c.byref(row))
            require(self.c.get_last_error()==18,"complete actual module enumeration")
            return result
        finally:self.close(handle)


class RetainedFiles:
    def __init__(self, api): self.api, self.items = api, []
    def add(self, pin):
        path = admit_actual_pin(pin)
        handle, identity = self.api.lease(path)
        self.items.append((handle,path,pin,identity))
        require(native_pin(path) == pin, "raw pin after retained lease")
        return pin
    def recheck(self):
        for handle,path,pin,identity in self.items:
            require(self.api.identity(handle,path) == identity and native_pin(path) == pin, "retained input identity/raw continuity")
    def close(self):
        self.recheck()
        while self.items:
            self.api.close(self.items[-1][0]); self.items.pop()


def fresh_evidence(parent, prefix):
    parent = ordinary(parent,True)
    path = parent / (prefix + "-" + uuid.uuid4().hex)
    path.mkdir(exist_ok=False)
    return ordinary(path,True)


def observe_job_retirement(query_active, deadline):
    """Require real zero-active accounting within the ORIGINAL operation deadline.

    No termination here, new grace period, job-handle wait or inferred join.
    query_active raises on failed actual QueryInformationJobObject.
    """
    while True:
        require(time.monotonic() <= deadline, "job retirement operation deadline expired")
        active = query_active()
        require(type(active) is int and 0 <= active <= 0xffffffff, "actual active process count")
        require(time.monotonic() <= deadline, "job retirement query exceeded operation deadline")
        if active == 0:
            return
        remaining = deadline - time.monotonic()
        require(remaining > 0, "descendants remain active at operation deadline")
        time.sleep(min(.01, remaining))


class NativeObservedChild:
    """Suspended CreateProcess with explicit three-handle allowlist, then resume.

    Before-resume hooks are only source-fixed supervisor publication, never caller
    callbacks. Stdout/stderr go directly to retained native CREATE_NEW files; no
    pipe reader can block an otherwise completed process or lose buffered data.
    """
    def __init__(self,api,executable,argv,cwd,root,label,before_resume=None,profile=None):
        self.api,self.tool,self.argv,self.cwd=api,executable,argv,ordinary(cwd,True)
        self.root=fresh_evidence(root,label); self.start=time.monotonic()
        self.handles=[]; self.job=None; self.process_handle=None; self.thread=None; self.pid=None; self.terminal=None
        admit_actual_pin(executable); require(type(argv) is list and all(type(a) is str and '\0' not in a for a in argv),"literal native argv")
        sa=api.SecurityAttributes(api.c.sizeof(api.SecurityAttributes),None,True)
        attributes=None
        overlay={}
        if profile is not None:
            profile=ordinary(profile,True)
            for name in ['APPDATA','LOCALAPPDATA','TEMP','TMP']:
                p=profile/name; p.mkdir(exist_ok=False); overlay[name]=str(ordinary(p,True))
        environment=None
        if overlay:
            values={k.upper():v for k,v in os.environ.items()}; values.update(overlay)
            require(all('\0' not in k+v and '=' not in k for k,v in values.items()),"literal native environment")
            environment=api.c.create_unicode_buffer('\0'.join(k+'='+values[k] for k in sorted(values))+'\0\0')
        self.before_pin=write_new(self.root/'before.json',json_bytes({'schema':'LocalPlayersNativeChildBefore/v1','name':label,
            'tool':executable,'argv':argv,'cwd':str(self.cwd),'supervisor':api.process(os.getpid()),
            'capture':'native inherited CREATE_NEW stdout/stderr files; handle-list restricted','profile_environment':overlay,
            'started_monotonic_ns':time.monotonic_ns()}))
        try:
            for name in ['stdout.log','stderr.log']:
                path=self.root/name
                h=api.handle(api.k.CreateFileW(str(path),0x40000000,1,api.c.byref(sa),1,0x200000,None))
                self.handles.append(h)
            stdin=api.handle(api.k.CreateFileW('NUL',0x80000000,3,api.c.byref(sa),3,0,None)); self.handles.append(stdin)
            size=api.c.c_size_t()
            require(not api.k.InitializeProcThreadAttributeList(None,1,0,api.c.byref(size)) and api.c.get_last_error()==122,"actual attribute-list sizing")
            storage=api.c.create_string_buffer(size.value); attributes=api.c.cast(storage,api.w.LPVOID)
            api.ok(api.k.InitializeProcThreadAttributeList(attributes,1,0,api.c.byref(size)),"process handle-list initialize")
            inherit=(api.w.HANDLE*3)(stdin,self.handles[0],self.handles[1])
            api.ok(api.k.UpdateProcThreadAttribute(attributes,0,0x20002,api.c.cast(inherit,api.w.LPVOID),api.c.sizeof(inherit),None,None),"explicit stdhandle inheritance list")
            startup=api.StartupEx(); startup.startup.cb=api.c.sizeof(startup); startup.startup.flags=0x100
            startup.startup.stdin=stdin; startup.startup.stdout=self.handles[0]; startup.startup.stderr=self.handles[1]; startup.attributes=attributes
            info=api.ProcessInfo(); command=api.c.create_unicode_buffer(subprocess.list2cmdline([executable['path'],*argv]))
            # list2cmdline is OS argv encoding only, never observed-command parsing
            # or construction of expected compiler/linker argv.
            self.job=api.handle(api.k.CreateJobObjectW(None,None))
            api.ok(api.k.CreateProcessW(executable['path'],command,None,None,True,0x08080004|(0x400 if environment is not None else 0),environment,str(self.cwd),api.c.byref(startup),api.c.byref(info)),"actual suspended native CreateProcessW")
            self.process_handle,self.thread,self.pid=info.process,info.thread,int(info.pid)
            if not api.k.AssignProcessToJobObject(self.job,self.process_handle):
                # A failed assignment leaves a suspended, unassigned process;
                # terminating an empty job cannot retire that process.
                api.ok(api.k.TerminateProcess(self.process_handle,125),'unassigned suspended child termination')
                require(api.k.WaitForSingleObject(self.process_handle,10000)==0,'unassigned child actual exit')
                raise ValueError('actual pre-resume child job assignment failed')
            self.observed=api.process(self.pid)
            require(self.observed['executable']['sha256']==executable['sha256'] and self.observed['executable']['bytes']==executable['bytes']
                    and self.observed['executable']['path'].casefold()==executable['path'].casefold()
                    and api.parent(self.pid)==os.getpid(),"pre-resume actual executable/direct-parent identity")
            write_new(self.root/'created-suspended.json',json_bytes({'process':self.observed,'parent':api.process(os.getpid()),'job_assigned':True,'stdhandle_allowlist_count':3}))
            if before_resume is not None: before_resume(self)
            require(api.k.ResumeThread(self.thread)==1,"resume exactly one suspended native child")
            api.close(self.thread); self.thread=None
        except BaseException:
            if self.process_handle is not None:
                api.ok(api.k.TerminateJobObject(self.job,125),"failed startup native job termination")
                require(api.k.WaitForSingleObject(self.process_handle,10000)==0,"failed startup actual exit")
            if self.thread is not None: api.close(self.thread); self.thread=None
            if self.process_handle is not None: api.close(self.process_handle); self.process_handle=None
            if self.job is not None: api.close(self.job); self.job=None
            while self.handles: api.close(self.handles[-1]); self.handles.pop()
            raise
        finally:
            if attributes is not None: api.k.DeleteProcThreadAttributeList(attributes)

    def live(self):
        require(self.api.k.WaitForSingleObject(self.process_handle,0)==258 and self.api.process(self.pid)==self.observed,"actual child alive")

    def finish(self,seconds,expected_code=0):
        api=self.api; error=None; code=api.w.DWORD(); timed_out=False; exited=False; retired=False
        try:
            ms=max(0,int((seconds-(time.monotonic()-self.start))*1000))
            wait=api.k.WaitForSingleObject(self.process_handle,min(ms,0xfffffffe))
            require(wait in [0,258],"actual child wait")
            if wait==258:
                timed_out=True; api.ok(api.k.TerminateJobObject(self.job,124),"watchdog actual tree termination")
                require(api.k.WaitForSingleObject(self.process_handle,10000)==0,"watchdog observed child exit")
            exited=True; api.ok(api.k.GetExitCodeProcess(self.process_handle,api.c.byref(code)),"observed exit code")
            # ActiveProcesses may retain an exited process while references
            # remain. Capture its actual exit first, then CHECKED close our
            # direct process handle before observing whole-job retirement.
            api.close(self.process_handle); self.process_handle=None
            require(not timed_out and code.value==expected_code,"actual exit/watchdog mismatch")
            def query_active():
                accounting=api.JobAccounting()
                api.ok(api.k.QueryInformationJobObject(self.job,1,api.c.byref(accounting),api.c.sizeof(accounting),None),"actual job accounting")
                return int(accounting.active)
            observe_job_retirement(query_active,self.start+seconds)
            require(native_pin(self.tool['path'])==self.tool,"actual executable continuity")
        except BaseException as failed:
            error=type(failed).__name__+': '+str(failed)
            api.ok(api.k.TerminateJobObject(self.job,125),"failure retained child-tree termination")
            if self.process_handle is not None:
                require(api.k.WaitForSingleObject(self.process_handle,10000)==0,"failure observed exit before handles retire")
                exited=True; api.ok(api.k.GetExitCodeProcess(self.process_handle,api.c.byref(code)),"failure actual exit")
                api.close(self.process_handle); self.process_handle=None
        finally:
            # No positive 'drained' until all actual job processes retired and
            # every parent log handle flushed/closed successfully.
            accounting=api.JobAccounting()
            api.ok(api.k.QueryInformationJobObject(self.job,1,api.c.byref(accounting),api.c.sizeof(accounting),None),"final job retirement")
            if accounting.active:
                api.ok(api.k.TerminateJobObject(self.job,125),"remaining descendants failure termination")
                deadline=time.monotonic()+10
                while accounting.active:
                    require(time.monotonic()<deadline,"retain descendant lifetime on failure")
                    time.sleep(.01); api.ok(api.k.QueryInformationJobObject(self.job,1,api.c.byref(accounting),api.c.sizeof(accounting),None),"descendant termination observation")
                error=error or 'unexpected live descendant after direct child exit'
            for h in self.handles[:2]: api.ok(api.k.FlushFileBuffers(h),"actual captured log flush")
            while self.handles: api.close(self.handles[-1]); self.handles.pop()
            if self.process_handle is not None: api.close(self.process_handle); self.process_handle=None
            api.close(self.job); self.job=None; retired=True
            self.terminal={'schema':'LocalPlayersNativeChildTerminal/v1','before':self.before_pin,'process':self.observed,
                'exit_observed':exited,'exit_code':int(code.value),'timed_out':timed_out,'drained':retired,
                'elapsed_ms':(time.monotonic()-self.start)*1000,'expected_exit':expected_code,'qualified_process':error is None,'error':error}
            write_new(self.root/'terminal.json',json_bytes(self.terminal))
        require(error is None,error or 'child failed')
        return {'before':self.before_pin,'terminal':native_pin(self.root/'terminal.json'),'stdout':native_pin(self.root/'stdout.log'),'stderr':native_pin(self.root/'stderr.log')}


# The source-fixed transport/supervisor uses only the suspended native launcher.
ObservedChild = NativeObservedChild


class ActorPipes:
    """Two noninherited OVERLAPPED servers; pending storage retires only after observed completion."""
    # Module-lifetime strong owners survive every operation/close unwind.
    _retained_operations = []
    def __init__(self, api, nonce, evidence):
        require(re.fullmatch('[0-9a-f]{32}',nonce) is not None,"pipe nonce")
        self.api, self.nonce, self.evidence = api, nonce, evidence
        self.names = ['\\\\.\\pipe\\flight-local-players-'+nonce+'-'+suffix for suffix in ['stdin','stdout']]
        self.handles, self.operations = [], []
        self.raw = (evidence/'actor.frames.ndjson').open('xb')
        self.record_count = 0; self.record_bytes = 0
        try:
            for index,name in enumerate(self.names):
                # FILE_FLAG_FIRST_PIPE_INSTANCE + OVERLAPPED, byte/read byte/wait,
                # PIPE_REJECT_REMOTE_CLIENTS; NULL security attributes => noninherit.
                h = api.handle(api.k.CreateNamedPipeW(name,(2 if index == 0 else 1)|0x40000000|0x00080000,8,1,8192,8192,0,None))
                self.handles.append(h)
        except BaseException:
            self.close(); raise

    def operation(self, handle, action, buffer=None, length=0, seconds=10, child=None):
        require(action in ['connect','read','write'],"closed actor pipe operation")
        require(not self.operations,"one actual actor operation at a time")
        api = self.api; event = api.handle(api.k.CreateEventW(None,True,False,None))
        ov = api.Overlapped(); ov.event = event; count = api.w.DWORD()
        # Keep kernel-referenced storage alive even if cancellation, observation
        # or Python unwinding fails. Only observed retirement removes this owner.
        owned = {'owner':self,'handle':handle,'event':event,'overlapped':ov,
                 'count':count,'buffer':buffer,'pending':False,'started_pending':False,'failure':None}
        self.operations.append(owned); ActorPipes._retained_operations.append(owned)
        deadline = time.monotonic()+seconds
        stage = 'start'; last_code = None; problems = []

        def problem(error, where, code=None):
            name = type(error).__name__
            if re.fullmatch('[A-Za-z_][A-Za-z0-9_]{0,63}',name) is None: name = 'Exception'
            observed = getattr(error,'winerror',None)
            if type(observed) is int: code = observed
            if type(code) is not int or not -(1<<31) <= code <= 0xffffffff: code = None
            return where+':'+name+':win32='+('none' if code is None else str(code))

        def failure():
            return 'actor pipe '+action+'; '+'; '.join(problems)+'; pending='+str(owned['pending'])

        def observe_result():
            done = api.k.GetOverlappedResult(handle,api.c.byref(ov),api.c.byref(count),False)
            code = 0 if done else api.c.get_last_error()
            # Called only after this operation's manual-reset event signaled.
            # ERROR_IO_INCOMPLETE is never terminal. For a failed result, also
            # require the documented OVERLAPPED status to have left STATUS_PENDING
            # (HasOverlappedIoCompleted semantics, only after ERROR_IO_PENDING).
            terminal = bool(done) or (owned['started_pending'] and code != 996 and
                                      (int(ov.internal)&0xffffffff) != 0x103)
            if terminal: owned['pending'] = False
            return bool(done), code, terminal

        try:
            # If a Python/API invocation itself raises, its issuance state is
            # uncertain: conservatively retain until separately observed done.
            owned['pending'] = True
            if action == 'connect': ok = api.k.ConnectNamedPipe(handle,api.c.byref(ov))
            elif action == 'read': ok = api.k.ReadFile(handle,buffer,length,api.c.byref(count),api.c.byref(ov))
            else: ok = api.k.WriteFile(handle,buffer,length,api.c.byref(count),api.c.byref(ov))
            last_code = 0 if ok else api.c.get_last_error()
            owned['started_pending'] = not bool(ok) and last_code == 997
            owned['pending'] = owned['started_pending']
            if action == 'connect' and last_code == 535: return 0
            require(ok or last_code == 997,"actual named-pipe start failed")
            while owned['pending']:
                stage = 'wait'; wait = api.k.WaitForSingleObject(event,20)
                if wait == 0:
                    stage = 'result'
                    done, last_code, terminal = observe_result()
                    require(terminal and done,"actual completed OVERLAPPED success required")
                elif wait == 258:
                    stage = 'deadline'; require(time.monotonic() < deadline,"pipe operation observation deadline")
                    if child is not None:
                        stage = 'child_live'; last_code = None; child.live()
                else:
                    last_code = api.c.get_last_error(); raise ValueError("named-pipe wait failed")
            require(last_code == 0,"pending operation success must clear ERROR_IO_PENDING")
            return int(count.value)
        except BaseException as original:
            problems.append(problem(original,stage,last_code))
            if owned['pending']:
                try:
                    cancelled = api.k.CancelIoEx(handle,api.c.byref(ov))
                    cancel_code = 0 if cancelled else api.c.get_last_error()
                    if not cancelled and cancel_code != 1168:
                        problems.append('cancel:failure:win32='+str(cancel_code))
                    elif not cancelled:
                        problems.append('cancel:race:win32=1168')
                except BaseException as cancel_error:
                    problems.append(problem(cancel_error,'cancel'))
                # Cancellation is only a request. Observe completion, including
                # failed terminal results other than ERROR_OPERATION_ABORTED.
                # No new success/deadline budget is granted for failure cleanup.
                while owned['pending']:
                    remaining = deadline-time.monotonic()
                    try:
                        wait = api.k.WaitForSingleObject(event,min(100,max(0,int(remaining*1000))))
                        if wait == 0:
                            done, code, terminal = observe_result()
                            if terminal:
                                if not done and code != 995:
                                    problems.append('cancel_result:failure:win32='+str(code))
                                break
                            problems.append('cancel_result:incomplete:win32='+str(code)); break
                        if wait != 258:
                            problems.append('cancel_wait:failure:win32='+str(api.c.get_last_error())); break
                        if time.monotonic() >= deadline:
                            problems.append('cancel_wait:deadline:win32=none'); break
                    except BaseException as drain_error:
                        problems.append(problem(drain_error,'cancel_observation')); break
            owned['failure'] = failure()
            raise ValueError(owned['failure']) from original
        finally:
            # On incomplete/failed observation the class-owned record survives
            # this frame, retaining even the buffer's backing ctypes object.
            # close() refuses those handles; Root observes failed process exit,
            # never a fabricated drained/qualified operation.
            if not owned['pending']:
                try: api.close(event)
                except BaseException as close_error:
                    problems.append(problem(close_error,'event_close'))
                    owned['failure'] = failure()
                    raise ValueError(owned['failure']) from close_error
                self.operations.remove(owned); ActorPipes._retained_operations.remove(owned)

    def connect(self, child):
        for handle in self.handles:
            self.operation(handle,'connect',seconds=45,child=child)
            pid = self.api.w.ULONG()
            self.api.ok(self.api.k.GetNamedPipeClientProcessId(handle,self.api.c.byref(pid)),"actual named-pipe child PID")
            require(pid.value == child.pid,"actor must open own client; inherited/opener PID rejected")
        child.live()

    def exact_read(self, count, child, seconds=120):
        result = bytearray(); deadline = time.monotonic()+seconds
        while len(result) < count:
            buffer = self.api.c.create_string_buffer(count-len(result))
            n = self.operation(self.handles[1],'read',buffer,len(buffer),max(0,deadline-time.monotonic()),child)
            require(0 < n <= len(buffer),"complete actor read/EOF")
            result.extend(buffer.raw[:n])
        return bytes(result)

    def read_frame(self, child, maximum_records=524290):
        length = struct.unpack('<I',self.exact_read(4,child))[0]
        require(1 <= length <= 4096,"actor frame length")
        raw = self.exact_read(length,child)
        value = strict_json_bytes(raw,4096)
        self.record_count += 1; self.record_bytes += length+4
        require(self.record_count <= maximum_records and self.record_bytes <= maximum_records*4100,"bounded complete raw actor stream")
        # Raw JSON bytes retained before semantic admission, no rewritten frame.
        self.raw.write(raw+b'\n'); self.raw.flush()
        return value

    def release(self, child):
        raw = json_bytes({"type":"RELEASE","nonce":self.nonce,"pid":child.pid,"action_ordinal":1})
        frame = struct.pack('<I',len(raw))+raw; position = 0; buffer = self.api.c.create_string_buffer(frame)
        deadline = time.monotonic()+10
        while position < len(frame):
            n = self.operation(self.handles[0],'write',self.api.c.byref(buffer,position),len(frame)-position,max(0,deadline-time.monotonic()),child)
            require(n > 0,"actual release write progress"); position += n

    def close(self):
        if self.operations:
            raise ValueError(self.operations[0]['failure'] or 'actor pipe operation still owned; no handle retirement')
        while self.handles: self.api.close(self.handles[-1]); self.handles.pop()
        if not self.raw.closed: self.raw.flush(); os.fsync(self.raw.fileno()); self.raw.close()


def admit_ready(value, nonce, pid, role, descriptor, plan):
    exact_keys(value,['type','nonce','pid','role','capability_sha256','plan_sha256'])
    require(value == {'type':'READY','nonce':nonce,'pid':pid,'role':role,'capability_sha256':descriptor,'plan_sha256':plan},"actual READY bindings")
    actual_int(value['pid'],1,0xffffffff,'READY actual PID')


def admit_closed(value, nonce, pid):
    exact_keys(value,['type','nonce','pid','reason','handles_closed'])
    require(value['type']=='CLOSED' and value['nonce']==nonce and type(value['pid']) is int and value['pid']==pid
            and value['reason']=='released' and value['handles_closed'] is True,"normal actor checked CLOSED only")


def admit_reservation(value, nonce, pid, service, sequence):
    exact_keys(value,['type','nonce','pid','reservation_sequence','action','category','service_ordinal','request_ordinal','allocation_ordinal','requested','rounded','reserved_pages','live_pages'])
    require(value['type']=='RESERVATION' and value['nonce']==nonce and value['pid']==pid and type(value['pid']) is int,"reservation stream actor binding")
    require(canonical_u64(value['reservation_sequence'],True)==sequence,"separate monotonic reservation sequence")
    require(value['action'] in ['claim','release','share','unshare'] and value['category'] in ['control','request','terminal','delivery','workspace','export_spool'],"reservation enums")
    require(actual_int(value['service_ordinal'],1,(1<<63)-1,'reservation service')==service,"reservation source service")
    actual_int(value['request_ordinal'],0,(1<<63)-1,'reservation request'); actual_int(value['allocation_ordinal'],1,(1<<63)-1,'reservation allocation')
    requested=actual_int(value['requested'],0,33554432,'requested actual bytes'); rounded=actual_int(value['rounded'],0,33554432,'rounded actual bytes')
    require(rounded>=requested and rounded%4096==0,"reservation rounding")
    for k in ['reserved_pages','live_pages']: actual_int(value[k],0,8192,k)
    return value


def source_test_roster(source):
    allocation,_=load_json(source/'docs/contracts/local-players/compiled-source-allocation-v1.json',ALLOCATION_SHA)
    tests=allocation['test_sources']
    names=[]
    for group in ['shared_core','windows_only','original_references','service_reference','full_record_reference','reservation_reference','metadata']:
        names.extend(tests[group])
    # Journey219/220 source is allocated but not consumed by focused BridgeChecks;
    # it must be present only when actually claimed by a separate journey gate.
    return [n for n in names if not n.endswith('/journey_checks.gd')]


def verify_cpp_compile(database, invocation, source, obj):
    before,terminal=read_invocation(invocation)
    require(before['kind']=='compile' and native_pin(source) in before['inputs'] and native_pin(obj) in terminal['outputs'],"actual test C++ compile input/output")
    rows,_=load_json(database); matches=[]
    for row in rows:
        require(type(row) is dict and type(row.get('directory')) is str and type(row.get('file')) is str,"CMake compile row metadata")
        cwd=ordinary(row['directory'],True)
        if ordinary(cwd/row['file'])==source: matches.append((row,cwd))
    # The same native.cpp is intentionally compiled into store and crash targets.
    matches=[(r,c) for r,c in matches if type(r.get('output')) is str and ordinary(c/r['output'])==obj]
    require(len(matches)==1,"one target/source/object CMake metadata row")
    row,cwd=matches[0]
    require(cwd==ordinary(before['cwd'],True) and actual_source(before['expanded_argv'],cwd,source),"actual C++ source/cwd match")
    if 'arguments' in row: require(row['arguments']==before['argv'],"actual compile arguments")
    else: require(type(row.get('command')) is str and row['command'],"bind original CMake command bytes; do not reconstruct")
    args=before['expanded_argv']; options=['/'+a[1:] if a.startswith('-') else a for a in args]
    require('/fp:strict' in options and not any(a.lower().startswith('/fp:') and a!='/fp:strict' for a in options),"test source strict FP")
    require('/WX' in options and '/W4' in options and '/utf-8' in options,"strict test compiler flags")
    defines,includes,outputs,forces=compiler_fields(args)
    require(len(outputs)==1 and ordinary(cwd/outputs[0])==obj,"actual unique test object operand")
    require('/MD' in options or '/MDd' in options,"actual dynamic MSVC CRT test compile")
    return {'source':native_pin(source),'object':native_pin(obj),'before':native_pin(Path(invocation)/'before.json'),
            'terminal':native_pin(Path(invocation)/'terminal.json'),'compile_database':native_pin(database),'row_index':rows.index(row)}


def admit_test_build(path, expected_sha):
    """Reconstruct measured bindings; a passed scalar is never sufficient."""
    value,raw=load_json(path,expected_sha)
    exact_keys(value,['schema','source_root','dependency_root','build_root','source_identity','configuration_cache',
        'production_build','compile_database','test_source_bindings','reference_bindings','targets','crt','ctest_source','scope'])
    require(value['schema']=='LocalPlayersTestCompiledBuildEvidence/v1',"fresh test-enabled build manifest required; ordinary Build is ineligible")
    source,deps,build=(ordinary(value[k],True) for k in ['source_root','dependency_root','build_root'])
    for row in [value['source_identity'],value['configuration_cache'],value['production_build'],value['compile_database'],value['ctest_source']]: admit_actual_pin(row)
    require(ordinary(value['ctest_source']['path'])==source/'tests/persistence/local_players/CMakeLists.txt',"actual allocated CTest source")
    identity,_=load_json(value['source_identity']['path'],value['source_identity']['sha256'])
    qualify_identity_inputs(identity)
    require([ordinary(identity[k],True) for k in ['source_root','dependency_root','build_root']]==[source,deps,build],"same fresh test build identity roots")
    header,_=identity_header(value['source_identity']['path'],value['source_identity']['sha256'])
    require((build/'local-players-generated/compiled_identity.hpp').read_bytes()==header,"same exact independently derived forced header")
    cache=ordinary(value['configuration_cache']['path']).read_text(encoding='utf-8')
    def cache_entry(name):
        rows=[line.split('=',1)[1] for line in cache.splitlines() if line.startswith(name+':') and '=' in line]
        require(len(rows)==1,"one actual test configure cache entry "+name); return rows[0]
    for name in ['BUILD_TESTING','FLIGHT_BUILD_LOCAL_PLAYERS','FLIGHT_BUILD_LOCAL_PLAYERS_TEST_BRIDGE']:
        require(cache_entry(name)=='ON',"test-enabled single configure required "+name)
    require(cache_entry('FLIGHT_LOCAL_PLAYERS_QUALIFICATION_MODE')=='windows',"Windows qualification mode")
    require(cache_entry('CMAKE_HOME_DIRECTORY').replace('\\','/')==source.as_posix(),"actual CMake source root")
    require(ordinary(value['configuration_cache']['path'])==build/'CMakeCache.txt' and ordinary(value['compile_database']['path'])==build/'compile_commands.json',"same configure metadata")
    production,_=load_json(value['production_build']['path'],value['production_build']['sha256'])
    require(production['schema']=='LocalPlayersCompiledBuildEvidence/v1' and production['compiled_build_verified'] is True
            and production['source_identity']==value['source_identity'] and production['compiled_source_count']==9,
            "actual independently admitted production build closure")
    require(len(production['compiles'])==9,"nine actual production compiles")
    production_runs={}
    for compile_row in production['compiles']:
        exact_keys(compile_row,['source','object','invocation_before','invocation_terminal','command_sha256'])
        for name in ['source','object','invocation_before','invocation_terminal']: admit_actual_pin(compile_row[name])
        run=ordinary(compile_row['invocation_before']['path']).parent
        require(ordinary(compile_row['invocation_terminal']['path'])==run/'terminal.json',"production invocation pair")
        before,terminal=read_invocation(run)
        require(before['kind']=='compile' and terminal['outputs']==[compile_row['object']]
                and actual_source(before['expanded_argv'],ordinary(before['cwd'],True),ordinary(compile_row['source']['path']))
                and before['command_sha256']==compile_row['command_sha256'],"actual production source/object/argv")
        require(compile_row['source']['path'] not in production_runs,"unique production source")
        production_runs[compile_row['source']['path']]=run
    for key in ['sqlite_archive','production_archives','forced_header','inner_link','actual_link_plan_chain']:
        require(key in production,"mandatory production measured witness "+key)
    archives=production['production_archives']
    require(type(archives) is list and len(archives)==2,"exact actual core/windows archive witnesses")
    archive_pins=[]
    require([r['target'] for r in archives]==['flight_local_players_core','flight_local_players_windows'],"ordered production archive targets")
    for archive_row,expected_count in zip(archives,[5,1]):
        exact_keys(archive_row,['target','archive','objects','members','object_roster_sha256','scope'])
        archive=archive_row['archive']; admit_actual_pin(archive)
        members=read_msvc_archive(ordinary(archive['path']).read_bytes())
        objects=archive_row['objects']
        require(len(members)==len(objects)==expected_count,"actual production object/member count")
        remaining=list(members)
        for obj in objects:
            obj_pin=obj['object'] if 'object' in obj else obj; admit_actual_pin(obj_pin)
            require(obj_pin in [r['object'] for r in production['compiles']],"archive object actually compiled in same production build")
            matches=[m for m in remaining if ntpath.basename(m['name'])==Path(obj_pin['path']).name
                     and m['bytes']==obj_pin['bytes'] and m['sha256']==obj_pin['sha256']
                     and m['data']==ordinary(obj_pin['path']).read_bytes()]
            require(len(matches)==1,"actual core/windows object archive bijection"); remaining.remove(matches[0])
        roster=[{k:m[k] for k in ['offset','name','bytes','sha256']} for m in members]
        require(not remaining and roster==archive_row['members'] and digest(json_bytes(roster))==archive_row['object_roster_sha256'],"exact recorded production archive roster")
        archive_pins.append(archive)
    sqlite=production['sqlite_archive']; admit_actual_pin(sqlite['archive']); admit_actual_pin(sqlite['object'])
    require(sqlite_archive_witness(sqlite['archive']['path'],sqlite['object']['path'])==sqlite,"actual SQLite object archive closure")
    sqlite_rows=[r for r in production['compiles'] if Path(r['source']['path']).name=='sqlite3.c']
    require(len(sqlite_rows)==1,"one actual SQLite production compile")
    require(match_compile_database(value['compile_database']['path'],production_runs[sqlite_rows[0]['source']['path']],
            sqlite_rows[0]['source']['path'],sqlite['object']['path'])==production['sqlite_compile'],"actual SQLite C compile closure")
    identity_rows=[r for r in production['compiles'] if Path(r['source']['path']).name=='storage_identity.cpp']
    require(len(identity_rows)==1 and verify_header_compile(production_runs[identity_rows[0]['source']['path']],
            value['source_identity']['path'],value['source_identity']['sha256'],build/'local-players-generated/compiled_identity.hpp')==production['forced_header'],"actual forced-header compile")
    prelink,_=load_json(production['prelink_admission']['path'],production['prelink_admission']['sha256'])
    link_roots=list(ordinary(build/'local-players-witness/link-receipts',True).iterdir())
    require(len(link_roots)==1 and link_roots[0].name.startswith('invocation-'),"one shipping measured inner link")
    link_before,link_terminal=read_invocation(ordinary(link_roots[0],True))
    require(link_before['plan']==prelink['plan'] and link_before['plan_digest_file']==prelink['plan_digest_file'],"actual frozen prelink authority")
    link_run=ordinary(link_terminal['before']['path']).parent
    require(link_inclusion_witness(link_run,sqlite['archive']['path'],sqlite['object']['path'],
            production['inner_link']['dll']['path'],production['inner_link']['map']['path'])==production['inner_link'],"actual shipping inner-link/SQLite map closure")
    archive_pins.append(sqlite['archive'])
    names=source_test_roster(source)
    require(type(value['test_source_bindings']) is list and [r['path'] for r in value['test_source_bindings']]==names,"exact allocated test-source/reference roster")
    for row in value['test_source_bindings']:
        exact_keys(row,['path','bytes','sha256']); actual=native_pin(source/row['path'])
        require(actual['bytes']==row['bytes'] and actual['sha256']==row['sha256'],"actual test source/reference raw binding")
    refs=[n for n in names if '/reference/' in n or '/service_reference/' in n or '/full_record_reference/' in n or '/reservation_reference/' in n]
    require([r['path'] for r in value['reference_bindings']]==refs,"all fixed reference inputs required")
    for row in value['reference_bindings']:
        require(row in value['test_source_bindings'],"reference raw correspondence")
    require(type(value['targets']) is list and [r['role'] for r in value['targets']]==list(TEST_TARGETS),"exact eight allocated test targets")
    children={}
    test_dir=source/'tests/persistence/local_players'
    for row in value['targets']:
        exact_keys(row,['role','target','output','objects','link_invocation'])
        target,expected_sources=TEST_TARGETS[row['role']]
        require(row['target']==target,"closed target name")
        output=admit_actual_pin(row['output']); require(output.is_relative_to(build),"test output in actual fresh build")
        expected=[source/'native/persistence/godot_bridge/src/local_players.cpp' if n=='@boundary' else test_dir/n for n in expected_sources]
        require([ordinary(o['source']['path']) for o in row['objects']]==expected,"exact target compilation source roster")
        for item,src in zip(row['objects'],expected):
            exact_keys(item,['source','object','invocation'])
            admit_actual_pin(item['source']); obj=admit_actual_pin(item['object'])
            require(obj.is_relative_to(build),"test object path contained")
            verify_cpp_compile(value['compile_database']['path'],ordinary(item['invocation'],True),src,obj)
        before,terminal=read_invocation(ordinary(row['link_invocation'],True))
        require(before['kind']=='link' and row['output'] in terminal['outputs'],"actual target link witness")
        required_archives=archive_pins if row['role']!='codec' else [archive_pins[0],archive_pins[2]]
        require(all(pin in before['inputs'] for pin in required_archives),"test executable/DLL uses SAME actual required production core/Windows/SQLite archives")
        require(all(o['object'] in before['inputs'] for o in row['objects']),"all actual target objects linked")
        require(not any(Path(p['path']).name=='register_types.cpp.obj' for p in before['inputs']) or row['role']!='test_bridge',"no shipping registration object in test bridge")
        children[row['role']]=row['output']
    require(type(value['crt']) is list and [Path(p['path']).name for p in value['crt']]==['MSVCP140.dll','MSVCP140_2.dll','MSVCP140_ATOMIC_WAIT.dll','VCRUNTIME140.dll','VCRUNTIME140_1.dll'],"exact five actual CRT module roster")
    for pin in value['crt']: admit_actual_pin(pin)
    return value,children,native_pin(path)


def strict_native_authorization(value, manifest, children, bridge=False):
    keys=['schema','operation','source_root','dependency_root','build_root','proof_parent','evidence_parent','root_runner','root_process',
          'python','qualifier','ctest','test_build','reference_bindings','discovery_commands','children','limits']
    if bridge: keys+=['native_checks','godot','test_project_resources']
    exact_keys(value,keys)
    require(value['schema']==('LocalPlayersBridgeExecutionAuthorization/v1' if bridge else 'LocalPlayersNativeExecutionAuthorization/v1')
            and value['operation']==('bridge-focused' if bridge else 'native-five-ctest'),"closed stage authorization")
    for name in ['source_root','dependency_root','build_root']:
        require(value[name]==manifest[name],"authorization test-build roots")
    for name in ['proof_parent','evidence_parent']:
        p=ordinary(value[name],True); require(str(p)==value[name] and p!=Path(p.anchor),"explicit ordinary native parent")
    require(native_proof_parent_allowed(value['source_root'],value['proof_parent']),"source-relative proof namespace")
    require(value['proof_parent']!=value['evidence_parent'] and not native_path_overlap(value['proof_parent'],value['evidence_parent']),"separate root and evidence parents")
    for key in ['root_runner','python','qualifier','ctest','test_build']:
        admit_actual_pin(value[key])
    require(value['python']==native_pin(sys.executable) and value['qualifier']==native_pin(__file__),"actual reviewed supervisor/Python bytes")
    require(ordinary(value['root_runner']['path'])==ordinary(value['source_root'],True)/'tools/local-players/run.ps1',"actual allocated Root runner")
    require(value['reference_bindings']==manifest['reference_bindings'],"unchanged reference raw roster")
    require(value['children']==children,"only actual compiled eight target outputs")
    exact_keys(value['root_process'],['pid','creation_filetime','executable'])
    actual_int(value['root_process']['pid'],1,0xffffffff,'Root PID'); canonical_u64(value['root_process']['creation_filetime'],True)
    admit_actual_pin(value['root_process']['executable'])
    exact_keys(value['limits'],['startup_seconds','held_seconds','release_close_seconds','actor_exit_seconds','native_case_seconds','overall_seconds'])
    require(value['limits']=={'startup_seconds':45,'held_seconds':120,'release_close_seconds':10,'actor_exit_seconds':10,'native_case_seconds':NATIVE_LIMITS,'overall_seconds':14400},"Root-ratified exact observation bounds")
    if bridge:
        admit_actual_pin(value['native_checks']); admit_actual_pin(value['godot'])
        require(Path(value['godot']['path']).suffix.lower()=='.exe' and not Path(value['godot']['path']).stem.lower().endswith('_console'),"actual nonconsole Godot")
    return value


def expected_ctest_commands(auth):
    source=Path(auth['source_root']); child=auth['children']; python=Path(auth['python']['path']).as_posix()
    # CMake FILEPATH/PATH cache values, PROJECT_SOURCE_DIR and TARGET_FILE
    # operands use its declared forward-slash rendering. This is predeclared
    # expected argv construction, never normalization of actual discovery.
    common=[python,'-I','-B',(source/'tools/local-players/qualify.py').as_posix(),'ctest']
    result={}
    result['local_players_codec']=[Path(child['codec']['path']).as_posix(),'--reference',(source/'tests/persistence/local_players/reference/expected-v1.json').as_posix()]
    for case in ['store','service','windows','crash']:
        command=common+['--case',case,'--executable',Path(child[case]['path']).as_posix(),'--proof-root',Path(auth['proof_parent']).as_posix(),'--execution-authorization',Path(auth['_authorization_path']).as_posix()]
        if case in ['store','crash']: command+=['--suite',case]
        if case in ['windows','crash']: command+=['--crash-actor',Path(child['crash_actor']['path']).as_posix(),'--lock-actor',Path(child['lock_actor']['path']).as_posix()]
        result['local_players_'+case]=command
    return result


def admit_discovery(value, expected):
    require(type(value) is dict and value.get('kind')=='ctestInfo' and type(value.get('tests')) is list,"actual CTest json-v1 discovery")
    rows=[row for row in value['tests'] if type(row.get('name')) is str and row['name'].startswith('local_players_')]
    require(len(rows)==5 and {row['name'] for row in rows}==set(NATIVE_NAMES),"exact five CTest names with no duplicate/extra storage gate")
    for row in rows: require(row.get('command')==expected[row['name']],"exact actual CTest command; no args/EXE substitutions")
    return [{'name':name,'command':expected[name]} for name in NATIVE_NAMES]


CASE_IDS={
    'store':['two_players_revisions','typed_audio_signed_zero','source_identifier_admission','exact_tick_history',
             'creation_cursor_archive','selected_export_receipt','prune_delete_isolation','real_close_reopen_recovery'],
    'service':['same_token_create_retry','foreign_owner_inert','fifo_capacity_copy','atomic_delivery_batch',
               'worker_progress_during_owner_barrier','closed_poll_after_join','management_loss_closed_failures','source_bound_terminal_shapes'],
    'windows':['descriptor_rejection_no_store_effects','physical_ntfs_identity_and_reparse','sentinel_content_and_lease_retirement',
               'mint_move_and_monotone_identity','foreign_owner_no_effects','share_zero_lock_refusal_and_retry',
               'untrusted_source_files_preserved','actual_sqlite_export_and_move_race'],
    'windows_contention':['external_lock_refusal'], 'windows_post_release':['external_lock_retry'],
}


def scalar_string(value,limit=4096):
    require(type(value) is str and 0<len(value.encode('utf-8'))<=limit and '\0' not in value
            and all(not 0xd800<=ord(c)<=0xdfff for c in value),"bounded scalar String")


def admit_event(frame,nonce,pid,service,sequence,sites,counters):
    exact_keys(frame,['type','nonce','pid','event'])
    require(frame['type']=='EVENT' and frame['nonce']==nonce and type(frame['pid']) is int and frame['pid']==pid,"EVENT actor binding")
    e=frame['event']; require(type(e) is dict,"event dictionary")
    shared=['run_nonce','actor_pid','service_ordinal','request_ordinal','event_sequence']
    allocation='category' in e
    exact_keys(e,shared+(['category','ordinal','requested','rounded','reserved_pages','live_pages'] if allocation
                        else ['kind','scope','phase','edge','occurrence','detail']))
    require(e['run_nonce']==nonce and type(e['actor_pid']) is int and e['actor_pid']==pid,"event native actor binding")
    require(actual_int(e['service_ordinal'],1,(1<<63)-1,'event service')==service,"event source service")
    actual_int(e['request_ordinal'],0,(1<<63)-1,'event request')
    require(canonical_u64(e['event_sequence'],True)==sequence,"independent controller sequence")
    if allocation:
        require(e['category'] in ['control','request','terminal','delivery','workspace','export_spool'],"allocation category")
        ordinal=actual_int(e['ordinal'],1,(1<<63)-1,'allocation ordinal')
        requested=actual_int(e['requested'],1,33554432,'allocation bytes')
        rounded=actual_int(e['rounded'],4096,33554432,'allocation page rounding')
        require(rounded==((requested+4095)//4096)*4096,"exact page rounding")
        for name in ['reserved_pages','live_pages']: actual_int(e[name],0,8192,name)
        key=('allocation',service,e['category']); require(ordinal==counters.get(key,0)+1,"allocation attempts cannot be reused/skipped")
        counters[key]=ordinal
        return {'type':'allocation','service_ordinal':service,'category':e['category'],'ordinal':ordinal}
    require(e['kind'] in ['lifecycle','start','create_player','rename_player','list_players','load_player','save_preferences',
                         'begin_practice','observe_practice','end_practice','link_archive','load_practice',
                         'list_practice','export_player','delete_player','prune_practice','start_management','list_recovery','delete_recovery'],"closed operation kind")
    require((e['kind']=='lifecycle') == (e['request_ordinal']==0),"lifecycle/request ordinal domain")
    require(e['scope'] in ['service','qualification_copy','original','export','recovery'] and e['edge'] in ['before','after'],"operation scope/edge")
    phases=['before_open','before_begin','row_write','before_commit','after_commit','rollback','postverify','publish_ack','checkpoint',
            'export_create','export_write','export_flush','export_move','export_verify_target','recovery_copy']
    require(e['phase'] in phases,"operation phase")
    site={'kind':e['kind'],'scope':e['scope'],'phase':e['phase'],'edge':e['edge']}
    require(site in sites,"operation must have predeclared source site")
    ordinal=actual_int(e['occurrence'],1,(1<<63)-1,'operation occurrence')
    key=('operation',service,e['request_ordinal'],e['scope'],e['phase'])
    prior=counters.get(key,{'kind':e['kind'],'occurrence':0,'pending':False})
    require(prior['kind']==e['kind'],"request kind continuity")
    if e['phase']=='after_commit':
        require(e['edge']=='after' and ordinal==prior['occurrence']+1,"after-commit source occurrence")
    elif e['edge']=='before':
        require(not prior['pending'] and ordinal==prior['occurrence']+1,"before cannot overlap/reuse")
        prior['pending']=True
    else:
        require(prior['pending'] and ordinal==prior['occurrence'],"actual after requires matching before")
        prior['pending']=False
    prior['occurrence']=ordinal; counters[key]=prior
    detail=e['detail']; require(type(detail) is dict,"operation detail")
    if e['phase']=='publish_ack':
        exact_keys(detail,['pending','undelivered'])
        for name in detail: actual_int(detail[name],0,32,name)
    elif phases.index(e['phase'])<=8:
        keys=['sqlite_result']+([] if e['phase']=='before_open' else ['autocommit','txn_state'])
        if e['phase']=='postverify': keys+=['verified_rows']
        exact_keys(detail,keys)
        if detail['sqlite_result'] is not None: actual_int(detail['sqlite_result'],0,0x7fffffff,'actual SQLite result')
        if 'autocommit' in detail:
            require(type(detail['autocommit']) is bool,"actual autocommit bool"); actual_int(detail['txn_state'],0,2,'txn state')
        if 'verified_rows' in detail: actual_int(detail['verified_rows'],0,0x7fffffff,'verified rows')
    else:
        keys=['win32_error','requested_bytes','completed_bytes','owned_handle','installed','volume_serial','file_id','chunk_index','role']
        if e['phase']=='recovery_copy': keys+=['io_kind']
        exact_keys(detail,keys)
        for name,limit in [('win32_error',0xffffffff),('requested_bytes',33554432),('completed_bytes',33554432)]:
            if detail[name] is not None: actual_int(detail[name],0,limit,name)
        require(type(detail['owned_handle']) is bool and (detail['installed'] is None or type(detail['installed']) is bool),"IO bool/null tags")
        if detail['volume_serial'] is not None: canonical_u64(detail['volume_serial'])
        require((detail['volume_serial'] is None)==(detail['file_id'] is None),"IO identity pair")
        if detail['file_id'] is not None: require(type(detail['file_id']) is str and re.fullmatch('[0-9a-f]{32}',detail['file_id']),"file ID")
        actual_int(detail['chunk_index'],0,0xffffffff,'chunk index')
        require(detail['role'] in ['target','temp','main','wal','shm','journal'],"IO role")
        if e['phase']=='recovery_copy': require(detail['io_kind'] in ['read','write'],"IO kind")
    return {'type':'operation','service_ordinal':service,'request_ordinal':e['request_ordinal'],**site,'occurrence':ordinal}


def owned_snapshot(root):
    """Actual no-follow finite files. No SQLite opens, WAL repair or cleanup."""
    root=ordinary(root,True); rows=[]; total=0
    def visit(directory):
        nonlocal total
        for entry in sorted(os.scandir(directory),key=lambda x:x.name):
            observed=os.stat(entry.path,follow_symlinks=False)
            require(not stat.S_ISLNK(observed.st_mode) and not getattr(observed,'st_file_attributes',0)&0x400,"snapshot nonreparse")
            if stat.S_ISDIR(observed.st_mode): visit(Path(entry.path))
            else:
                require(stat.S_ISREG(observed.st_mode) and observed.st_nlink==1,"snapshot ordinary single-link")
                pin=native_pin(entry.path); total+=pin['bytes']
                require(len(rows)<4096 and total<=512*1024*1024,"bounded retained-root snapshot")
                rows.append({'path':Path(entry.path).relative_to(root).as_posix(),'bytes':pin['bytes'],'sha256':pin['sha256']})
    visit(root); return rows


def check_logs(result,allow_stdout=True):
    stderr=ordinary(result['stderr']['path']).read_bytes()
    require(not stderr.strip(),"actual child stderr must be empty")
    stdout=ordinary(result['stdout']['path']).read_bytes()
    require(len(stdout)<=64*1024*1024,"bounded retained stdout")
    if not allow_stdout: require(not stdout.strip(),"unexpected child stdout")
    require(not re.search(rb'(?:SCRIPT ERROR|ERROR:|ObjectDB instances? (?:was |were )?leaked|RID allocations? leaked|resources? (?:is |are )?still in use)',stdout+stderr,re.I),"actual runtime errors/leaks")
    return stdout


def child_arguments(context,descriptor,plan,suite=None):
    result=[]
    for name,pin in [('context',context),('descriptor',descriptor),('plan',plan)]:
        result+=['--'+name,pin['path'],'--'+name+'-sha256',pin['sha256']]
    if suite is not None: result+=['--suite',suite]
    return result


def prepare_case_root(api,auth,evidence,case_id):
    require(case_id in ['store','service','windows-standalone','windows-lock','bridge',*CRASH_SCENARIO_IDS],"fixed source-owned case-parent derivation")
    case_parent=fresh_evidence(auth['proof_parent'],'case-'+case_id)
    preparation={'schema':'LocalPlayersNativePreparationAuthorization/v1','operation':'prepare-isolated-test-root',
        'source_root':auth['source_root'],'proof_parent':str(case_parent),'evidence_parent':str(evidence),
        'supervisor_sha256':native_pin(__file__)['sha256'],'python_sha256':native_pin(sys.executable)['sha256']}
    pin=write_new(evidence/'root-authorization.json',json_bytes(preparation))
    # This explicit nested operation inherits outer actual authorization and is
    # admitted by the SAME native preparer; it is not a subprocess/DB operation.
    prepared=prepare_native_test_root(pin['path'],pin['sha256'])
    descriptor=prepared['descriptor']; admit_actual_pin(descriptor)
    value,_=load_json(descriptor['path'],descriptor['sha256'])
    require(value['parent']==str(case_parent) and case_parent.parent==Path(auth['proof_parent']),"fixed fresh child of authorized proof namespace")
    return {'authorization':pin,'preparation':native_pin(Path(descriptor['path']).parent/'preparation.json'),'descriptor':descriptor,'value':value}


def driver_context(api,auth,role,executable,descriptor,plan,evidence):
    parent=api.process(os.getpid())
    value={'schema':'LocalPlayersNativeTestContext/v1','role':role,'source_root':auth['source_root'],
        'proof_parent':load_json(descriptor['path'],descriptor['sha256'])[0]['parent'],'parent_pid':parent['pid'],'parent_creation_filetime':parent['creation_filetime'],
        'actor_sha256':executable['sha256'],'capability_sha256':descriptor['sha256'],'plan_sha256':plan['sha256']}
    return write_new(evidence/'context.json',json_bytes(value))


def run_driver(api,auth,case,capability,evidence,plan_value=None,ordinal=1):
    suite=case if case in ['store','crash'] else None
    role=case if not case.startswith('windows_') else 'windows'
    plan_value=plan_value or {'schema':'LocalPlayersNativeTestPlan/v1','nonce':capability['value']['nonce'],
        'first_service_ordinal':ordinal,'maximum_actual_events':16384,'suite':case,'cases':CASE_IDS[case]}
    plan=write_new(evidence/'plan.json',json_bytes(plan_value)); executable=auth['children'][role]
    context=driver_context(api,auth,role,executable,capability['descriptor'],plan,evidence)
    inputs=RetainedFiles(api)
    try:
        for row in [context,plan,capability['descriptor']]: inputs.add(row)
        child=ObservedChild(api,executable,child_arguments(context,capability['descriptor'],plan,suite),auth['build_root'],evidence,'driver')
        observed=child.finish(NATIVE_LIMITS[role]); stdout=check_logs(observed)
        if role in ['store','service']:
            match=re.fullmatch(rb'LocalPlayers focused '+role.encode()+rb' checks=([1-9][0-9]*) actual_events=([1-9][0-9]*) PASS\r?\n?',stdout)
            require(match is not None,"actual focused native result, no unavailable substitute")
            result={'checks':int(match[1]),'actual_events':int(match[2]),'cases':CASE_IDS[role],
                    'scope':'Source-bound focused driver asserts actual worker joins; no all-handle or full219 claim.'}
        elif role=='windows':
            result=strict_json_bytes(stdout,1024*1024)
            admit_windows_result(result,case,context,capability['descriptor'],plan)
        else:
            result=admit_crash_stage_stdout(stdout,plan_value['cases'][0],child.pid,capability['descriptor'],plan)
        inputs.recheck()
        return {'context':context,'plan':plan,'process':observed,'observed_result':result}
    finally:
        inputs.close()


def admit_windows_result(value,case,context,descriptor,plan):
    base=['schema','passed','context_sha256','descriptor_sha256','plan_sha256','checks']
    suffix={'windows':['actual_events','cases','export_move_error','terminal_witnesses','two_process_contention'],
            'windows_contention':['open_win32_error','start_terminal_json','service_quiescent'],
            'windows_post_release':['start_terminal_json','list_terminal_json','worker_joined']}[case]
    exact_keys(value,base+suffix)
    schema={'windows':'LocalPlayersWindowsChecks/v1','windows_contention':'LocalPlayersWindowsContentionChecks/v1',
            'windows_post_release':'LocalPlayersWindowsPostReleaseChecks/v1'}[case]
    require(value['schema']==schema and value['passed'] is True and value['context_sha256']==context['sha256']
            and value['descriptor_sha256']==descriptor['sha256'] and value['plan_sha256']==plan['sha256'],"actual Windows receipt pins")
    # Polling assertions have no fixed iteration ceiling; Writer emits signed INT64.
    check_count_max=(1<<63)-1
    actual_int(value['checks'],1,check_count_max,'actual Windows checks')
    if case=='windows':
        actual_int(value['actual_events'],1,524288,'actual Windows events')
        require(type(value['cases']) is list and [r['id'] for r in value['cases']]==CASE_IDS[case]
                and value['two_process_contention'] is False,"standalone Windows scope/roster")
        for row in value['cases']:
            exact_keys(row,['id','checks','actual_events']); actual_int(row['checks'],1,check_count_max,'case checks'); actual_int(row['actual_events'],0,524288,'case events')
        actual_int(value['export_move_error'],1,0xffffffff,'actual move-race error')
        for row in value['terminal_witnesses']:
            exact_keys(row,['case_id','terminal_json']); require(row['case_id'] in CASE_IDS[case],"terminal case"); scalar_string(row['terminal_json'],2*1024*1024)
    elif case=='windows_contention':
        require(type(value['open_win32_error']) is int and value['open_win32_error']==32 and value['service_quiescent'] is True,"actual share-zero refusal/quiescence")
    else: require(value['worker_joined'] is True,"actual post-release worker join")
    for name in ['start_terminal_json','list_terminal_json']:
        if name in value: strict_json_bytes(value[name].encode('utf-8'),2*1024*1024)


def run_lock_span(api,auth,capability,evidence):
    target=Path(capability['value']['root'])/'players.lock'
    handle,identity=api.lease(target,access=0x80000000|0x40000000,creation=1,share=3)
    api.close(handle) # Actor opens the exact already-created object; no fallback.
    nonce=capability['value']['nonce']; pipes=ActorPipes(api,nonce,evidence)
    plan_value={'schema':'LocalPlayersLockActorPlan/v1','nonce':nonce,'service_ordinal':1,'action_ordinal':1,
                'target':'ownership_lock',**identity}
    plan=write_new(evidence/'actor-plan.json',json_bytes(plan_value)); parent=api.process(os.getpid()); executable=auth['children']['lock_actor']
    context=write_new(evidence/'actor-context.json',json_bytes({'schema':'LocalPlayersLockActorContext/v2','role':'lock_holder',
        'source_root':auth['source_root'],'proof_parent':capability['value']['parent'],'parent_pid':parent['pid'],
        'parent_creation_filetime':parent['creation_filetime'],'actor_sha256':executable['sha256'],
        'capability_sha256':capability['descriptor']['sha256'],'plan_sha256':plan['sha256'],
        'stdin_pipe':pipes.names[0],'stdout_pipe':pipes.names[1]}))
    child=None; finished=False; inputs=RetainedFiles(api)
    try:
        for row in [context,plan,capability['descriptor']]: inputs.add(row)
        child=ObservedChild(api,executable,child_arguments(context,capability['descriptor'],plan),auth['build_root'],evidence,'lock-actor')
        pipes.connect(child); ready=pipes.read_frame(child)
        admit_ready(ready,nonce,child.pid,'lock_holder',capability['descriptor']['sha256'],plan['sha256'])
        held=pipes.read_frame(child); exact_keys(held,['type','nonce','pid','action_ordinal','volume_serial','file_id','held'])
        require(held=={'type':'HELD','nonce':nonce,'pid':child.pid,'action_ordinal':1,**identity,'held':True}
                and type(held['pid']) is int and type(held['action_ordinal']) is int,"actual held target identity")
        during=fresh_evidence(evidence,'contention')
        refusal=run_driver(api,auth,'windows_contention',capability,during,ordinal=2)
        child.live(); inputs.recheck(); pipes.release(child); closed=pipes.read_frame(child); admit_closed(closed,nonce,child.pid)
        actor=child.finish(45+120+20); finished=True; check_logs(actor,False)
        pipes.close()
        after=run_driver(api,auth,'windows_post_release',capability,fresh_evidence(evidence,'post-release'),ordinal=3)
        inputs.recheck()
        return {'context':context,'plan':plan,'ready':ready,'held':held,'closed':closed,'actual_process':actor,
                'raw_frames':native_pin(evidence/'actor.frames.ndjson'),'contended':refusal,'post_release':after,
                'transport_closed_after_closed_frame':True}
    finally:
        if child is not None and not finished and child.process_handle is not None:
            # Retained failure may terminate for safety. Never report a release,
            # graceful close or join from the watchdog's observed process exit.
            api.ok(api.k.TerminateJobObject(child.job,125),'failed lock span termination')
            try: child.finish(0)
            except ValueError: pass
        inputs.close()
        pipes.close()



def raw_authorization(path,expected_sha,test_build,test_build_sha,bridge=False):
    manifest,children,manifest_pin=admit_test_build(test_build,test_build_sha)
    auth,_=load_json(path,expected_sha)
    strict_native_authorization(auth,manifest,children,bridge)
    require(auth['test_build']==manifest_pin,"actual authorized test build")
    auth['_authorization_path']=str(ordinary(path))
    require(auth['discovery_commands']==expected_ctest_commands(auth),"explicit exact five authorized commands")
    return auth,manifest,manifest_pin,native_pin(path)


def hold_stage_inputs(api,auth,manifest,authorization_pin):
    leases=RetainedFiles(api); seen=set()
    rows=[authorization_pin,auth['test_build'],auth['root_runner'],auth['python'],auth['qualifier'],auth['ctest'],
          manifest['source_identity'],manifest['configuration_cache'],manifest['production_build'],manifest['compile_database'],manifest['ctest_source'],
          *auth['children'].values(),*manifest['crt']]
    rows+=[native_pin(Path(auth['source_root'])/p['path']) for p in manifest['test_source_bindings']]
    identity,_=load_json(manifest['source_identity']['path'],manifest['source_identity']['sha256'])
    rows+=[native_pin(Path(auth['source_root'])/p['path']) for p in identity['source_bindings']]
    if 'godot' in auth: rows+=[auth['godot'],auth['native_checks']]
    for pin in rows:
        if pin['path'] not in seen: leases.add(pin); seen.add(pin['path'])
    return leases


def admit_ancestry_session(api,auth,authorization_pin):
    # This fixed sibling cannot be supplied independently or silently replaced.
    session_path=Path(auth['_authorization_path']+'.session.json')
    session,_=load_json(session_path)
    exact_keys(session,['schema','authorization','test_build','root_process','native_supervisor','ctest_process','evidence_root'])
    require(session['schema']=='LocalPlayersCTestSession/v1' and session['authorization']==authorization_pin
            and session['test_build']==auth['test_build'] and session['root_process']==auth['root_process'],"immutable actual CTest session binding")
    ordinary(session['evidence_root'],True)
    require(Path(session['evidence_root']).parent==Path(auth['evidence_parent']),"Root-owned evidence session")
    require(session['native_supervisor']['executable']==auth['python'] and session['ctest_process']['executable']==auth['ctest'],"actual supervisor/CTest tools")
    chain=api.ancestry(os.getpid(),[session['ctest_process'],session['native_supervisor'],session['root_process']])
    return session,native_pin(session_path),chain


def ctest_case(args):
    require(args.case in ['store','service','windows','crash'],"closed wrapper case")
    authorization_pin=native_pin(args.execution_authorization)
    auth_value,_=load_json(args.execution_authorization,authorization_pin['sha256'])
    auth,manifest,manifest_pin,authorization_pin=raw_authorization(args.execution_authorization,authorization_pin['sha256'],
        auth_value['test_build']['path'],auth_value['test_build']['sha256'])
    require(str(ordinary(args.proof_root,True))==auth['proof_parent'] and native_pin(args.executable)==auth['children'][args.case],"fixed actual CTest executable/proof context")
    require(args.suite== (args.case if args.case in ['store','crash'] else None),"exact suite selector")
    if args.case in ['windows','crash']:
        require(native_pin(args.crash_actor)==auth['children']['crash_actor'] and native_pin(args.lock_actor)==auth['children']['lock_actor'],"fixed actor outputs")
    else: require(args.crash_actor is None and args.lock_actor is None,"no actor overrides")
    api=NativeApi(); session,session_pin,chain=admit_ancestry_session(api,auth,authorization_pin)
    evidence=Path(session['evidence_root'])/('case-'+args.case)
    evidence.mkdir(exist_ok=False); ordinary(evidence,True)
    result={'schema':'LocalPlayersCTestCase/v1','case':args.case,'passed':False,'authorization':authorization_pin,
        'test_build':manifest_pin,'source_inputs':manifest['test_source_bindings'],'root_capabilities':[],
        'invocations':[],'driver_results':[],'actors':[],'coverage':{},'remaining_acceptance':NATIVE_REMAINING}
    leases=None
    try:
        leases=hold_stage_inputs(api,auth,manifest,authorization_pin); leases.add(session_pin)
        write_new(evidence/'ancestry.json',json_bytes({'wrapper':api.process(os.getpid()),'session':session_pin,'actual_ancestors':chain}))
        if args.case in ['store','service']:
            cap=prepare_case_root(api,auth,evidence,args.case); result['root_capabilities'].append(cap)
            driver=run_driver(api,auth,args.case,cap,fresh_evidence(evidence,'run'))
            result['invocations'].append(driver); result['driver_results'].append(driver['observed_result'])
            result['coverage']={'fixed_cases':CASE_IDS[args.case],'checks':driver['observed_result']['checks'],'actual_events':driver['observed_result']['actual_events']}
        elif args.case=='windows':
            cap=prepare_case_root(api,auth,fresh_evidence(evidence,'standalone-root'),'windows-standalone'); result['root_capabilities'].append(cap)
            driver=run_driver(api,auth,'windows',cap,fresh_evidence(evidence,'standalone'))
            result['invocations'].append(driver); result['driver_results'].append(driver['observed_result'])
            lock_cap=prepare_case_root(api,auth,fresh_evidence(evidence,'lock-root'),'windows-lock'); result['root_capabilities'].append(lock_cap)
            span=run_lock_span(api,auth,lock_cap,fresh_evidence(evidence,'lock-span')); result['actors'].append(span)
            result['coverage']={'fixed_cases':CASE_IDS['windows'],'modes':['standalone','external_lock_refusal','external_lock_retry'],
                'checks':driver['observed_result']['checks']+span['contended']['observed_result']['checks']+span['post_release']['observed_result']['checks'],
                'actual_events':driver['observed_result']['actual_events']}
        else:
            crash=run_crash_table(api,auth,evidence)
            result['root_capabilities']=crash['root_capabilities']; result['invocations']=crash['invocations']
            result['driver_results']=crash['driver_results']; result['actors']=crash['actors']; result['coverage']=crash['coverage']
        leases.recheck(); api.ancestry(os.getpid(),chain)
        leases.close(); leases=None
        result['passed']=True
    except BaseException as error:
        result['coverage']['failure']=type(error).__name__+': '+str(error)
        raise
    finally:
        if leases is not None:
            try: leases.close()
            except BaseException as error:
                result['passed']=False; result['coverage']['lease_retirement_failure']=str(error)
        write_new(evidence/'case-receipt.json',json_bytes(result))
    require(result['passed'],"case was not safely retired")
    return {'case_receipt':native_pin(evidence/'case-receipt.json'),'scope':'Actual focused gate only; see explicit remaining_acceptance.'}


def ctest_junit(path,commands):
    import xml.etree.ElementTree as ET
    raw=ordinary(path).read_bytes(); require(len(raw)<=64*1024*1024 and b'<!DOCTYPE' not in raw.upper() and b'<!ENTITY' not in raw.upper(),"bounded nonentity CTest XML")
    root=ET.fromstring(raw); rows=list(root.iter('testcase'))
    require(len(rows)==5 and {r.get('name') for r in rows}==set(NATIVE_NAMES),"all five actual CTest results, no skipped test substitution")
    results=[]
    for name in NATIVE_NAMES:
        row=next(r for r in rows if r.get('name')==name)
        require(row.get('status')=='run' and not any(row.find(k) is not None for k in ['failure','error','skipped']),"CTest case did not pass")
        elapsed=float(row.get('time','nan')); require(0<=elapsed<=NATIVE_LIMITS[name.removeprefix('local_players_')],"actual bounded per-case elapsed")
        output=row.findtext('system-out',''); require(type(output) is str,"actual CTest stdout")
        results.append({'name':name,'command':commands[name],'elapsed_seconds':elapsed,'stdout':output})
    return results


def native_checks(args):
    auth,manifest,manifest_pin,auth_pin=raw_authorization(args.authorization,args.authorization_sha256,args.test_build,args.test_build_sha256)
    require(native_pin(args.ctest)==auth['ctest'] and auth['ctest']['sha256']==args.ctest_sha256,"pinned actual CTest")
    api=NativeApi(); root_chain=api.ancestry(os.getpid(),[auth['root_process']])
    evidence=fresh_evidence(auth['evidence_parent'],'native-checks'); session_path=Path(auth['_authorization_path']+'.session.json')
    require(not session_path.exists(),"authorization is one-use; prior session remains failure evidence")
    result={'schema':'LocalPlayersNativeChecks/v1','passed':False,'scope':'Actual five focused CTests, isolated Windows capability and process-crash injection; not complete219.',
        'execution_authorization':auth_pin,'test_build':manifest_pin,'source_identity':manifest['source_identity'],
        'discovery':None,'ctest_process':None,'cases':[],'actors':[],'coverage':{},'remaining_acceptance':NATIVE_REMAINING}
    leases=None
    try:
        leases=hold_stage_inputs(api,auth,manifest,auth_pin)
        result['coverage']['module_crt']=module_crt_closure(manifest)
        commands=expected_ctest_commands(auth)
        discovery=ObservedChild(api,auth['ctest'],['--test-dir',auth['build_root'],'--show-only=json-v1'],auth['build_root'],evidence,'ctest-discovery')
        discovery_process=discovery.finish(120); raw=check_logs(discovery_process)
        value=strict_json_bytes(raw,16*1024*1024)
        rows=admit_discovery(value,commands); result['discovery']={'process':discovery_process,'tests':rows}
        junit=evidence/'ctest-junit.xml'
        argv=['--test-dir',auth['build_root'],'-R','^local_players_(codec|store|service|windows|crash)$','--parallel','1',
            '--no-tests=error','--output-on-failure','--test-output-size-passed','65536','--output-junit',str(junit)]
        def publish_session(child):
            current=api.process(os.getpid()); require(api.ancestry(os.getpid(),root_chain)==root_chain,"Root remains actual parent")
            write_new(session_path,json_bytes({'schema':'LocalPlayersCTestSession/v1','authorization':auth_pin,'test_build':manifest_pin,
                'root_process':auth['root_process'],'native_supervisor':current,'ctest_process':child.observed,'evidence_root':str(evidence)}))
            leases.add(native_pin(session_path))
        ctest=ObservedChild(api,auth['ctest'],argv,auth['build_root'],evidence,'ctest-execute',publish_session)
        result['ctest_process']=ctest.finish(14400); check_logs(result['ctest_process'])
        tests=ctest_junit(junit,commands); result['coverage']['junit']=native_pin(junit)
        for case in ['store','service','windows','crash']:
            path=evidence/('case-'+case)/'case-receipt.json'; row,_=load_json(path)
            exact_keys(row,['schema','case','passed','authorization','test_build','source_inputs','root_capabilities','invocations','driver_results','actors','coverage','remaining_acceptance'])
            require(row['schema']=='LocalPlayersCTestCase/v1' and row['case']==case and row['passed'] is True
                    and row['authorization']==auth_pin and row['test_build']==manifest_pin
                    and row['source_inputs']==manifest['test_source_bindings'] and row['remaining_acceptance']==NATIVE_REMAINING,"actual same-session closed case receipt")
            result['cases'].append({'case':case,'receipt':native_pin(path),'coverage':row['coverage']}); result['actors']+=row['actors']
        codec=next(r for r in tests if r['name']=='local_players_codec')
        codec_match=re.search(r'(?m)^LOCAL_PLAYERS_CODEC_PASS checks=([1-9][0-9]*) applicable_reference_rows=95 deferred_reference_rows=19 original_reference_rows=114 scope=pure_codec_records_no_storage_runtime\r?$',codec['stdout'])
        require(codec_match is not None and codec['stdout'].count('LOCAL_PLAYERS_CODEC_PASS ')==1,"actual codec authored applicable/deferred coverage")
        result['cases'].insert(0,{'case':'codec','checks':int(codec_match[1]),'applicable_reference_rows':95,'deferred_reference_rows':19,'ctest_junit':native_pin(junit),'observed_stdout':codec['stdout'],
            'reference':next(r for r in manifest['reference_bindings'] if r['path']=='tests/persistence/local_players/reference/expected-v1.json'),
            'scope':'Actual direct CTest native codec executable; 114 reference rows are not 114 runtime categories.'})
        require(result['cases'][-1]['coverage']['scenario_ids']==CRASH_SCENARIO_IDS,"all nineteen source-fixed crash recipes mandatory")
        result['coverage'].update({'five_actual_tests':tests,'windows_modes':['standalone','external_lock_refusal','external_lock_retry'],
            'crash_scenarios':CRASH_SCENARIO_IDS,'counts_are_observed_driver_checks':True,'ancestry':root_chain})
        leases.recheck(); api.ancestry(os.getpid(),root_chain); leases.close(); leases=None
        result['passed']=True
    except BaseException as error:
        result['coverage']['failure']=type(error).__name__+': '+str(error); raise
    finally:
        if leases is not None:
            try: leases.close()
            except BaseException as error:
                result['passed']=False; result['coverage']['lease_retirement_failure']=str(error)
        write_new(evidence/'native-checks-receipt.json',json_bytes(result))
    require(result['passed'],"native aggregate retirement failed")
    return {'native_checks':native_pin(evidence/'native-checks-receipt.json'),'passed':True,'remaining_acceptance':NATIVE_REMAINING}


def pe_imports(path,is_dll):
    raw=ordinary(path).read_bytes(); require(len(raw)<=512*1024*1024 and raw[:2]==b'MZ' and len(raw)>=64,"bounded actual PE")
    nt=struct.unpack_from('<I',raw,60)[0]
    require(nt+264<=len(raw) and raw[nt:nt+4]==b'PE\0\0',"PE signature/header")
    machine,sections=struct.unpack_from('<HH',raw,nt+4); optional=struct.unpack_from('<H',raw,nt+20)[0]
    characteristics=struct.unpack_from('<H',raw,nt+22)[0]
    require(machine==0x8664 and bool(characteristics&0x2000)==is_dll and struct.unpack_from('<H',raw,nt+24)[0]==0x20b,"AMD64 actual EXE/DLL kind")
    require(1<=sections<=96 and optional>=240,"PE64 bounded sections")
    table=nt+24+optional; require(table+40*sections<=len(raw),"complete PE sections")
    spans=[]
    for i in range(sections):
        size,va,rawsize,offset=struct.unpack_from('<IIII',raw,table+40*i+8)
        require(offset+rawsize<=len(raw),"PE section file bounds"); spans.append((va,max(size,rawsize),offset,rawsize))
    def at(rva,count):
        found=[off+rva-va for va,size,off,rawsize in spans if va<=rva and rva+count<=va+rawsize]
        require(len(found)==1 and found[0]+count<=len(raw),"unique mapped PE bytes"); return found[0]
    def name(rva):
        pos=at(rva,1); end=raw.find(b'\0',pos,min(pos+513,len(raw))); require(end>pos,"bounded PE name")
        return raw[pos:end].decode('ascii','strict')
    require(struct.unpack_from('<I',raw,nt+24+108)[0]>=2,"PE import directory exists")
    directory_count=struct.unpack_from('<I',raw,nt+24+108)[0]
    require(directory_count<=16,"closed PE directory count")
    if directory_count>13:
        require(struct.unpack_from('<II',raw,nt+24+112+13*8)==(0,0),"source policy forbids unbound delayed imports")
    rva,size=struct.unpack_from('<II',raw,nt+24+112+8)
    require(rva and 20<=size<=1024*1024,"actual imports")
    result=[]; pos=at(rva,size); ended=False
    for i in range(size//20):
        row=struct.unpack_from('<IIIII',raw,pos+i*20)
        if not any(row): ended=True;break
        dll=name(row[3]); require(dll.lower() not in [n.lower() for n in result],"unique import DLL")
        result.append(dll)
    require(ended and result,"complete import descriptor roster")
    return result


def module_crt_closure(manifest):
    crt={Path(p['path']).name.casefold():p for p in manifest['crt']}
    system={'kernel32.dll','advapi32.dll','bcrypt.dll','shell32.dll','ole32.dll','user32.dll','ntdll.dll',
            'ucrtbase.dll','msvcrt.dll','ws2_32.dll','winmm.dll','version.dll','comdlg32.dll','gdi32.dll','shlwapi.dll','setupapi.dll'}
    rows=[]
    for target in manifest['targets']:
        imports=pe_imports(target['output']['path'],target['role']=='test_bridge')
        require(all(n.casefold() in crt or n.casefold() in system or n.casefold().startswith('api-ms-win-') or n.casefold().startswith('ext-ms-win-') for n in imports),"test PE imports require actual CRT or declared Windows system dependency")
        require(not any('sqlite' in n.casefold() or 'flight_local_players_bridge' in n.casefold() for n in imports),"same static SQLite and isolated test bridge")
        rows.append({'role':target['role'],'module':target['output'],'imports':imports})
    for pin in manifest['crt']: pe_imports(pin['path'],True)
    return {'modules':rows,'crt':manifest['crt'],'scope':'Actual PE64 import graph/system classification and raw CRT binding; no runtime claim.'}


BRIDGE_HOST='''# Original MIT. Root-only focused host; no production storage path.
extends SceneTree
var checks: RefCounted
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var ready := FileAccess.open("res://loaded-ready.json", FileAccess.WRITE)
    if ready == null:
        push_error("BRIDGE_READY_WRITE_FAILED")
        quit(1)
        return
    ready.store_string(JSON.stringify({"pid": OS.get_process_id()}, "", false, true))
    ready.close()
    var deadline := Time.get_ticks_msec() + 10000
    while not FileAccess.file_exists("res://module-observed.ack"):
        if Time.get_ticks_msec() >= deadline:
            push_error("BRIDGE_MODULE_OBSERVATION_MISSING")
            quit(1)
            return
        await process_frame
    var host := Node.new()
    root.add_child(host)
    checks = load("res://bridge_checks.gd").new()
    var observed: Variant = await checks.run(host)
    var output := FileAccess.open("res://bridge-observed-result.json", FileAccess.WRITE)
    if output == null:
        push_error("BRIDGE_RESULT_WRITE_FAILED")
        return
    output.store_string(JSON.stringify(observed, "  ", false, true))
    output.close()
    # A failed join retains checks and its wrapper. Root's watchdog may terminate
    # the process but cannot turn that into a positive service join.
    if typeof(observed) != TYPE_DICTIONARY or observed.get("evidence", {}).get("joined", false) != true:
        push_error("BRIDGE_JOIN_UNPROVEN_RETAINED")
        return
    host.queue_free()
    await process_frame
    quit(0 if observed.get("passed", false) else 1)
'''


def bridge_result(value):
    exact_keys(value,['passed','checks','failures','evidence','scope'])
    require(value['passed'] is True and actual_int(value['checks'],1,1000000,'actual focused ClassDB checks')
            and type(value['failures']) is list and not value['failures'],"actual focused result")
    exact_keys(value['evidence'],['joined','boundary','capability','journey'])
    require(value['evidence']=={'joined':True,'boundary':'same-production-LocalPlayersBoundary',
                'capability':'Root-bound-isolated-test','journey':False}
            and value['scope']=='focused-ClassDB-parity-not-complete-219',"focused same-boundary/actual join limits")


def bridge_checks(args):
    auth,manifest,manifest_pin,auth_pin=raw_authorization(args.authorization,args.authorization_sha256,args.test_build,args.test_build_sha256,True)
    require(native_pin(args.godot)==auth['godot'] and auth['godot']['sha256']==args.godot_sha256,"actual pinned nonconsole Godot")
    require(native_pin(args.native_checks)==auth['native_checks'] and auth['native_checks']['sha256']==args.native_checks_sha256,"exact prior native evidence")
    native,_=load_json(args.native_checks,args.native_checks_sha256)
    require(native['schema']=='LocalPlayersNativeChecks/v1' and native['passed'] is True and native['test_build']==manifest_pin
            and [r['case'] for r in native['cases']]==list(NATIVE_LIMITS),"actual SAME test build native five gates")
    api=NativeApi(); ancestry=api.ancestry(os.getpid(),[auth['root_process']])
    evidence=fresh_evidence(auth['evidence_parent'],'bridge-checks')
    result={'schema':'LocalPlayersBridgeChecks/v1','passed':False,'scope':'Actual focused isolated SAME-boundary ClassDB route; not full219/220 journey or shipping delivery.',
        'execution_authorization':auth_pin,'test_build':manifest_pin,'native_checks':auth['native_checks'],'capability':None,'context':None,
        'resources':[],'import_process':None,'runtime_process':None,'observed_result':None,'loaded_modules':[],
        'remaining_acceptance':NATIVE_REMAINING}
    leases=None; child=None
    try:
        leases=hold_stage_inputs(api,auth,manifest,auth_pin); module_crt_closure(manifest)
        cap=prepare_case_root(api,auth,fresh_evidence(evidence,'root'),'bridge'); result['capability']=cap
        project=evidence/'project'; project.mkdir(exist_ok=False); binary=project/'bin'; binary.mkdir(exist_ok=False)
        source=Path(auth['source_root']); names=['tests/persistence/local_players/bridge_checks.gd','tests/persistence/local_players/local_players_test.gdextension']
        require([p['path'] for p in auth['test_project_resources']]==names,"exact two source-bound test resources")
        for row in auth['test_project_resources']:
            require(row in manifest['test_source_bindings'],"actual compiled source/reference authority for test resource")
            raw=ordinary(source/row['path']).read_bytes(); require(len(raw)==row['bytes'] and digest(raw)==row['sha256'],"raw resource source pin")
            result['resources'].append(write_new(project/Path(row['path']).name,raw))
        for pin in [auth['children']['test_bridge'],*manifest['crt']]:
            name='flight_local_players_test_bridge.dll' if pin==auth['children']['test_bridge'] else Path(pin['path']).name
            result['resources'].append(write_new(binary/name,ordinary(pin['path']).read_bytes()))
        identity,_=load_json(manifest['source_identity']['path'],manifest['source_identity']['sha256'])
        identity_resource=Path(manifest['source_identity']['path']).parent/identity['generated_resource']['path']
        result['resources'].append(write_new(project/'local-players-identity.gd',ordinary(identity_resource).read_bytes()))
        result['resources'].append(write_new(project/'project.godot',b'config_version=5\n\n[application]\nconfig/name="Root-bound LocalPlayers Focused ClassDB"\n\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n'))
        result['resources'].append(write_new(project/'bridge_host.gd',BRIDGE_HOST.encode('utf-8')))
        imported=ObservedChild(api,auth['godot'],['--headless','--audio-driver','Dummy','--path',str(project),'--editor','--import','--frame-delay','1000'],str(project),evidence,'bridge-import',profile=fresh_evidence(evidence,'import-profile'))
        result['import_process']=imported.finish(120); check_logs(result['import_process'])
        parent=api.process(os.getpid())
        context={'schema':'LocalPlayersGodotTestContext/v1','role':'bridge','source_root':auth['source_root'],'proof_parent':cap['value']['parent'],
            'parent_pid':str(parent['pid']),'parent_creation_100ns':parent['creation_filetime'],
            'godot_executable_sha256':auth['godot']['sha256'],'test_bridge_sha256':auth['children']['test_bridge']['sha256'],
            'descriptor_sha256':cap['descriptor']['sha256']}
        result['context']=write_new(evidence/'godot-context.json',json_bytes(context)); leases.add(result['context']); leases.add(cap['descriptor'])
        argv=['--headless','--audio-driver','Dummy','--path',str(project),'--script','res://bridge_host.gd','--']
        for name,pin in [('context',result['context']),('descriptor',cap['descriptor'])]:
            argv+=['--local-players-test-'+name,pin['path'],'--local-players-test-'+name+'-sha256',pin['sha256']]
        child=ObservedChild(api,auth['godot'],argv,str(project),evidence,'bridge-runtime',profile=fresh_evidence(evidence,'runtime-profile'))
        deadline=time.monotonic()+10
        while not (project/'loaded-ready.json').exists():
            child.live(); require(time.monotonic()<deadline,"actual bridge load readiness deadline"); time.sleep(.01)
        ready,_=load_json(project/'loaded-ready.json'); exact_keys(ready,['pid']); require(type(ready['pid']) is int and ready['pid']==child.pid,"actual host readiness PID")
        modules=api.modules(child.pid)
        wanted=project/'bin/flight_local_players_test_bridge.dll'
        actual=[p for p in modules if Path(p['path']).name.casefold()=='flight_local_players_test_bridge.dll']
        require(len(actual)==1 and ordinary(actual[0]['path'])==ordinary(wanted)
                and actual[0]['sha256']==auth['children']['test_bridge']['sha256'],"actual SAME test DLL loaded from isolated package")
        require(native_pin(actual[0]['path'])==actual[0],"actual selected test DLL remains strict ordinary single-link input")
        require(not any(Path(p['path']).name.casefold()=='flight_local_players_bridge.dll' for p in modules),"shipping storage registration absent from focused test process")
        for crt in manifest['crt']:
            loaded=[p for p in modules if Path(p['path']).name.casefold()==Path(crt['path']).name.casefold()]
            if loaded:
                require(len(loaded)==1 and loaded[0]['sha256']==crt['sha256'] and loaded[0]['bytes']==crt['bytes'],"actual loaded CRT exact pin")
                require(native_pin(loaded[0]['path'])==loaded[0],"actual selected CRT remains strict ordinary single-link input")
        result['loaded_modules']=modules
        write_new(project/'module-observed.ack',b'ROOT_ACTUAL_MODULE_ADMITTED\n')
        result['runtime_process']=child.finish(600); child=None; check_logs(result['runtime_process'])
        observed_path=project/'bridge-observed-result.json'; result['observed_result']=native_pin(observed_path)
        observed,_=load_json(observed_path); bridge_result(observed)
        for pin in result['resources']: require(native_pin(pin['path'])==pin,"test resources/binaries unchanged")
        leases.recheck(); api.ancestry(os.getpid(),ancestry); leases.close(); leases=None
        result['passed']=True
    except BaseException as error:
        result['remaining_acceptance']=NATIVE_REMAINING+['FAILED: '+type(error).__name__+': '+str(error)]; raise
    finally:
        if child is not None and child.process_handle is not None:
            api.ok(api.k.TerminateJobObject(child.job,125),'failed bridge actual termination')
            try: child.finish(0)
            except ValueError: pass
        if leases is not None:
            try: leases.close()
            except BaseException as error:
                result['passed']=False; result['remaining_acceptance']+=['input lease retirement failed: '+str(error)]
        write_new(evidence/'bridge-checks-receipt.json',json_bytes(result))
    require(result['passed'],"bridge safe retirement failed")
    return {'bridge_checks':native_pin(evidence/'bridge-checks-receipt.json'),'passed':True,'remaining_acceptance':NATIVE_REMAINING}


# Frozen independent pre-output crash inputs, embedded in the allocated qualifier.
CRASH_RECIPE_SOURCE_SHA = 'cedbf3be21dcf548263c190abe5881c677bff8dfb0ecac9a1068a8926a93ba8c'
CRASH_NATIVE_SOURCE_SHA = '205ceba71620784655bad5b0355d955985c990fc5b5dc5257be12bfd35dd76ed'
CRASH_ACTOR_SOURCE_SHA = '5e922567ac587916151a5f4b21821ea782c582599ef21adfa6e61a23e2d70e06'
CRASH_RECIPES = json.loads('{"schema":"PrivateLocalPlayersCrashMachineRecipes/v1","status":"SOURCE_ONLY_PREOUTPUT_REVIEW_REQUIRED","template_binding":"ONLY nonce.root_binding may become the authenticated fresh root nonce; all other plan values literal. Root records actual actor-context/raw hashes and actual spawned-parent/child identities independently.","bindings":{"sentinel_bytes":"raw bound canonical root sentinel length","original_main_first_chunk_bytes":"min(65536, Root-preactor observed original main length)","expected_export_bytes":2778},"closed_fixture_ids":{"alice":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bob":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","one":"cccccccccccccccccccccccccccccccc","two":"dddddddddddddddddddddddddddddddd"},"recipes":[{"id":"pre_begin","fixture":"pair","driver_stages":["pre_begin_prepare","pre_begin_reopen"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"},{"kind":"rename_player","scope":"original","phase":"before_begin","edge":"before"},{"kind":"rename_player","scope":"original","phase":"before_begin","edge":"after"},{"kind":"rename_player","scope":"original","phase":"row_write","edge":"before"},{"kind":"rename_player","scope":"original","phase":"row_write","edge":"after"},{"kind":"rename_player","scope":"original","phase":"before_commit","edge":"before"},{"kind":"rename_player","scope":"original","phase":"before_commit","edge":"after"},{"kind":"rename_player","scope":"original","phase":"after_commit","edge":"after"},{"kind":"rename_player","scope":"original","phase":"rollback","edge":"before"},{"kind":"rename_player","scope":"original","phase":"rollback","edge":"after"},{"kind":"rename_player","scope":"original","phase":"postverify","edge":"before"},{"kind":"rename_player","scope":"original","phase":"postverify","edge":"after"},{"kind":"rename_player","scope":"original","phase":"checkpoint","edge":"before"},{"kind":"rename_player","scope":"original","phase":"checkpoint","edge":"after"},{"kind":"rename_player","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"rename_player","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"},{"kind":"rename_player","player_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","expected_revision":"2","name":"Alice After","utc":"2026-10-03T12:03:00Z"}],"crash_selector":{"request_ordinal":2,"kind":"rename_player","scope":"original","phase":"before_begin","edge":"before","occurrence":1,"service_ordinal":1},"exit_code":86},"required_call_prefix":[],"selected_and_prior_predicates":[{"detail":{"sqlite_result":null,"autocommit":true,"txn_state":0}}]}]},{"id":"before_commit","fixture":"pair","driver_stages":["before_commit_prepare","before_commit_reopen"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"},{"kind":"rename_player","scope":"original","phase":"before_begin","edge":"before"},{"kind":"rename_player","scope":"original","phase":"before_begin","edge":"after"},{"kind":"rename_player","scope":"original","phase":"row_write","edge":"before"},{"kind":"rename_player","scope":"original","phase":"row_write","edge":"after"},{"kind":"rename_player","scope":"original","phase":"before_commit","edge":"before"},{"kind":"rename_player","scope":"original","phase":"before_commit","edge":"after"},{"kind":"rename_player","scope":"original","phase":"after_commit","edge":"after"},{"kind":"rename_player","scope":"original","phase":"rollback","edge":"before"},{"kind":"rename_player","scope":"original","phase":"rollback","edge":"after"},{"kind":"rename_player","scope":"original","phase":"postverify","edge":"before"},{"kind":"rename_player","scope":"original","phase":"postverify","edge":"after"},{"kind":"rename_player","scope":"original","phase":"checkpoint","edge":"before"},{"kind":"rename_player","scope":"original","phase":"checkpoint","edge":"after"},{"kind":"rename_player","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"rename_player","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"},{"kind":"rename_player","player_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","expected_revision":"2","name":"Alice After","utc":"2026-10-03T12:03:00Z"}],"crash_selector":{"request_ordinal":2,"kind":"rename_player","scope":"original","phase":"before_commit","edge":"before","occurrence":1,"service_ordinal":1},"exit_code":86},"required_call_prefix":[],"selected_and_prior_predicates":[{"detail":{"sqlite_result":null,"autocommit":false,"txn_state":2}},{"prior":{"kind":"rename_player","scope":"original","phase":"row_write","edge":"after","sqlite_result":101}}]}]},{"id":"after_commit","fixture":"pair","driver_stages":["after_commit_prepare","after_commit_reopen"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"},{"kind":"rename_player","scope":"original","phase":"before_begin","edge":"before"},{"kind":"rename_player","scope":"original","phase":"before_begin","edge":"after"},{"kind":"rename_player","scope":"original","phase":"row_write","edge":"before"},{"kind":"rename_player","scope":"original","phase":"row_write","edge":"after"},{"kind":"rename_player","scope":"original","phase":"before_commit","edge":"before"},{"kind":"rename_player","scope":"original","phase":"before_commit","edge":"after"},{"kind":"rename_player","scope":"original","phase":"after_commit","edge":"after"},{"kind":"rename_player","scope":"original","phase":"rollback","edge":"before"},{"kind":"rename_player","scope":"original","phase":"rollback","edge":"after"},{"kind":"rename_player","scope":"original","phase":"postverify","edge":"before"},{"kind":"rename_player","scope":"original","phase":"postverify","edge":"after"},{"kind":"rename_player","scope":"original","phase":"checkpoint","edge":"before"},{"kind":"rename_player","scope":"original","phase":"checkpoint","edge":"after"},{"kind":"rename_player","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"rename_player","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"},{"kind":"rename_player","player_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","expected_revision":"2","name":"Alice After","utc":"2026-10-03T12:03:00Z"}],"crash_selector":{"request_ordinal":2,"kind":"rename_player","scope":"original","phase":"after_commit","edge":"after","occurrence":1,"service_ordinal":1},"exit_code":86},"required_call_prefix":[],"selected_and_prior_predicates":[{"detail":{"sqlite_result":101,"autocommit":true,"txn_state":0}}]}]},{"id":"publish_ack","fixture":"pair","driver_stages":["publish_ack_prepare","publish_ack_reopen"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"},{"kind":"rename_player","scope":"original","phase":"before_begin","edge":"before"},{"kind":"rename_player","scope":"original","phase":"before_begin","edge":"after"},{"kind":"rename_player","scope":"original","phase":"row_write","edge":"before"},{"kind":"rename_player","scope":"original","phase":"row_write","edge":"after"},{"kind":"rename_player","scope":"original","phase":"before_commit","edge":"before"},{"kind":"rename_player","scope":"original","phase":"before_commit","edge":"after"},{"kind":"rename_player","scope":"original","phase":"after_commit","edge":"after"},{"kind":"rename_player","scope":"original","phase":"rollback","edge":"before"},{"kind":"rename_player","scope":"original","phase":"rollback","edge":"after"},{"kind":"rename_player","scope":"original","phase":"postverify","edge":"before"},{"kind":"rename_player","scope":"original","phase":"postverify","edge":"after"},{"kind":"rename_player","scope":"original","phase":"checkpoint","edge":"before"},{"kind":"rename_player","scope":"original","phase":"checkpoint","edge":"after"},{"kind":"rename_player","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"rename_player","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"},{"kind":"rename_player","player_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","expected_revision":"2","name":"Alice After","utc":"2026-10-03T12:03:00Z"}],"crash_selector":{"request_ordinal":2,"kind":"rename_player","scope":"service","phase":"publish_ack","edge":"before","occurrence":1,"service_ordinal":1},"exit_code":86},"required_call_prefix":[],"selected_and_prior_predicates":[{"prior":{"kind":"rename_player","scope":"original","phase":"after_commit","edge":"after","sqlite_result":101,"autocommit":true,"txn_state":0}},{"prior":{"kind":"rename_player","scope":"original","phase":"postverify","edge":"after","verified_rows":1}}]}]},{"id":"wal_schema","fixture":"empty","driver_stages":["wal_schema_prepare","wal_schema_reopen"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"}],"crash_selector":{"request_ordinal":1,"kind":"start","scope":"original","phase":"after_commit","edge":"after","occurrence":1,"service_ordinal":1},"exit_code":86},"required_call_prefix":[],"selected_and_prior_predicates":[{"detail":{"sqlite_result":101,"autocommit":true,"txn_state":0}}]}]},{"id":"interrupt_before_commit","fixture":"active","driver_stages":["interrupt_before_commit_prepare","interrupt_before_commit_reopen"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"}],"crash_selector":{"request_ordinal":1,"kind":"start","scope":"original","phase":"before_commit","edge":"before","occurrence":1,"service_ordinal":1},"exit_code":86},"required_call_prefix":[],"selected_and_prior_predicates":[{"detail":{"sqlite_result":null,"autocommit":false,"txn_state":2}},{"prior":{"kind":"start","scope":"original","phase":"row_write","edge":"after","sqlite_result":101}}]}]},{"id":"interrupt_after_commit","fixture":"active","driver_stages":["interrupt_after_commit_prepare","interrupt_after_commit_reopen"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"}],"crash_selector":{"request_ordinal":1,"kind":"start","scope":"original","phase":"after_commit","edge":"after","occurrence":1,"service_ordinal":1},"exit_code":86},"required_call_prefix":[],"selected_and_prior_predicates":[{"detail":{"sqlite_result":101,"autocommit":true,"txn_state":0}}]}]},{"id":"pre_intent_read","fixture":"pair","driver_stages":["pre_intent_read_prepare","pre_intent_read_reopen"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"}],"crash_selector":{"request_ordinal":1,"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after","occurrence":2,"service_ordinal":1},"exit_code":86},"required_call_prefix":[{"occurrence":1,"purpose":"recheck_sentinel","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"binding":"sentinel_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":2,"purpose":"inspect_main_header","role":"main","io_kind":"read","chunk_index":1,"requested_bytes":100,"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null}],"selected_and_prior_predicates":[{"detail":{"role":"main","io_kind":"read","chunk_index":1,"requested_bytes":100,"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},"scope":"recovery","phase":"recovery_copy","edge":"after"}]}]},{"id":"intent_before_write","fixture":"pair","driver_stages":["intent_before_write_prepare","intent_before_write_inspect"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"}],"crash_selector":{"request_ordinal":1,"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before","occurrence":3,"service_ordinal":1},"exit_code":86},"required_call_prefix":[{"occurrence":1,"purpose":"recheck_sentinel","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"binding":"sentinel_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":2,"purpose":"inspect_main_header","role":"main","io_kind":"read","chunk_index":1,"requested_bytes":100,"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":3,"purpose":"write_intent","role":"temp","io_kind":"write","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null}],"selected_and_prior_predicates":[{"detail":{"role":"temp","io_kind":"write","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":null,"win32_error":null,"owned_handle":true,"installed":null},"scope":"recovery","phase":"recovery_copy","edge":"before"}]}]},{"id":"copy_after_read","fixture":"pair","driver_stages":["copy_after_read_prepare","copy_after_read_inspect"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"}],"crash_selector":{"request_ordinal":1,"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after","occurrence":6,"service_ordinal":1},"exit_code":86},"required_call_prefix":[{"occurrence":1,"purpose":"recheck_sentinel","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"binding":"sentinel_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":2,"purpose":"inspect_main_header","role":"main","io_kind":"read","chunk_index":1,"requested_bytes":100,"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":3,"purpose":"write_intent","role":"temp","io_kind":"write","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":4,"purpose":"verify_intent","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":5,"purpose":"verify_intent_eof","role":"temp","io_kind":"read","chunk_index":2,"requested_bytes":1,"completed_bytes":0,"win32_error":0,"owned_handle":true,"installed":null},{"occurrence":6,"purpose":"copy_main_read","role":"main","io_kind":"read","chunk_index":1,"requested_bytes":{"binding":"original_main_first_chunk_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null}],"selected_and_prior_predicates":[{"detail":{"role":"main","io_kind":"read","chunk_index":1,"requested_bytes":{"binding":"original_main_first_chunk_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},"scope":"recovery","phase":"recovery_copy","edge":"after"}]}]},{"id":"copy_after_write","fixture":"pair","driver_stages":["copy_after_write_prepare","copy_after_write_inspect"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"}],"crash_selector":{"request_ordinal":1,"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after","occurrence":7,"service_ordinal":1},"exit_code":86},"required_call_prefix":[{"occurrence":1,"purpose":"recheck_sentinel","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"binding":"sentinel_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":2,"purpose":"inspect_main_header","role":"main","io_kind":"read","chunk_index":1,"requested_bytes":100,"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":3,"purpose":"write_intent","role":"temp","io_kind":"write","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":4,"purpose":"verify_intent","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":5,"purpose":"verify_intent_eof","role":"temp","io_kind":"read","chunk_index":2,"requested_bytes":1,"completed_bytes":0,"win32_error":0,"owned_handle":true,"installed":null},{"occurrence":6,"purpose":"copy_main_read","role":"main","io_kind":"read","chunk_index":1,"requested_bytes":{"binding":"original_main_first_chunk_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":7,"purpose":"copy_main_write","role":"main","io_kind":"write","chunk_index":1,"requested_bytes":{"binding":"original_main_first_chunk_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null}],"selected_and_prior_predicates":[{"detail":{"role":"main","io_kind":"write","chunk_index":1,"requested_bytes":{"binding":"original_main_first_chunk_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},"scope":"recovery","phase":"recovery_copy","edge":"after"}]}]},{"id":"work_before_sqlite","fixture":"pair","driver_stages":["work_before_sqlite_prepare","work_before_sqlite_inspect"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"}],"crash_selector":{"request_ordinal":1,"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before","occurrence":1,"service_ordinal":1},"exit_code":86},"required_call_prefix":[],"selected_and_prior_predicates":[{"detail":{"sqlite_result":null}},{"pre_release_roster":"one_complete_retained_and_associated_complete_work_no_sqlite"}]}]},{"id":"two_partial_limit","fixture":"pair","driver_stages":["two_partial_limit_prepare","two_partial_limit_inspect"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"}],"crash_selector":{"request_ordinal":1,"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after","occurrence":7,"service_ordinal":1},"exit_code":86},"required_call_prefix":[{"occurrence":1,"purpose":"recheck_sentinel","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"binding":"sentinel_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":2,"purpose":"inspect_main_header","role":"main","io_kind":"read","chunk_index":1,"requested_bytes":100,"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":3,"purpose":"write_intent","role":"temp","io_kind":"write","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":4,"purpose":"verify_intent","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":5,"purpose":"verify_intent_eof","role":"temp","io_kind":"read","chunk_index":2,"requested_bytes":1,"completed_bytes":0,"win32_error":0,"owned_handle":true,"installed":null},{"occurrence":6,"purpose":"copy_main_read","role":"main","io_kind":"read","chunk_index":1,"requested_bytes":{"binding":"original_main_first_chunk_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":7,"purpose":"copy_main_write","role":"main","io_kind":"write","chunk_index":1,"requested_bytes":{"binding":"original_main_first_chunk_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null}],"selected_and_prior_predicates":[{"detail":{"role":"main","io_kind":"write","chunk_index":1,"requested_bytes":{"binding":"original_main_first_chunk_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},"scope":"recovery","phase":"recovery_copy","edge":"after"}]},{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"}],"crash_selector":{"request_ordinal":1,"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after","occurrence":9,"service_ordinal":1},"exit_code":86},"required_call_prefix":[{"occurrence":1,"purpose":"recheck_sentinel","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"binding":"sentinel_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":2,"purpose":"list_existing_intent","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":3,"purpose":"inspect_main_header","role":"main","io_kind":"read","chunk_index":1,"requested_bytes":100,"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":4,"purpose":"snapshot_relist_existing_intent","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":5,"purpose":"write_intent","role":"temp","io_kind":"write","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":6,"purpose":"verify_intent","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":7,"purpose":"verify_intent_eof","role":"temp","io_kind":"read","chunk_index":2,"requested_bytes":1,"completed_bytes":0,"win32_error":0,"owned_handle":true,"installed":null},{"occurrence":8,"purpose":"copy_main_read","role":"main","io_kind":"read","chunk_index":1,"requested_bytes":{"binding":"original_main_first_chunk_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":9,"purpose":"copy_main_write","role":"main","io_kind":"write","chunk_index":1,"requested_bytes":{"binding":"original_main_first_chunk_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null}],"selected_and_prior_predicates":[{"detail":{"role":"main","io_kind":"write","chunk_index":1,"requested_bytes":{"binding":"original_main_first_chunk_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},"scope":"recovery","phase":"recovery_copy","edge":"after"}]}]},{"id":"export_after_write","fixture":"export","driver_stages":["export_after_write_prepare","export_after_write_inspect"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"},{"kind":"export_player","scope":"original","phase":"before_begin","edge":"before"},{"kind":"export_player","scope":"original","phase":"before_begin","edge":"after"},{"kind":"export_player","scope":"original","phase":"before_commit","edge":"before"},{"kind":"export_player","scope":"original","phase":"before_commit","edge":"after"},{"kind":"export_player","scope":"original","phase":"after_commit","edge":"after"},{"kind":"export_player","scope":"original","phase":"rollback","edge":"before"},{"kind":"export_player","scope":"original","phase":"rollback","edge":"after"},{"kind":"export_player","scope":"export","phase":"export_create","edge":"before"},{"kind":"export_player","scope":"export","phase":"export_create","edge":"after"},{"kind":"export_player","scope":"export","phase":"export_write","edge":"before"},{"kind":"export_player","scope":"export","phase":"export_write","edge":"after"},{"kind":"export_player","scope":"export","phase":"export_flush","edge":"before"},{"kind":"export_player","scope":"export","phase":"export_flush","edge":"after"},{"kind":"export_player","scope":"export","phase":"export_move","edge":"before"},{"kind":"export_player","scope":"export","phase":"export_move","edge":"after"},{"kind":"export_player","scope":"export","phase":"export_verify_target","edge":"before"},{"kind":"export_player","scope":"export","phase":"export_verify_target","edge":"after"},{"kind":"export_player","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"export_player","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"},{"kind":"export_player","player_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","expected_revision":"2"}],"crash_selector":{"request_ordinal":2,"kind":"export_player","scope":"export","phase":"export_write","edge":"after","occurrence":1,"service_ordinal":1},"exit_code":86},"required_call_prefix":[],"selected_and_prior_predicates":[{"detail":{"win32_error":0,"role":"temp","owned_handle":true,"installed":null,"requested_bytes":{"binding":"expected_export_bytes"},"completed_bytes":{"binding":"expected_export_bytes"},"chunk_index":1}}]}]},{"id":"export_after_flush","fixture":"export","driver_stages":["export_after_flush_prepare","export_after_flush_inspect"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"},{"kind":"export_player","scope":"original","phase":"before_begin","edge":"before"},{"kind":"export_player","scope":"original","phase":"before_begin","edge":"after"},{"kind":"export_player","scope":"original","phase":"before_commit","edge":"before"},{"kind":"export_player","scope":"original","phase":"before_commit","edge":"after"},{"kind":"export_player","scope":"original","phase":"after_commit","edge":"after"},{"kind":"export_player","scope":"original","phase":"rollback","edge":"before"},{"kind":"export_player","scope":"original","phase":"rollback","edge":"after"},{"kind":"export_player","scope":"export","phase":"export_create","edge":"before"},{"kind":"export_player","scope":"export","phase":"export_create","edge":"after"},{"kind":"export_player","scope":"export","phase":"export_write","edge":"before"},{"kind":"export_player","scope":"export","phase":"export_write","edge":"after"},{"kind":"export_player","scope":"export","phase":"export_flush","edge":"before"},{"kind":"export_player","scope":"export","phase":"export_flush","edge":"after"},{"kind":"export_player","scope":"export","phase":"export_move","edge":"before"},{"kind":"export_player","scope":"export","phase":"export_move","edge":"after"},{"kind":"export_player","scope":"export","phase":"export_verify_target","edge":"before"},{"kind":"export_player","scope":"export","phase":"export_verify_target","edge":"after"},{"kind":"export_player","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"export_player","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"},{"kind":"export_player","player_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","expected_revision":"2"}],"crash_selector":{"request_ordinal":2,"kind":"export_player","scope":"export","phase":"export_flush","edge":"after","occurrence":1,"service_ordinal":1},"exit_code":86},"required_call_prefix":[],"selected_and_prior_predicates":[{"detail":{"win32_error":0,"role":"temp","owned_handle":true,"installed":null,"requested_bytes":null,"completed_bytes":null}}]}]},{"id":"export_after_move","fixture":"export","driver_stages":["export_after_move_prepare","export_after_move_inspect"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"},{"kind":"export_player","scope":"original","phase":"before_begin","edge":"before"},{"kind":"export_player","scope":"original","phase":"before_begin","edge":"after"},{"kind":"export_player","scope":"original","phase":"before_commit","edge":"before"},{"kind":"export_player","scope":"original","phase":"before_commit","edge":"after"},{"kind":"export_player","scope":"original","phase":"after_commit","edge":"after"},{"kind":"export_player","scope":"original","phase":"rollback","edge":"before"},{"kind":"export_player","scope":"original","phase":"rollback","edge":"after"},{"kind":"export_player","scope":"export","phase":"export_create","edge":"before"},{"kind":"export_player","scope":"export","phase":"export_create","edge":"after"},{"kind":"export_player","scope":"export","phase":"export_write","edge":"before"},{"kind":"export_player","scope":"export","phase":"export_write","edge":"after"},{"kind":"export_player","scope":"export","phase":"export_flush","edge":"before"},{"kind":"export_player","scope":"export","phase":"export_flush","edge":"after"},{"kind":"export_player","scope":"export","phase":"export_move","edge":"before"},{"kind":"export_player","scope":"export","phase":"export_move","edge":"after"},{"kind":"export_player","scope":"export","phase":"export_verify_target","edge":"before"},{"kind":"export_player","scope":"export","phase":"export_verify_target","edge":"after"},{"kind":"export_player","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"export_player","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"},{"kind":"export_player","player_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","expected_revision":"2"}],"crash_selector":{"request_ordinal":2,"kind":"export_player","scope":"export","phase":"export_move","edge":"after","occurrence":1,"service_ordinal":1},"exit_code":86},"required_call_prefix":[],"selected_and_prior_predicates":[{"detail":{"win32_error":0,"role":"target","owned_handle":true,"installed":true,"requested_bytes":null,"completed_bytes":null}}]}]},{"id":"delete_before_row","fixture":"pair_two_ended_histories","driver_stages":["delete_before_row_prepare","delete_before_row_reopen"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"},{"kind":"delete_player","scope":"original","phase":"before_begin","edge":"before"},{"kind":"delete_player","scope":"original","phase":"before_begin","edge":"after"},{"kind":"delete_player","scope":"original","phase":"row_write","edge":"before"},{"kind":"delete_player","scope":"original","phase":"row_write","edge":"after"},{"kind":"delete_player","scope":"original","phase":"before_commit","edge":"before"},{"kind":"delete_player","scope":"original","phase":"before_commit","edge":"after"},{"kind":"delete_player","scope":"original","phase":"after_commit","edge":"after"},{"kind":"delete_player","scope":"original","phase":"rollback","edge":"before"},{"kind":"delete_player","scope":"original","phase":"rollback","edge":"after"},{"kind":"delete_player","scope":"original","phase":"postverify","edge":"before"},{"kind":"delete_player","scope":"original","phase":"postverify","edge":"after"},{"kind":"delete_player","scope":"original","phase":"checkpoint","edge":"before"},{"kind":"delete_player","scope":"original","phase":"checkpoint","edge":"after"},{"kind":"delete_player","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"delete_player","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"},{"kind":"delete_player","player_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","expected_revision":"2"}],"crash_selector":{"kind":"delete_player","scope":"original","phase":"row_write","edge":"before","request_ordinal":2,"occurrence":1,"service_ordinal":1},"exit_code":86},"required_call_prefix":[],"selected_and_prior_predicates":[{"detail":{"sqlite_result":null,"autocommit":false,"txn_state":2}}]}]},{"id":"delete_after_row","fixture":"pair_two_ended_histories","driver_stages":["delete_after_row_prepare","delete_after_row_reopen"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"},{"kind":"delete_player","scope":"original","phase":"before_begin","edge":"before"},{"kind":"delete_player","scope":"original","phase":"before_begin","edge":"after"},{"kind":"delete_player","scope":"original","phase":"row_write","edge":"before"},{"kind":"delete_player","scope":"original","phase":"row_write","edge":"after"},{"kind":"delete_player","scope":"original","phase":"before_commit","edge":"before"},{"kind":"delete_player","scope":"original","phase":"before_commit","edge":"after"},{"kind":"delete_player","scope":"original","phase":"after_commit","edge":"after"},{"kind":"delete_player","scope":"original","phase":"rollback","edge":"before"},{"kind":"delete_player","scope":"original","phase":"rollback","edge":"after"},{"kind":"delete_player","scope":"original","phase":"postverify","edge":"before"},{"kind":"delete_player","scope":"original","phase":"postverify","edge":"after"},{"kind":"delete_player","scope":"original","phase":"checkpoint","edge":"before"},{"kind":"delete_player","scope":"original","phase":"checkpoint","edge":"after"},{"kind":"delete_player","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"delete_player","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"},{"kind":"delete_player","player_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","expected_revision":"2"}],"crash_selector":{"kind":"delete_player","scope":"original","phase":"row_write","edge":"after","request_ordinal":2,"occurrence":1,"service_ordinal":1},"exit_code":86},"required_call_prefix":[],"selected_and_prior_predicates":[{"detail":{"sqlite_result":101,"autocommit":false,"txn_state":2}}]}]},{"id":"delete_after_commit","fixture":"pair_two_ended_histories","driver_stages":["delete_after_commit_prepare","delete_after_commit_reopen"],"actors":[{"plan_template":{"schema":"LocalPlayersCrashActorPlan/v1","nonce":{"root_binding":"fresh_nonce"},"service_ordinal":1,"maximum_actual_events":16384,"sites":[{"kind":"start","scope":"original","phase":"before_open","edge":"before"},{"kind":"start","scope":"original","phase":"before_open","edge":"after"},{"kind":"start","scope":"original","phase":"before_begin","edge":"before"},{"kind":"start","scope":"original","phase":"before_begin","edge":"after"},{"kind":"start","scope":"original","phase":"row_write","edge":"before"},{"kind":"start","scope":"original","phase":"row_write","edge":"after"},{"kind":"start","scope":"original","phase":"before_commit","edge":"before"},{"kind":"start","scope":"original","phase":"before_commit","edge":"after"},{"kind":"start","scope":"original","phase":"after_commit","edge":"after"},{"kind":"start","scope":"original","phase":"rollback","edge":"before"},{"kind":"start","scope":"original","phase":"rollback","edge":"after"},{"kind":"start","scope":"original","phase":"postverify","edge":"before"},{"kind":"start","scope":"original","phase":"postverify","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"before_open","edge":"after"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"before"},{"kind":"start","scope":"qualification_copy","phase":"postverify","edge":"after"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"before"},{"kind":"start","scope":"recovery","phase":"recovery_copy","edge":"after"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"start","scope":"service","phase":"publish_ack","edge":"after"},{"kind":"delete_player","scope":"original","phase":"before_begin","edge":"before"},{"kind":"delete_player","scope":"original","phase":"before_begin","edge":"after"},{"kind":"delete_player","scope":"original","phase":"row_write","edge":"before"},{"kind":"delete_player","scope":"original","phase":"row_write","edge":"after"},{"kind":"delete_player","scope":"original","phase":"before_commit","edge":"before"},{"kind":"delete_player","scope":"original","phase":"before_commit","edge":"after"},{"kind":"delete_player","scope":"original","phase":"after_commit","edge":"after"},{"kind":"delete_player","scope":"original","phase":"rollback","edge":"before"},{"kind":"delete_player","scope":"original","phase":"rollback","edge":"after"},{"kind":"delete_player","scope":"original","phase":"postverify","edge":"before"},{"kind":"delete_player","scope":"original","phase":"postverify","edge":"after"},{"kind":"delete_player","scope":"original","phase":"checkpoint","edge":"before"},{"kind":"delete_player","scope":"original","phase":"checkpoint","edge":"after"},{"kind":"delete_player","scope":"service","phase":"publish_ack","edge":"before"},{"kind":"delete_player","scope":"service","phase":"publish_ack","edge":"after"}],"jobs":[{"kind":"start"},{"kind":"delete_player","player_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","expected_revision":"2"}],"crash_selector":{"kind":"delete_player","scope":"original","phase":"after_commit","edge":"after","request_ordinal":2,"occurrence":1,"service_ordinal":1},"exit_code":86},"required_call_prefix":[],"selected_and_prior_predicates":[{"detail":{"sqlite_result":101,"autocommit":true,"txn_state":0}},{"prior":{"kind":"delete_player","scope":"original","phase":"row_write","edge":"after","sqlite_result":101,"autocommit":false,"txn_state":2}}]}]}],"full_call_prefixes":{"fresh":[{"occurrence":1,"purpose":"recheck_sentinel","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"binding":"sentinel_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":2,"purpose":"inspect_main_header","role":"main","io_kind":"read","chunk_index":1,"requested_bytes":100,"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":3,"purpose":"write_intent","role":"temp","io_kind":"write","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":4,"purpose":"verify_intent","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":5,"purpose":"verify_intent_eof","role":"temp","io_kind":"read","chunk_index":2,"requested_bytes":1,"completed_bytes":0,"win32_error":0,"owned_handle":true,"installed":null},{"occurrence":6,"purpose":"copy_main_read","role":"main","io_kind":"read","chunk_index":1,"requested_bytes":{"binding":"original_main_first_chunk_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":7,"purpose":"copy_main_write","role":"main","io_kind":"write","chunk_index":1,"requested_bytes":{"binding":"original_main_first_chunk_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null}],"second_partial":[{"occurrence":1,"purpose":"recheck_sentinel","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"binding":"sentinel_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":2,"purpose":"list_existing_intent","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":3,"purpose":"inspect_main_header","role":"main","io_kind":"read","chunk_index":1,"requested_bytes":100,"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":4,"purpose":"snapshot_relist_existing_intent","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":5,"purpose":"write_intent","role":"temp","io_kind":"write","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":6,"purpose":"verify_intent","role":"temp","io_kind":"read","chunk_index":1,"requested_bytes":{"positive_at_most":65536},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":7,"purpose":"verify_intent_eof","role":"temp","io_kind":"read","chunk_index":2,"requested_bytes":1,"completed_bytes":0,"win32_error":0,"owned_handle":true,"installed":null},{"occurrence":8,"purpose":"copy_main_read","role":"main","io_kind":"read","chunk_index":1,"requested_bytes":{"binding":"original_main_first_chunk_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null},{"occurrence":9,"purpose":"copy_main_write","role":"main","io_kind":"write","chunk_index":1,"requested_bytes":{"binding":"original_main_first_chunk_bytes"},"completed_bytes":"requested","win32_error":0,"owned_handle":true,"installed":null}]},"prefix_assertion":"Every listed actual call has before and after with same occurrence, except selected before edge intentionally has no actual call/after. Successful full completions required. No parity inference, output-fitted occurrence or partial-call substitution. Actual detail IDs correlate to Root-bound sentinel/original/temp handles.","remaining_gates":["Actual actor86, event/RESERVATION/ARRIVED/RELEASE order and distinct-process reopen are Root supervisor gates, never driver assertions.","These19 do not prove real partial WinAPI completion, rollback failure, disk full, flush failure or partial retained-set deletion. Transactional player-cascade deletion is distinct from retained-directory management deletion."]}')
CRASH_SCENARIO_IDS = [r["id"] for r in CRASH_RECIPES["recipes"]]
CRASH_EXPORT_BYTES = b'{"format":"LocalPlayerSummary","payload_json":"{\\"player\\":{\\"created_utc\\":\\"2026-10-03T12:00:00Z\\",\\"id\\":\\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\",\\"name\\":\\"Alice\\",\\"revision\\":\\"2\\",\\"type\\":\\"LocalPlayer\\",\\"updated_utc\\":\\"2026-10-03T12:04:00Z\\",\\"version\\":1},\\"practice\\":[{\\"archive\\":{\\"linked\\":false},\\"commit_sequence\\":\\"8\\",\\"creation_sequence\\":\\"7\\",\\"end_reason\\":\\"user_end\\",\\"first_tick\\":\\"0\\",\\"id\\":\\"dddddddddddddddddddddddddddddddd\\",\\"last_observed_utc\\":\\"2026-10-03T12:02:00Z\\",\\"last_tick\\":\\"5\\",\\"observed_ticks\\":\\"5\\",\\"player_id\\":\\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\",\\"revision\\":\\"2\\",\\"source\\":{\\"angular_integration_method\\":null,\\"model_identity\\":{\\"backend_model\\":\\"original-interactive\\",\\"id\\":\\"original-interactive-prototype\\",\\"version\\":\\"0.1.0-prototype\\"},\\"named_start\\":\\"ground-ready\\",\\"native_source_fingerprint\\":\\"1111111111111111111111111111111111111111111111111111111111111111\\",\\"prepared_world_sha256\\":\\"2222222222222222222222222222222222222222222222222222222222222222\\",\\"session_id\\":\\"synthetic-service-reference-2\\",\\"source_variant\\":\\"jsbsim-1.3.1-upstream\\",\\"wind_profile\\":\\"calm\\"},\\"started_utc\\":\\"2026-10-03T12:01:00Z\\",\\"status\\":\\"manually_ended\\",\\"tick_rate_hz\\":120,\\"type\\":\\"LocalPractice\\",\\"version\\":1},{\\"archive\\":{\\"linked\\":false},\\"commit_sequence\\":\\"6\\",\\"creation_sequence\\":\\"5\\",\\"end_reason\\":\\"user_end\\",\\"first_tick\\":\\"9007199254740993\\",\\"id\\":\\"cccccccccccccccccccccccccccccccc\\",\\"last_observed_utc\\":\\"2026-10-03T12:02:00Z\\",\\"last_tick\\":\\"9007199254741000\\",\\"observed_ticks\\":\\"7\\",\\"player_id\\":\\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\",\\"revision\\":\\"2\\",\\"source\\":{\\"angular_integration_method\\":null,\\"model_identity\\":{\\"backend_model\\":\\"original-interactive\\",\\"id\\":\\"original-interactive-prototype\\",\\"version\\":\\"0.1.0-prototype\\"},\\"named_start\\":\\"ground-ready\\",\\"native_source_fingerprint\\":\\"1111111111111111111111111111111111111111111111111111111111111111\\",\\"prepared_world_sha256\\":\\"2222222222222222222222222222222222222222222222222222222222222222\\",\\"session_id\\":\\"synthetic-service-reference-1\\",\\"source_variant\\":\\"jsbsim-1.3.1-upstream\\",\\"wind_profile\\":\\"calm\\"},\\"started_utc\\":\\"2026-10-03T12:01:00Z\\",\\"status\\":\\"manually_ended\\",\\"tick_rate_hz\\":120,\\"type\\":\\"LocalPractice\\",\\"version\\":1}],\\"preferences\\":{\\"audio\\":{\\"airflow_gain\\":{\\"$binary64_le\\":\\"000000000000f03f\\"},\\"enabled\\":true,\\"engine_gain\\":{\\"$binary64_le\\":\\"0000000000000080\\"},\\"show_panel_captions\\":true},\\"legacy_input\\":null,\\"piston_input\\":null,\\"player_id\\":\\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\",\\"revision\\":\\"2\\",\\"type\\":\\"LocalPlayerPreferences\\",\\"version\\":1}}","payload_sha256":"1c27d5cfd564fa6772bd0a5e2c6671bf649e4b9ec578af4679b9e938c52c10ab","version":1}'
# BEGIN exact independent trace_model.py excluding scalar __main__ examples
"""Original MIT. Prelaunch full-call expectation from source, never from history.

Inputs are Root's immutable PRE-actor raw inventory, not candidate call output.
Only successful complete calls are modeled for these fixed small crash recipes;
partial completion/failure causes mismatch and fails this recipe's premise.
"""
import json

NAMES=('players.sqlite3','players.sqlite3-wal','players.sqlite3-shm','players.sqlite3-journal')
ROLES=('main','wal','shm','journal')
CAPS=(268435456,67108864,8388608,8388608)
def compact(value): return json.dumps(value,sort_keys=True,separators=(',',':')).encode()
def metadata_sizes(files):
    # GUIDs, timestamp, file/volume IDs and SHA fields have fixed ASCII width.
    # No native-generated random value is consulted to derive these sizes.
    identity={'file_id_hex':'0'*32,'volume_serial_hex':'0'*16}
    rows=[];copies=[]
    for name,role,size in zip(NAMES,ROLES,files):
        row=dict(role=role,name=name,present=size is not None,bytes=size,source_identity=identity if size is not None else None)
        rows.append(row)
        copies.append(dict(row,sha256='0'*64 if size is not None else None,copy_identity=identity if size is not None else None))
    base=dict(version=1,id='0'*32,created_utc='2026-10-03T12:00:00Z')
    intent=compact(dict(base,format='LocalPlayersRecoveryIntent',source_files=rows))
    manifest=compact(dict(base,format='LocalPlayersRecoveryCopy',intent_sha256='0'*64,files=copies))
    return len(intent),len(manifest)

def expected_recovery_calls(*,sentinel_bytes,files,existing_partial_intent_bytes=None):
    """Complete worker trace through snapshot(), just before WORK before_open.

    files: exactly four None-or-nonnegative integer byte lengths from PRE-actor
    ordinary original4. Existing partial contains one valid intent and only main
    copy, no manifest/work; its raw length is PRE-second-actor observed. Its
    data file is opened/identified but never ReadFile-hashed by audit_set(partial).
    """
    assert type(sentinel_bytes) is int and 0<sentinel_bytes<=1024
    assert len(files)==4 and type(files[0]) is int and files[0]>=100
    for size,cap in zip(files,CAPS): assert size is None or type(size) is int and 0<=size<=cap
    if existing_partial_intent_bytes is not None:
        assert type(existing_partial_intent_bytes) is int and 0<existing_partial_intent_bytes<=65536
    out=[]
    def add(purpose,role,io,requested,completed,chunk):
        out.append(dict(occurrence=len(out)+1,purpose=purpose,role=role,io_kind=io,chunk_index=chunk,requested_bytes=requested,completed_bytes=completed,win32_error=0,owned_handle=True,installed=None))
    def read(purpose,role,size,eof=False,capacity=65536):
        chunk=0;left=size
        while left:
            chunk+=1;n=min(capacity,left);add(purpose,role,'read',n,n,chunk);left-=n
        if eof:add(purpose+'_eof',role,'read',1,0,chunk+1)
    def write_verify(purpose,size):
        left=size;chunk=0
        while left:
            chunk+=1;n=min(65536,left);add('write_'+purpose,'temp','write',n,n,chunk);left-=n
        read('verify_'+purpose,'temp',size,True)
    def copy(purpose):
        for role,size in zip(ROLES,files):
            if size is None:continue
            left=size;chunk=0
            while left:
                chunk+=1;n=min(65536,left)
                add(purpose+'_'+role+'_read',role,'read',n,n,chunk)
                add(purpose+'_'+role+'_write',role,'write',n,n,chunk);left-=n
            read(purpose+'_'+role+'_verify_target',role,size,True)
            read(purpose+'_'+role+'_verify_source',role,size,True)
    read('recheck_sentinel','temp',sentinel_bytes)
    if existing_partial_intent_bytes is not None:read('list_existing_intent','temp',existing_partial_intent_bytes)
    read('inspect_main_header','main',100)
    if existing_partial_intent_bytes is not None:read('snapshot_relist_existing_intent','temp',existing_partial_intent_bytes)
    intent,manifest=metadata_sizes(files)
    write_verify('intent',intent)
    copy('copy_retained')
    write_verify('manifest',manifest)
    read('audit_retained_intent','temp',intent)
    read('audit_retained_manifest','temp',manifest)
    for role,size in zip(ROLES,files):
        # snapshot() audits retained files using metadata_io_[8192], not the
        # caller's65536-byte copy buffer (windows_filesystem.hpp / audit_set).
        if size is not None:read('audit_retained_'+role,role,size,True,capacity=8192)
    write_verify('work_intent',intent)
    copy('copy_work')
    assert len(out)*2<16384
    return out

# END exact independent trace model


def admit_crash_stage_stdout(raw,stage,pid,descriptor,plan):
    value=strict_json_bytes(raw,262144)
    exact_keys(value,['schema','stage','stage_only','pid','nonce','descriptor_sha256','plan_sha256','checks','actual_events','joined','observations'])
    plan_value,_=load_json(plan['path'],plan['sha256'])
    require(value['schema']=='LocalPlayersCrashStageReceipt/v1' and value['stage']==stage and value['stage_only'] is True
            and type(value['pid']) is int and value['pid']==pid and value['nonce']==plan_value['nonce']
            and value['descriptor_sha256']==descriptor['sha256'] and value['plan_sha256']==plan['sha256']
            and value['joined'] is True,"actual stage-only process/plan/capability receipt")
    actual_int(value['checks'],1,(1<<63)-1,'actual stage checks'); actual_int(value['actual_events'],0,16384,'actual stage events')
    rows=value['observations']; require(type(rows) is list and 1<=len(rows)<=128 and len(json_bytes(rows))<=131072,"finite actual stage observations")
    data='players\\.sqlite3(?:-wal|-shm|-journal)?'
    label=re.compile('(?:original/'+data+'|(?:recovery|work)-[0-9a-f]{32}/(?:'+data+'|intent\\.json|manifest\\.json)|export/(?:target|\\.fsplayers-[0-9a-f]{32}\\.tmp))')
    for row in rows:
        require(type(row) is dict,"closed observation")
        if 'label' in row:
            exact_keys(row,['label','present','bytes','sha256','identity'])
            require(type(row['label']) is str and label.fullmatch(row['label']) and type(row['present']) is bool,"closed actual file label/presence")
            if row['present']:
                actual_int(row['bytes'],0,335544320,'actual finite file bytes')
                require(type(row['sha256']) is str and HEX.fullmatch(row['sha256']),"actual file SHA")
                exact_keys(row['identity'],['file_id_hex','volume_serial_hex'])
                require(re.fullmatch('[0-9a-f]{32}',row['identity']['file_id_hex']) and re.fullmatch('[0-9a-f]{16}',row['identity']['volume_serial_hex']),"actual FILE_ID_INFO hex")
            else: require(row['bytes'] is None and row['sha256'] is None and row['identity'] is None,"absent file null companions")
        elif row.get('kind')=='quiescence':
            exact_keys(row,['kind','ever_worker','actual_join'])
            require(type(row['ever_worker']) is bool and row['actual_join'] is True
                    and row['ever_worker']==(stage!='wal_schema_prepare'),"no fabricated ever-created worker")
        else:
            exact_keys(row,['kind','frames','commits','main_schema_cookie','committed_schema_cookie'])
            require(row['kind']=='wal_schema' and stage=='wal_schema_reopen',"WAL diagnosis stage")
            frames=actual_int(row['frames'],1,16384,'actual WAL frames'); actual_int(row['commits'],1,frames,'actual WAL commits')
            require(type(row['main_schema_cookie']) is int and row['main_schema_cookie']==0,"actual stale main")
            actual_int(row['committed_schema_cookie'],1,0xffffffff,'actual committed WAL page1')
    return value


def pattern_value(expected,actual,bindings,detail):
    if type(expected) is dict:
        if set(expected)=={'binding'}: return actual==bindings[expected['binding']] and type(actual) is int
        if set(expected)=={'positive_at_most'}: return type(actual) is int and 0<actual<=expected['positive_at_most']
        require(type(actual) is dict,"expected observation dictionary")
        return all(k in actual and pattern_value(v,actual[k],bindings,actual) for k,v in expected.items())
    if expected=='requested': return type(actual) is int and actual==detail['requested_bytes']
    return type(actual) is type(expected) and actual==expected


def preactor_facts(capability,snapshot):
    rows={r['path']:r for r in snapshot}
    files=[rows[n]['bytes'] if n in rows else None for n in NAMES]
    sentinel=rows['.local-players-test-root.json']
    require(sentinel['sha256']==capability['value']['sentinel_sha256'],"same actual admitted sentinel")
    intents=[r for r in snapshot if re.fullmatch('recovery/recovery-[0-9a-f]{32}/intent.json',r['path'])]
    require(len(intents)<=1,"at most one prior partial before second actor")
    return files,sentinel['bytes'],(intents[0]['bytes'] if intents else None)


def crash_publish_ack_admission(plan,events):
    # Actor jobs are sequential: finish_job validates and acknowledges each
    # prior terminal before submitting the selected request. Service snapshots
    # counts under its mutex before exposing the transition to owner polling.
    selected=plan['crash_selector']; expected=[]
    for request,job in enumerate(plan['jobs'],1):
        if request>selected['request_ordinal']: break
        edges=['before','after'] if request<selected['request_ordinal'] else []
        if request==selected['request_ordinal'] and selected['phase']=='publish_ack':
            edges=['before'] if selected['edge']=='before' else ['before','after']
        for edge in edges:
            expected.append({'kind':job['kind'],'scope':'service','phase':'publish_ack','edge':edge,
                             'service_ordinal':plan['service_ordinal'],'request_ordinal':request,'occurrence':1,
                             'detail':{'pending':1 if edge=='before' else 0,'undelivered':0 if edge=='before' else 1}})
    actual=[e for e in events if e.get('phase')=='publish_ack']
    require(len(actual)==len(expected),'complete predeclared publish ACK history')
    for observed,wanted in zip(actual,expected):
        require(all(k in observed and type(observed[k]) is type(v) and observed[k]==v
                    for k,v in wanted.items() if k!='detail'),'exact publish ACK job/edge/occurrence order')
        exact_keys(observed['detail'],['pending','undelivered'])
        require(all(type(observed['detail'][k]) is int and observed['detail'][k]==v
                    for k,v in wanted['detail'].items()),'actual sequential publish ACK counts')


def crash_prefix_admission(recipe,plan,events,selected,capability,pre_snapshot):
    crash_publish_ack_admission(plan,events)
    files,sentinel,partial=preactor_facts(capability,pre_snapshot)
    bindings={'sentinel_bytes':sentinel,'original_main_first_chunk_bytes':min(65536,files[0]) if files[0] is not None else 0,
              'expected_export_bytes':len(CRASH_EXPORT_BYTES)}
    for predicate in recipe['selected_and_prior_predicates']:
        if 'detail' in predicate:
            require(pattern_value(predicate,selected,bindings,selected['detail']),"predeclared selected actual detail")
        elif 'prior' in predicate:
            expected=predicate['prior']
            require(any(all((k in e and pattern_value(v,e[k],bindings,e.get('detail',{}))) or
                            (k in e.get('detail',{}) and pattern_value(v,e['detail'][k],bindings,e['detail']))
                            for k,v in expected.items()) for e in events if canonical_u64(e['event_sequence'])<canonical_u64(selected['event_sequence'])),"predeclared successful prior operation")
        else: require(predicate=={'pre_release_roster':'one_complete_retained_and_associated_complete_work_no_sqlite'},"closed source predicate")
    recovery=[e for e in events if 'phase' in e and e['phase']=='recovery_copy']
    if recipe['required_call_prefix'] or any('pre_release_roster' in p for p in recipe['selected_and_prior_predicates']):
        # Derive request lengths solely from BEFORE-actor source inventory. No
        # observed requested/completed value enters mathematical expectations.
        model=expected_recovery_calls(sentinel_bytes=sentinel,files=files,existing_partial_intent_bytes=partial)
        cutoff=selected['occurrence'] if selected['phase']=='recovery_copy' else len(model)
        require(1<=cutoff<=len(model),"source-derived full-call cutoff")
        expected_rows=[]
        for expected in model[:cutoff]:
            for edge in ['before','after']:
                if selected['phase']=='recovery_copy' and expected['occurrence']==cutoff and edge=='after' and selected['edge']=='before': continue
                expected_rows.append((expected,edge))
        require(len(recovery)==len(expected_rows),"complete predeclared recovery call history, not odd/even inference")
        for actual,(expected,edge) in zip(recovery,expected_rows):
            require(actual['scope']=='recovery' and actual['kind']=='start' and actual['request_ordinal']==1
                    and actual['edge']==edge and actual['occurrence']==expected['occurrence'],"source exact recovery call/edge order")
            detail={k:v for k,v in expected.items() if k not in ['purpose','occurrence']}
            if edge=='before': detail['completed_bytes']=None; detail['win32_error']=None
            require(pattern_value(detail,actual['detail'],bindings,actual['detail']),"source-derived real requested/completed bytes and identity-bearing IO")
        for prefix in recipe['required_call_prefix']:
            wanted=[e for e in recovery if e['occurrence']==prefix['occurrence'] and e['edge']=='after']
            if not wanted and selected['edge']=='before' and prefix['occurrence']==selected['occurrence']: continue
            require(len(wanted)==1 and pattern_value({k:v for k,v in prefix.items() if k not in ['purpose','occurrence']},wanted[0]['detail'],bindings,wanted[0]['detail']),"literal source reference call prefix")
    return {'preactor_original_lengths':files,'sentinel_bytes':sentinel,'prior_partial_intent_bytes':partial,
            'source_call_model_sha256':digest(json_bytes(model)) if recovery and (recipe['required_call_prefix'] or selected['scope']=='qualification_copy') else None}


CRASH_HELD_PHASE_ROLES = [{'scenario': 'pre_begin', 'actor_in_scenario': 1, 'selector': {'request_ordinal': 2, 'kind': 'rename_player', 'scope': 'original', 'phase': 'before_begin', 'edge': 'before', 'occurrence': 1, 'service_ordinal': 1}, 'original_main': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED', 'original_wal': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED'}, {'scenario': 'before_commit', 'actor_in_scenario': 1, 'selector': {'request_ordinal': 2, 'kind': 'rename_player', 'scope': 'original', 'phase': 'before_commit', 'edge': 'before', 'occurrence': 1, 'service_ordinal': 1}, 'original_main': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED', 'original_wal': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED'}, {'scenario': 'after_commit', 'actor_in_scenario': 1, 'selector': {'request_ordinal': 2, 'kind': 'rename_player', 'scope': 'original', 'phase': 'after_commit', 'edge': 'after', 'occurrence': 1, 'service_ordinal': 1}, 'original_main': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED', 'original_wal': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED'}, {'scenario': 'publish_ack', 'actor_in_scenario': 1, 'selector': {'request_ordinal': 2, 'kind': 'rename_player', 'scope': 'service', 'phase': 'publish_ack', 'edge': 'before', 'occurrence': 1, 'service_ordinal': 1}, 'original_main': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED', 'original_wal': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED'}, {'scenario': 'wal_schema', 'actor_in_scenario': 1, 'selector': {'request_ordinal': 1, 'kind': 'start', 'scope': 'original', 'phase': 'after_commit', 'edge': 'after', 'occurrence': 1, 'service_ordinal': 1}, 'original_main': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED', 'original_wal': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED'}, {'scenario': 'interrupt_before_commit', 'actor_in_scenario': 1, 'selector': {'request_ordinal': 1, 'kind': 'start', 'scope': 'original', 'phase': 'before_commit', 'edge': 'before', 'occurrence': 1, 'service_ordinal': 1}, 'original_main': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED', 'original_wal': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED'}, {'scenario': 'interrupt_after_commit', 'actor_in_scenario': 1, 'selector': {'request_ordinal': 1, 'kind': 'start', 'scope': 'original', 'phase': 'after_commit', 'edge': 'after', 'occurrence': 1, 'service_ordinal': 1}, 'original_main': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED', 'original_wal': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED'}, {'scenario': 'pre_intent_read', 'actor_in_scenario': 1, 'selector': {'request_ordinal': 1, 'kind': 'start', 'scope': 'recovery', 'phase': 'recovery_copy', 'edge': 'after', 'occurrence': 2, 'service_ordinal': 1}, 'original_main': 'FULL_BYTE_HASH_REQUIRED', 'original_wal': 'FULL_BYTE_HASH_REQUIRED'}, {'scenario': 'intent_before_write', 'actor_in_scenario': 1, 'selector': {'request_ordinal': 1, 'kind': 'start', 'scope': 'recovery', 'phase': 'recovery_copy', 'edge': 'before', 'occurrence': 3, 'service_ordinal': 1}, 'original_main': 'FULL_BYTE_HASH_REQUIRED', 'original_wal': 'FULL_BYTE_HASH_REQUIRED'}, {'scenario': 'copy_after_read', 'actor_in_scenario': 1, 'selector': {'request_ordinal': 1, 'kind': 'start', 'scope': 'recovery', 'phase': 'recovery_copy', 'edge': 'after', 'occurrence': 6, 'service_ordinal': 1}, 'original_main': 'FULL_BYTE_HASH_REQUIRED', 'original_wal': 'FULL_BYTE_HASH_REQUIRED'}, {'scenario': 'copy_after_write', 'actor_in_scenario': 1, 'selector': {'request_ordinal': 1, 'kind': 'start', 'scope': 'recovery', 'phase': 'recovery_copy', 'edge': 'after', 'occurrence': 7, 'service_ordinal': 1}, 'original_main': 'FULL_BYTE_HASH_REQUIRED', 'original_wal': 'FULL_BYTE_HASH_REQUIRED'}, {'scenario': 'work_before_sqlite', 'actor_in_scenario': 1, 'selector': {'request_ordinal': 1, 'kind': 'start', 'scope': 'qualification_copy', 'phase': 'before_open', 'edge': 'before', 'occurrence': 1, 'service_ordinal': 1}, 'original_main': 'FULL_BYTE_HASH_REQUIRED', 'original_wal': 'FULL_BYTE_HASH_REQUIRED'}, {'scenario': 'two_partial_limit', 'actor_in_scenario': 1, 'selector': {'request_ordinal': 1, 'kind': 'start', 'scope': 'recovery', 'phase': 'recovery_copy', 'edge': 'after', 'occurrence': 7, 'service_ordinal': 1}, 'original_main': 'FULL_BYTE_HASH_REQUIRED', 'original_wal': 'FULL_BYTE_HASH_REQUIRED'}, {'scenario': 'two_partial_limit', 'actor_in_scenario': 2, 'selector': {'request_ordinal': 1, 'kind': 'start', 'scope': 'recovery', 'phase': 'recovery_copy', 'edge': 'after', 'occurrence': 9, 'service_ordinal': 1}, 'original_main': 'FULL_BYTE_HASH_REQUIRED', 'original_wal': 'FULL_BYTE_HASH_REQUIRED'}, {'scenario': 'export_after_write', 'actor_in_scenario': 1, 'selector': {'request_ordinal': 2, 'kind': 'export_player', 'scope': 'export', 'phase': 'export_write', 'edge': 'after', 'occurrence': 1, 'service_ordinal': 1}, 'original_main': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED', 'original_wal': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED'}, {'scenario': 'export_after_flush', 'actor_in_scenario': 1, 'selector': {'request_ordinal': 2, 'kind': 'export_player', 'scope': 'export', 'phase': 'export_flush', 'edge': 'after', 'occurrence': 1, 'service_ordinal': 1}, 'original_main': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED', 'original_wal': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED'}, {'scenario': 'export_after_move', 'actor_in_scenario': 1, 'selector': {'request_ordinal': 2, 'kind': 'export_player', 'scope': 'export', 'phase': 'export_move', 'edge': 'after', 'occurrence': 1, 'service_ordinal': 1}, 'original_main': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED', 'original_wal': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED'}, {'scenario': 'delete_before_row', 'actor_in_scenario': 1, 'selector': {'kind': 'delete_player', 'scope': 'original', 'phase': 'row_write', 'edge': 'before', 'request_ordinal': 2, 'occurrence': 1, 'service_ordinal': 1}, 'original_main': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED', 'original_wal': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED'}, {'scenario': 'delete_after_row', 'actor_in_scenario': 1, 'selector': {'kind': 'delete_player', 'scope': 'original', 'phase': 'row_write', 'edge': 'after', 'request_ordinal': 2, 'occurrence': 1, 'service_ordinal': 1}, 'original_main': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED', 'original_wal': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED'}, {'scenario': 'delete_after_commit', 'actor_in_scenario': 1, 'selector': {'kind': 'delete_player', 'scope': 'original', 'phase': 'after_commit', 'edge': 'after', 'request_ordinal': 2, 'occurrence': 1, 'service_ordinal': 1}, 'original_main': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED', 'original_wal': 'SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED'}]


def admit_crash_metadata(value,path):
    exact_keys(value,['attributes','links','file_type','final_path','volume_serial','file_id','bytes'])
    actual_int(value['attributes'],0,0xffffffff,'actual file attributes DWORD')
    require(not value['attributes']&0x410,'ordinary nonreparse non-directory crash file')
    require(type(value['links']) is int and value['links']==1,'actual single-link crash file')
    require(type(value['file_type']) is int and value['file_type']==1,'actual FILE_TYPE_DISK')
    require(type(path) is str and ntpath.isabs(path) and type(value['final_path']) is str
            and value['final_path'].startswith('\\\\?\\') and not value['final_path'].startswith('\\\\?\\UNC\\')
            and value['final_path'][4:].casefold()==path.casefold(),'exact physical normalized crash pathname')
    canonical_u64(value['volume_serial'])
    require(type(value['file_id']) is str and re.fullmatch('[0-9a-f]{32}',value['file_id']),'actual native file ID')
    actual_int(value['bytes'],0,512*1024*1024,'bounded actual native size')
    return value


def crash_file_row(relative,metadata,sha,error,allow_denied):
    require(type(relative) is str and relative and '\\' not in relative and not relative.startswith('/')
            and all(part not in ['','.','..'] for part in relative.split('/')),'closed relative crash file path')
    require(type(allow_denied) is bool,'source-derived denial eligibility BOOL')
    actual_int(error,0,0xffffffff,'actual content-open DWORD')
    if sha is None:
        require(allow_denied and error==32 and relative in ['players.lock','players.sqlite3','players.sqlite3-wal'],
                'no arbitrary unreadable crash file waiver')
        observation='metadata_read_denied'
    else:
        require(type(sha) is str and HEX.fullmatch(sha) and error==0,'complete actual held hash')
        observation='content_sha256'
    if relative=='players.lock': require(metadata['bytes']==0,'actual held lock size zero')
    return {'path':relative,'bytes':metadata['bytes'],'sha256':sha,'observation':observation,
            'native_metadata':metadata,'read_open_win32_error':error}


def crash_phase_role(scenario,actor_ordinal,recipe,plan,selected):
    actual_int(actor_ordinal,1,2,'fixed actor ordinal')
    rows=[row for row in CRASH_HELD_PHASE_ROLES if row['scenario']==scenario and row['actor_in_scenario']==actor_ordinal]
    require(len(rows)==1,'exact fixed twenty-row crash phase role')
    row=rows[0]; wanted=recipe['plan_template']['crash_selector']
    require(plan['crash_selector']==wanted==row['selector'],'complete source-fixed plan selector')
    require(all(k in selected and type(selected[k]) is type(v) and selected[k]==v for k,v in wanted.items()),
            'actual selected callback matches exact fixed phase role')
    return row


def crash_snapshot(api,root,phase,role):
    """Private typed crash evidence; metadata is never presented as held bytes."""
    require(phase in ['preactor','held','after-death-before-reopen'],'closed crash snapshot phase')
    require(role in CRASH_HELD_PHASE_ROLES,'source-fixed snapshot phase role')
    root=ordinary(root,True); rows=[]; total=0
    def visit(directory):
        nonlocal total
        directory_handle,identity=api.crash_directory_lease(directory)
        try:
            for entry in sorted(os.scandir(directory),key=lambda x:x.name):
                observed=os.stat(entry.path,follow_symlinks=False)
                require(not stat.S_ISLNK(observed.st_mode) and not getattr(observed,'st_file_attributes',0)&0x400,
                        'crash snapshot nonreparse')
                if stat.S_ISDIR(observed.st_mode): visit(Path(entry.path))
                else:
                    require(stat.S_ISREG(observed.st_mode) and observed.st_nlink==1,'crash snapshot ordinary single-link')
                    relative=Path(entry.path).relative_to(root).as_posix()
                    allowed=phase=='held' and (relative=='players.lock' or (relative=='players.sqlite3'
                        and role['original_main']=='SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED')
                        or (relative=='players.sqlite3-wal'
                        and role['original_wal']=='SQLITE_OWNED_METADATA_AND_EXACT_READ_DENIAL_ALLOWED'))
                    row=api.crash_file(entry.path,relative,allowed); total+=row['bytes']
                    require(len(rows)<4096 and total<=512*1024*1024,'bounded complete crash inventory')
                    rows.append(row)
            require(api.identity(directory_handle,directory,True)==identity,'crash directory identity continuity')
        finally: api.close(directory_handle)
    visit(root)
    return {'schema':'LocalPlayersCrashFileSnapshot/v1','phase':phase,'phase_role':role,'files':rows}


def crash_content_rows(snapshot,names=None):
    rows=snapshot['files']
    if names is not None: rows=[r for r in rows if r['path'] in names]
    require(all(r['observation']=='content_sha256' and type(r['sha256']) is str for r in rows),
            'complete content rows required; metadata is not byte proof')
    return [{'path':r['path'],'bytes':r['bytes'],'sha256':r['sha256']} for r in rows]


def crash_snapshot_relations(pre,held,after=None):
    require(pre['phase']=='preactor' and held['phase']=='held' and pre['phase_role']==held['phase_role'],
            'ordered same-role preactor/held inventory')
    if after is not None:
        require(after['phase']=='after-death-before-reopen' and after['phase_role']==held['phase_role'],
                'full after-death inventory belongs to same phase role')
        crash_content_rows(after)
    crash_content_rows(pre)
    maps=[{r['path']:r for r in s['files']} for s in [pre,held]+([after] if after is not None else [])]
    require(all(len(m)==len(s['files']) for m,s in zip(maps,[pre,held]+([after] if after is not None else []))),
            'unique full crash inventory paths')
    prior_absent=pre['phase_role']['scenario']=='wal_schema'
    require(('players.lock' not in maps[0])==prior_absent,'only fresh WAL fixture lacks prior lock')
    require('players.lock' in maps[1] and (after is None or 'players.lock' in maps[2]),'actual held/death lock roster')
    if not prior_absent: require(maps[0]['players.lock']['bytes']==0,'actual preactor lock size')
    continuity=[]
    for name in ['players.lock','players.sqlite3']:
        present=[(index,m[name]) for index,m in enumerate(maps) if name in m]
        if name=='players.sqlite3':
            require((name not in maps[0])==prior_absent,'only fresh WAL fixture lacks prior MAIN')
            require(name in maps[1] and (after is None or name in maps[2]),'held/death original MAIN required')
        require(present,'actual identity observation required')
        identities=[{k:r['native_metadata'][k] for k in ['volume_serial','file_id','final_path']} for _,r in present]
        require(all(identity==identities[0] for identity in identities),'physical identity continuity across actual observations')
        if name=='players.lock':require(all(r['bytes']==0 for _,r in present),'observed lock zero at each phase')
        continuity.append({'path':name,'preactor_presence':'absent' if name not in maps[0] else 'present',
            'identity_origin':'newly_observed_held' if name not in maps[0] else 'preactor',
            'native_identity_continuity':True,'observed_sizes':[r['bytes'] for _,r in present]})
    # Only actually observed original WAL identities participate; absence is not a hash.
    wal_present=[(index,m['players.sqlite3-wal']) for index,m in enumerate(maps) if 'players.sqlite3-wal' in m]
    if wal_present:
        wal_identities=[{k:r['native_metadata'][k] for k in ['volume_serial','file_id','final_path']} for _,r in wal_present]
        require(all(identity==wal_identities[0] for identity in wal_identities),'original WAL physical identity continuity across actual observations')
        continuity.append({'path':'players.sqlite3-wal',
            'preactor_presence':'present' if 'players.sqlite3-wal' in maps[0] else 'absent',
            'identity_origin':'preactor' if 'players.sqlite3-wal' in maps[0] else
                'newly_observed_held' if 'players.sqlite3-wal' in maps[1] else 'newly_observed_after_death',
            'native_identity_continuity':True,
            'observed_phases':[['preactor','held','after-death-before-reopen'][index] for index,_ in wal_present],
            'observed_sizes':[r['bytes'] for _,r in wal_present]})
    if held['phase_role']['original_main']=='FULL_BYTE_HASH_REQUIRED':
        original=crash_content_rows(pre,NAMES)
        require(crash_content_rows(held,NAMES)==original,'seven full original4 preactor/held byte proofs')
        if after is not None:require(crash_content_rows(after,NAMES)==original,'seven full original4 preactor/held/death byte proofs')
    if after is None:return {'identity_observations':continuity,'after_death_observed':False}
    opaque=[r['path'] for r in held['files'] if r['observation']=='metadata_read_denied']
    require(all(path in maps[2] for path in opaque),'opaque observations require full after-death content')
    comparable=[r for r in held['files'] if r['observation']=='content_sha256']
    comparable_equal=all(r['path'] in maps[2] and all(r[k]==maps[2][r['path']][k]
                          for k in ['bytes','sha256']) for r in comparable)
    roster_equal=set(maps[1])==set(maps[2])
    return {'schema':'LocalPlayersCrashInventoryComparison/v1','identity_observations':continuity,
        'after_death_observed':True,'held_to_death_roster_equal':roster_equal,
        'comparable_content_files':len(comparable),'comparable_content_equal':comparable_equal,
        'noncomparable_held_content_paths':opaque,
        'held_to_death_inventory_equal':None if opaque else roster_equal and comparable_equal,
        'scope':'Metadata identity/size observations do not establish held byte equality.'}


def admit_crash_death(terminal):
    require(terminal.get('schema')=='LocalPlayersNativeChildTerminal/v1','actual terminal schema')
    require(all(terminal.get(k) is True for k in ['exit_observed','drained','qualified_process'])
            and terminal.get('timed_out') is False and terminal.get('error') is None,'actual joined/drained qualified death')
    require(type(terminal.get('exit_code')) is int and terminal['exit_code']==86
            and type(terminal.get('expected_exit')) is int and terminal['expected_exit']==86,'actual expected86 only')
    elapsed=terminal.get('elapsed_ms')
    require(type(elapsed) in [int,float] and 0<=elapsed<=185000,'actual original crash operation deadline')
    return True


def admit_crash_reopen(actor,terminal):
    admit_crash_death(terminal)
    gate=actor.get('before_reopen')
    exact_keys(gate,['schema','phase','actual_terminal','full_after_death_inventory','raw_wal_required','raw_wal_complete'])
    require(gate['schema']=='LocalPlayersCrashBeforeReopen/v1' and gate['phase']=='after-death-before-reopen'
            and gate['actual_terminal']==actor['actual_process']['terminal']
            and gate['full_after_death_inventory']==actor['after_death_files'],'actual death and inventory precede reopen')
    require(type(gate['raw_wal_required']) is bool and type(gate['raw_wal_complete']) is bool
            and gate['raw_wal_complete'] is True
            and (actor['wal_schema'] is not None)==gate['raw_wal_required'],'required raw WAL observation before reopen')
    return True



def raw_wal_schema(root):
    main=ordinary(root/'players.sqlite3').read_bytes(); wal=ordinary(root/'players.sqlite3-wal').read_bytes()
    require(100<=len(main)<=268435456 and 32<=len(wal)<=67108864 and (len(wal)-32)%4120==0,"finite complete actual WAL")
    def word(buf,at,big=True):return int.from_bytes(buf[at:at+4],'big' if big else 'little')
    magic=word(wal,0); require(magic in [0x377f0682,0x377f0683] and word(wal,4)==3007000 and word(wal,8)==4096,"pinned actual WAL header")
    checksum=[0,0]; big=bool(magic&1)
    def add(at,size):
        for i in range(at,at+size,8):
            checksum[0]=(checksum[0]+word(wal,i,big)+checksum[1])&0xffffffff
            checksum[1]=(checksum[1]+word(wal,i+4,big)+checksum[0])&0xffffffff
    add(0,24); require(checksum==[word(wal,24),word(wal,28)],"actual WAL header checksum")
    pending=committed=None; commits=0
    for at in range(32,len(wal),4120):
        require(word(wal,at)>0 and wal[at+8:at+16]==wal[16:24],"actual WAL frame salts/page")
        add(at,8);add(at+24,4096);require(checksum==[word(wal,at+16),word(wal,at+20)],"all actual frame checksums")
        if word(wal,at)==1:pending=at+24
        if word(wal,at+4):commits+=1;committed=pending
    require(commits and committed is not None and main[:16]==b'SQLite format 3\0' and wal[committed:committed+16]==main[:16]
            and word(main,40)==0 and word(wal,committed+40)>0,"actual committed page1 with stale main schema cookie")
    return {'kind':'wal_schema','frames':(len(wal)-32)//4120,'commits':commits,'main_schema_cookie':word(main,40),'committed_schema_cookie':word(wal,committed+40)}


def run_crash_actor(api,auth,capability,recipe,scenario,actor_ordinal,evidence):
    plan_value=json.loads(json.dumps(recipe['plan_template']))
    require(plan_value['nonce']=={'root_binding':'fresh_nonce'},"only admitted source template substitution")
    plan_value['nonce']=capability['value']['nonce']
    plan=write_new(evidence/'actor-plan.json',json_bytes(plan_value)); nonce=plan_value['nonce']
    role=crash_phase_role(scenario,actor_ordinal,recipe,plan_value,plan_value['crash_selector'])
    pre_inventory=crash_snapshot(api,Path(capability['value']['root']),'preactor',role)
    pre_snapshot=crash_content_rows(pre_inventory)
    write_new(evidence/'preactor-files.json',json_bytes(pre_inventory))
    pipes=ActorPipes(api,nonce,evidence); executable=auth['children']['crash_actor']; parent=api.process(os.getpid())
    context=write_new(evidence/'actor-context.json',json_bytes({'schema':'LocalPlayersCrashActorContext/v1','role':'crash_actor',
        'source_root':auth['source_root'],'proof_parent':capability['value']['parent'],'parent_pid':parent['pid'],
        'parent_creation_filetime':parent['creation_filetime'],'actor_sha256':executable['sha256'],
        'capability_sha256':capability['descriptor']['sha256'],'plan_sha256':plan['sha256'],
        'stdin_pipe':pipes.names[0],'stdout_pipe':pipes.names[1]}))
    child=None; leases=RetainedFiles(api)
    try:
        for pin in [context,plan,capability['descriptor']]:leases.add(pin)
        child=ObservedChild(api,executable,child_arguments(context,capability['descriptor'],plan),auth['build_root'],evidence,'crash-actor')
        pipes.connect(child); ready=pipes.read_frame(child)
        admit_ready(ready,nonce,child.pid,'crash_actor',capability['descriptor']['sha256'],plan['sha256'])
        events=[]; reservations=[]; order=[]; counters={}; selected=[]
        while True:
            frame=pipes.read_frame(child,plan_value['maximum_actual_events']+2)
            if frame.get('type')=='ARRIVED': break
            require(len(order)<plan_value['maximum_actual_events'],"one shared actual event/reservation capacity")
            if frame.get('type')=='RESERVATION':
                admit_reservation(frame,nonce,child.pid,plan_value['service_ordinal'],len(reservations)+1)
                reservations.append(frame);order.append({'type':'RESERVATION','sequence':len(reservations)})
            else:
                selector=admit_event(frame,nonce,child.pid,plan_value['service_ordinal'],len(events)+1,plan_value['sites'],counters)
                events.append(frame['event']);order.append({'type':'EVENT','sequence':len(events)})
                expected=plan_value['crash_selector']
                if all(selector.get(k)==v and type(selector.get(k)) is type(v) for k,v in expected.items()): selected.append(frame['event'])
        exact_keys(frame,['type','nonce','pid','action_ordinal','event_sequence'])
        require(frame['type']=='ARRIVED' and frame['nonce']==nonce and type(frame['pid']) is int and frame['pid']==child.pid
                and type(frame['action_ordinal']) is int and frame['action_ordinal']==1 and len(selected)==1
                and canonical_u64(frame['event_sequence'],True)==canonical_u64(selected[0]['event_sequence'],True),"actual held unique source-selected callback")
        premise=crash_prefix_admission(recipe,plan_value,events,selected[0],capability,pre_snapshot)
        require(crash_phase_role(scenario,actor_ordinal,recipe,plan_value,selected[0])==role,
                'actual held callback has source-fixed snapshot permissions')
        child.live()
        held_inventory=crash_snapshot(api,Path(capability['value']['root']),'held',role)
        crash_snapshot_relations(pre_inventory,held_inventory)
        write_new(evidence/'held-files.json',json_bytes(held_inventory))
        # The actual source-held worker remains live until this exact release.
        child.live(); leases.recheck(); pipes.release(child)
        process=child.finish(45+120+20,86); check_logs(process,False)
        admit_crash_death(load_json(process['terminal']['path'])[0])
        pipes.close();leases.close()
        # All complete bytes and raw WAL parsing occur after observed86/drain,
        # while the independent reopen process has not even been created.
        after=crash_snapshot(api,Path(capability['value']['root']),'after-death-before-reopen',role)
        comparison=crash_snapshot_relations(pre_inventory,held_inventory,after)
        after_pin=write_new(evidence/'after-death-files.json',json_bytes(after))
        wal_required=selected[0]['kind']=='start' and selected[0]['phase']=='after_commit' and not any(r['path'] in NAMES for r in pre_snapshot)
        wal=raw_wal_schema(Path(capability['value']['root'])) if wal_required else None
        gate={'schema':'LocalPlayersCrashBeforeReopen/v1','phase':'after-death-before-reopen',
            'actual_terminal':process['terminal'],'full_after_death_inventory':after_pin,
            'raw_wal_required':wal_required,'raw_wal_complete':True}
        return {'context':context,'plan':plan,'ready':ready,'arrived':frame,'actual_process':process,
            'raw_frames':native_pin(evidence/'actor.frames.ndjson'),'events':len(events),'reservations':len(reservations),
            'stream_order_sha256':digest(json_bytes(order)),'selected_actual_event':selected[0],'predeclared_premise':premise,
            'preactor_files':native_pin(evidence/'preactor-files.json'),'held_files':native_pin(evidence/'held-files.json'),
            'after_death_files':after_pin,'wal_schema':wal,'before_reopen':gate,
            'inventory_comparison':comparison,
            'held_to_death_inventory_equal':comparison['held_to_death_inventory_equal'],
            'scope':'Injected source-selected process death86; not graceful service join or hardware power loss.'}
    finally:
        if child is not None and child.process_handle is not None:
            api.ok(api.k.TerminateJobObject(child.job,125),'failed crash observation actual termination')
            try:child.finish(0)
            except ValueError:pass
        pipes.close();leases.close()


def run_crash_table(api,auth,evidence):
    require(native_pin(Path(auth['source_root'])/'tests/persistence/local_players/native.cpp')['sha256']==CRASH_NATIVE_SOURCE_SHA,"exact reviewed nineteen-scenario native driver, no old unavailable stub")
    require(native_pin(Path(auth['source_root'])/'tests/persistence/local_players/crash_actor.cpp')['sha256']==CRASH_ACTOR_SOURCE_SHA,"exact reviewed delete-capable actor source")
    result={'root_capabilities':[],'invocations':[],'driver_results':[],'actors':[],'coverage':{'scenario_ids':[],
        'actor_count':0,'checks':0,'actual_events':0,'scope':'Entire nineteen fixed recipes; retained-directory partial-delete and other deferred failure gates remain explicit.'}}
    for recipe in CRASH_RECIPES['recipes']:
        case=fresh_evidence(evidence,recipe['id']); cap=prepare_case_root(api,auth,case,recipe['id']); result['root_capabilities'].append(cap)
        stages=recipe['driver_stages']; require(len(stages)==2,"one prepare then distinct reopen/inspect per fixed scenario")
        def stage(name):
            plan={'schema':'LocalPlayersNativeTestPlan/v1','nonce':cap['value']['nonce'],'first_service_ordinal':1,
                  'maximum_actual_events':16384,'suite':'crash','cases':[name]}
            observed=run_driver(api,auth,'crash',cap,fresh_evidence(case,name),plan)
            result['invocations'].append(observed); result['driver_results'].append(observed['observed_result'])
            result['coverage']['checks']+=observed['observed_result']['checks'];result['coverage']['actual_events']+=observed['observed_result']['actual_events']
            return observed
        prepared=stage(stages[0])
        actors=[]
        for actor_ordinal,item in enumerate(recipe['actors'],1):
            actor=run_crash_actor(api,auth,cap,item,recipe['id'],actor_ordinal,fresh_evidence(case,'injected-crash'))
            actors.append(actor);result['actors'].append(actor);result['coverage']['actor_count']+=1
        # All actual86/closed transport and drained tree receipts precede this
        # separate process creation. A joined prepare or inspector alone cannot
        # stand in for the actor's actual death.
        for actor in actors:
            admit_actual_pin(actor['actual_process']['terminal'])
            admit_actual_pin(actor['after_death_files'])
            admit_crash_reopen(actor,load_json(actor['actual_process']['terminal']['path'])[0])
        reopened=stage(stages[1]); require(all(load_json(a['actual_process']['terminal']['path'])[0]['process']['pid']!=load_json(reopened['process']['terminal']['path'])[0]['process']['pid'] for a in actors),"different reopen process")
        if recipe['id']=='wal_schema':
            actual=[r for r in reopened['observed_result']['observations'] if r.get('kind')=='wal_schema']
            require(len(actual)==1 and actual[0]==actors[0]['wal_schema'],"independent raw Root/native WAL witness agreement")
        result['coverage']['scenario_ids'].append(recipe['id'])
    require(result['coverage']['scenario_ids']==CRASH_SCENARIO_IDS and result['coverage']['actor_count']==20,"complete fixed nineteen/20 actor roster")
    return result

def load_link_plan_index(path, digest_path, argv):
    """Select an independently frozen plan by exact argv, never mint from argv.

    Root's index is integrity-pinned before the compiler build starts. Expected
    commands must originate in the reviewed Root policy/configuration producer;
    neither a launcher observation nor a compile database shell string supplies
    expected arguments. Every referenced plan is checked before selection.
    """
    expected_sha, digest_pin = resolve_plan_digest(path, digest_file=digest_path)
    index, raw = load_json(path, expected_sha)
    exact_keys(index, ["schema", "source_root", "build_root", "entries"])
    require(index["schema"] == "LocalPlayersLinkPlanIndex/v1", "compile plan index schema")
    source, build = ordinary(index["source_root"], True), ordinary(index["build_root"], True)
    require(source != build and index["source_root"] == str(source)
            and index["build_root"] == str(build), "canonical index roots")
    require(type(index["entries"]) is list and 1 <= len(index["entries"]) <= 64,
            "bounded nonempty compile plan index")
    matches, commands, paths = [], set(), set()
    for pin in index["entries"]:
        exact_keys(pin, ["path", "bytes", "sha256"])
        require(type(pin["bytes"]) is int and 0 < pin["bytes"] <= MAX_JSON
                and type(pin["sha256"]) is str and HEX.fullmatch(pin["sha256"]), "typed compile plan pin")
        candidate = ordinary(pin["path"])
        require(candidate.is_relative_to(build) and str(candidate) == pin["path"]
                and pin["path"] not in paths, "unique contained compile plan")
        paths.add(pin["path"])
        require(file_pin(candidate) == pin, "frozen compile plan pin drift")
        plan, _ = load_json(candidate, pin["sha256"])
        exact_keys(plan, "schema kind source_root build_root cwd argv tools inputs outputs".split())
        require(plan["schema"] == "LocalPlayersInvocationPlan/v1" and plan["kind"] == "link"
                and plan["source_root"] == str(source) and plan["build_root"] == str(build), "compile plan roots/kind")
        command = plan["argv"]
        require(type(command) is list and command and all(type(a) is str and "\0" not in a for a in command),
                "closed expected compile argv")
        key = (plan["cwd"], tuple(command))
        require(key not in commands, "duplicate expected compile command")
        commands.add(key)
        if command == argv and plan["cwd"] == os.getcwd():
            matches.append(pin)
    require(len(matches) == 1, "actual compiler argv has no unique independently admitted plan")
    require(file_pin(path)["sha256"] == digest(raw)
            and resolve_plan_digest(path, digest_file=digest_path) == (expected_sha, digest_pin),
            "index admission drift")
    return matches[0], file_pin(path), digest_pin

def launch_planned_link(index_path, digest_path, receipt_root, argv):
    pin, index_pin, digest_pin = load_link_plan_index(index_path, digest_path, argv)
    # Keep index evidence separate from command/compiled identity to avoid a
    # plan/index hash cycle. The selected original plan is pinned by launch().
    parent = ordinary(receipt_root, True)
    evidence = parent / ("link-selection-" + uuid.uuid4().hex)
    evidence.mkdir()
    before = {"schema": "LocalPlayersLinkPlanSelection/v1", "index": index_pin,
              "digest_file": digest_pin, "selected_plan": pin, "argv": argv,
              "cwd": os.getcwd(), "launcher": file_pin(__file__)}
    write_new(evidence / "before.json", json_bytes(before))
    code, error = None, None
    try:
        code = launch("link", pin["path"], pin["sha256"], receipt_root, argv)
        require(file_pin(index_path) == index_pin and file_pin(digest_path) == digest_pin
                and file_pin(pin["path"]) == pin, "compile index changed during invocation")
    except (OSError, ValueError, KeyError, TypeError, UnicodeError) as exception:
        error = type(exception).__name__ + ": " + str(exception)
    write_new(evidence / "terminal.json", json_bytes({
        "schema": "LocalPlayersLinkPlanSelectionTerminal/v1", "before": file_pin(evidence / "before.json"),
        "selected_plan": pin, "exit_code": code, "error": error,
        "qualified_selection": code == 0 and error is None}))
    return 0 if code == 0 and error is None else 1

def argument_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="mode", required=True)
    p = sub.add_parser("launch-planned-compile")
    p.add_argument("--plan-index", required=True); p.add_argument("--plan-index-digest-file", required=True)
    p.add_argument("--receipt-root", required=True); p.add_argument("argv", nargs=argparse.REMAINDER)
    for mode in ["launch-compile", "launch-link"]:
        p = sub.add_parser(mode); p.add_argument("--plan", required=True)
        integrity = p.add_mutually_exclusive_group(required=True)
        integrity.add_argument("--plan-sha256"); integrity.add_argument("--plan-digest-file")
        p.add_argument("--receipt-root", required=True); p.add_argument("argv", nargs=argparse.REMAINDER)
    p = sub.add_parser("verify-compile"); p.add_argument("--compile-database", required=True); p.add_argument("--invocation", required=True)
    p.add_argument("--source", required=True); p.add_argument("--object", required=True)
    p = sub.add_parser("verify-archive"); p.add_argument("--archive", required=True); p.add_argument("--object", required=True)
    p = sub.add_parser("verify-link"); p.add_argument("--invocation", required=True); p.add_argument("--archive", required=True)
    p.add_argument("--object", required=True); p.add_argument("--dll", required=True); p.add_argument("--map", required=True)
    for mode in ["emit-header", "verify-header-compile"]:
        p = sub.add_parser(mode); p.add_argument("--identity-manifest", required=True); p.add_argument("--identity-manifest-sha256", required=True)
        if mode == "emit-header":
            p.add_argument("--output", required=True)
        else:
            p.add_argument("--header", required=True); p.add_argument("--invocation", required=True)
    p = sub.add_parser("prepare-test-root"); p.add_argument("--authorization", required=True)
    p.add_argument("--authorization-sha256", required=True)
    for mode in ['native-checks','bridge-checks']:
        p=sub.add_parser(mode)
        for name in ['authorization','authorization-sha256','test-build','test-build-sha256','ctest','ctest-sha256']:
            p.add_argument('--'+name,required=True)
        if mode=='bridge-checks':
            for name in ['native-checks','native-checks-sha256','godot','godot-sha256']:
                p.add_argument('--'+name,required=True)
    p=sub.add_parser('ctest')
    p.add_argument('--case',choices=['store','service','windows','crash'],required=True)
    for name in ['executable','proof-root','execution-authorization']:
        p.add_argument('--'+name,required=True)
    p.add_argument('--suite',choices=['store','crash']); p.add_argument('--crash-actor'); p.add_argument('--lock-actor')
    p=sub.add_parser('launch-planned-link')
    for name in ['plan-index','plan-index-digest-file','receipt-root']: p.add_argument('--'+name,required=True)
    p.add_argument('argv',nargs=argparse.REMAINDER)
    return parser


def main():
    args = argument_parser().parse_args()
    try:
        if args.mode in ['native-checks','bridge-checks','ctest']:
            result={'native-checks':native_checks,'bridge-checks':bridge_checks,'ctest':ctest_case}[args.mode](args)
            print(json.dumps(result,ensure_ascii=False,allow_nan=False))
            return 0
        if args.mode == 'launch-planned-link':
            argv=args.argv[1:] if args.argv[:1]==['--'] else args.argv
            return launch_planned_link(args.plan_index,args.plan_index_digest_file,args.receipt_root,argv)
        if args.mode == "launch-planned-compile":
            argv = args.argv[1:] if args.argv[:1] == ["--"] else args.argv
            return launch_planned_compile(args.plan_index, args.plan_index_digest_file, args.receipt_root, argv)
        if args.mode.startswith("launch-"):
            argv = args.argv[1:] if args.argv[:1] == ["--"] else args.argv
            return launch(args.mode.removeprefix("launch-"), args.plan, args.plan_sha256, args.receipt_root, argv, args.plan_digest_file)
        if args.mode == "prepare-test-root":
            result = prepare_native_test_root(args.authorization, args.authorization_sha256)
        elif args.mode == "emit-header":
            raw, identity = identity_header(args.identity_manifest, args.identity_manifest_sha256)
            require(Path(os.path.abspath(args.output)) == ordinary(identity["build_root"], True) / "local-players-generated/compiled_identity.hpp", "predeclared build header location")
            result = {"identity_manifest": file_pin(args.identity_manifest), "generated_header": write_new(args.output, raw),
                      "scope": "precompile header only; CTest/native/storage qualification NOT implemented"}
        elif args.mode == "verify-compile":
            result = match_compile_database(args.compile_database, args.invocation, args.source, args.object)
        elif args.mode == "verify-archive":
            result = sqlite_archive_witness(args.archive, args.object)
        elif args.mode == "verify-link":
            result = link_inclusion_witness(args.invocation, args.archive, args.object, args.dll, args.map)
        else:
            result = verify_header_compile(args.invocation, args.identity_manifest, args.identity_manifest_sha256, args.header)
        print(json.dumps(result, ensure_ascii=False, allow_nan=False))
        return 0
    except (OSError, ValueError, KeyError, TypeError, UnicodeError, struct.error) as error:
        print("LOCAL PLAYERS BUILD WITNESS REJECTED: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
