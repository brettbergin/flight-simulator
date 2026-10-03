# Native Windows export proof

This is the bounded [#15](https://github.com/brettbergin/flight-simulator/issues/15)
integration proof. It uses the accepted v1 native contracts and an original,
uncalibrated synthetic aircraft. It is not a playable simulator or a C172S model.
See [the evidence record](../../docs/evidence/P1/native-export.md).

## Reproduce

Use the [pinned bootstrap](../bootstrap/README.md), Node and Python 3.12.5 on
Windows x64 with an installed compatible MSVC 2022 release toolchain. These tools
are build/proof dependencies; the resulting application does not invoke them.

```powershell
npm ci --ignore-scripts --prefix schemas
./tools/bootstrap/build.ps1 -Python python -WithGodot -WithExportTemplates
node tests/export/make-initializer.mjs --check
node --test tests/export/runtime.test.mjs
./tools/export/proof.ps1 -Python python
python tools/export/source-bundle.py --output .local/export-source-fresh
python tests/export/source-integrity.py .local/export-source-fresh/source
$source = Get-Content .local/export-source-fresh/source-bundle-evidence.json -Raw | ConvertFrom-Json
./tools/export/replacement.ps1 -SourceArchive .local/export-source-fresh/jsbsim-1.3.1-library-source.zip -SourceSHA256 $source.source_archive_sha256 -Python python
node tools/export/package.mjs .local/export-source-fresh
```

Choose a new source output directory for each generation. The generator refuses
to reuse one. `latest-run.json` under `.local/export-proof/` locates the actual
isolated project, portable payload, relocated copies and evidence directory.
On Linux run `proof.ps1 -EditorOnly`; Windows export/replacement gates are not
claimed from a Linux editor load. CI runs both editor proofs and the full Windows
pipeline. Only evidence is uploaded; no release or simulator binaries are published.

The exact engine and export template pins remain Godot 4.7.2. The bridge consumes
the pinned godot-cpp 4.5 standard-precision ABI and C++20 native API. The compiled
host/bridge/JSBSim use x64 and dynamic release MSVC CRT, with exact compiler patches
in the build manifest. No debug CRT, tool DLL or copied Windows OS component is staged.

## What the scene exercises

`app/proof/proof.gd` constructs `FlightProofSession`, loads a bounded private
initializer transport, submits a v1 `ControlCommand`, reads full v1 snapshots and
operational events, pauses at tick 121, and closes. The source/authority is fixed
to registered pilot controls. Wire uint64 values stay canonical decimal strings,
including sequence `9007199254740993`. Unknown fields, versions, nonfinite axes,
numeric sequence and authority elevation reject before native submission.

`FlightProofSession` exposes `open_session`, `submit`, `session_control`,
`step_fixed` and `close`. Replies contain explicit success/error fields and
versioned native JSON samples; no Godot or JSBSim object escapes the boundary.
The single worker creates, uses and destroys the authoritative native `Session`.
Calls are synchronous and step batches bounded to 1–32; this is an integration
proof facade, not the asynchronous frame loop owned by #20. Explicit close is
idempotent; destructor and extension termination join the worker before unload.
Reloading the extension in a running editor is disabled.

The portable test has an empty PATH, isolated TEMP/profile directories, a working
directory outside the payload, and a relocated path containing spaces and Unicode.
It checks actual code-address-derived loaded JSBSim path/hash, actual CRT module
paths/hashes, schema validity and clean shutdown. It also exercises destructor-only
closure and malformed initializer rejection. A separate disposable copy quarantines
both exported JSBSim locations: startup must fail visibly, without a fallback DLL.
Root and `bin/` copies are deliberately retained for Godot exporter dependency
staging and Windows startup search; the actual loaded module witness identifies
which identical bytes were selected.

Cold editor import uses `--quit-after 120 --frame-delay 100`, plus a 120-second
watchdog. Immediate first-discovery shutdown crashed the pinned engine during
the original experiment. The bounded paced import completed with clean logs;
this is a tooling workaround, not an engine patch or runtime stability claim.

## Corresponding source and runtime gates

`source-bundle.py` selects 279 byte-identical pinned upstream library files plus
seven first-party wrapper/inventory/build files. It excludes all upstream model
XML and unrelated packages. Canonical LF, ordinal ZIP entries and fixed metadata
produce the reviewed archive hash on both Git checkout styles. Included
`verify.py`, `pack.py` and `BUILD.md` document independent verification/rebuild and
LGPL-compatible replacement/debugging rights. No application-side binary hash
allowlist prevents an ABI-compatible modified JSBSim DLL.

`replacement.ps1` verifies the archive, builds it from a fresh extraction, checks
unchanged source, retains actual compile/header/import logs, and replaces only
JSBSim DLL files in a disposable export. Its clean-environment run must load the
replacement inside that payload and preserve command/sample/event behavior within
frozen `1e-9` absolute / `1e-12` relative numeric tolerance; nonnumeric fields stay
exact. This tolerance tests the integration boundary, not aircraft accuracy.

`package.mjs` stages notices, primary terms, corresponding source and replacement
evidence, writes a hashed component inventory, and runs the package rights audit.
`check-runtime.mjs` requires exact reviewed CRT hashes/version/source revision,
x64 PE files, valid inspected Microsoft signatures and a runtime no older than
the actual compiled toolset. New hosted runtime identities deliberately fail this
gate until their concrete inventory is independently reviewed and pinned in the
rights register. A Community entitlement does not silently approve arbitrary DLLs.

The artifact inventory is proof scope only. Final simulator packaging, servicing,
read-only install tests, signatures and release qualification belong to #61/#P7.
