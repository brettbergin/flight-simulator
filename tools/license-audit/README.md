# Offline rights audit

The Node CLI checks `third_party/licenses/register.json` and exact notice bytes. Use Node 20+; no npm packages or network access. Exit status is 0 on success and 1 on invalid/incomplete evidence. `test.mjs` exercises real notice integrity and deliberately invalid inventory/package cases using clearly marked fixtures in a temporary directory.

```powershell
node tools/license-audit/audit.mjs
node tools/license-audit/test.mjs
node tools/license-audit/audit.mjs --dependency-lock third_party/dependencies.lock.json
node tools/license-audit/audit.mjs --release .local/release-inventory.json --package-root .local/release-payload --dependency-lock third_party/dependencies.lock.json
```

Issue #15 owns producing the real package/source bundle and wiring this last command into its release job before upload. Until then, inventory success is not a releasable package result. A lock check validates source revision/version/acquisition digests; Godot tool/template versions must match the reviewed runtime. Build-only tools without `license_id` are not runtime approvals and cannot enter a package without a new ledger entry.

## Register contract (schema 1)

Each entry needs a unique lowercase ID, class, name, version, owner role, scope, license/rights description, decision, redistribution state, evidence status, source URLs/revision/applicability, obligations and notice-file inventory. Exact source archive digests, when present, identify acquisition. Notice records contain a repository-relative path, SHA-256 and upstream source URL, with an optional upstream Git blob ID.

Allowed states are `permitted`, `conditional`, `excluded`. Allowed evidence statuses are `source-verified`, `synthetic`, `provisional`, `not-acquired`; provisional/not-acquired cannot clear an included runtime/content record. Excluded entries require a concrete blocker and `no-redistribution` obligation. Unknown classes, states, obligations, missing fields and notice hash changes fail closed. The eight required classes must remain represented even when all entries in a class are excluded.

LGPL entries require dynamic linkage, corresponding-source delivery/modification policies, a separate distributable source digest (or explicit null while the release gate is open), library replacement, modification/debugging permission and modification tracking. Null always blocks release. The upstream download digest is not a fallback corresponding-source digest.

## Package contract (schema 1)

Keep the inventory JSON outside the payload directory. Every payload file must be declared by a registered, included component; file records have `path`, lowercase `sha256` and `role`. Roles: `binary`, `content`, `notice`, `source`, `build-instructions`, `evidence`. Paths are normalized relative paths using `/`; absolute paths, parent traversal, Windows drive paths and symlinks are rejected. All file hashes and staged notice mappings are checked. Shared notices are allowed only with identical hash and role. Unregistered/excluded components, changed versions/revisions, duplicate components and undeclared payload files fail.

Example component shape (substitute verified hashes and paths; this is not a valid package):

```json
{
  "schema_version": 1,
  "components": [{
    "id": "jsbsim",
    "version": "1.3.1",
    "source_revision": "3b25f25e49b42d0489c04ac805674fc1450ca579",
    "files": [{"path": "bin/JSBSim.dll", "sha256": "VERIFIED_SHA256", "role": "binary"}],
    "notices": [{"register_path": "third_party/licenses/notices/JSBSim-COPYING.txt", "package_path": "notices/JSBSim-COPYING.txt"}],
    "linkage": "dynamic",
    "shared_library": "bin/JSBSim.dll",
    "source_archive": "source/jsbsim-library-source.zip",
    "build_instructions": "source/BUILD.md",
    "replacement_test": "evidence/dll-replacement.json",
    "reverse_engineering_permitted": true,
    "modified": false
  }]
}
```

Add all required notices, source, instructions and replacement evidence to `files`. The source file hash must equal the reviewed distributable-source digest. The example's intentionally incomplete inventory fails. A release uses actual SHA-256 digests rather than placeholders.

The auditor checks integrity and evidence presence. Human/source review must establish source-bundle dependency closure, archive members' rights, authentic compiler/runtime identity, the truth of replacement-test results and applicable publication/asset rights. It does not inspect arbitrary archive members or certify legal conclusions from labels. A reviewed source-bundle digest is therefore a prerequisite, not something generated and trusted by the release job itself. Any future library modification needs renewed source review and an explicit policy extension before this auditor permits it.


## Reserved coupled-source release extension

[ADR015's closed modified-library release policy](../../docs/decisions/015-source-law-coupled-shaft.md) reserves only component/policy `jsbsim-coupled-midpoint-v1` for source variant `jsbsim-1.3.1-event-aware-coupled-midpoint-v1`. The current auditor still rejects modified libraries until the separately reviewed implementation lands. Existing `jsbsim` policy and dependency lock remain pristine.

The extension requires a reviewed renewed schema3 identity/archive after prominent piston-file changed/date notices, unchanged four-file/293-file scope, exact staged source identity and modification notice, retained upstream notices, dynamic replacement/debugging rights and matching actual source-rebuild/export evidence. The issue149 archive9b1b digest remains preserved numerical evidence, not modified-release approval. No other component, arbitrary policy/digest, generic modified-library exemption or old pristine ExportProofRoot is admitted. See ADR015 for exact added register/component fields; schema1's existing meanings are preserved.


The same ADR015 addendum reserves exact `SelectedLibraryRelease/v1` source/export selection and separate `PistonFlightChecks/v1` focused-player receipts before consumers. Their exact shapes, counts, source/backend matching and nonvacuous checks are defined there; existing facade receipts remain unchanged.
