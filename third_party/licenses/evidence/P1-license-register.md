# P1 issue #13 evidence

Reviewed 2026-10-03. Branch `codex/license-register`; scope is the rights ledger, retained notices, offline audit and aircraft-source feasibility. This is source/inventory evidence; no binary package, C172S fidelity validation or release gate is claimed.

| Acceptance | Evidence |
| --- | --- |
| Runtime/data classes have source, license, obligations, owner and evidence | `register.json`: sixteen specific entries and eight mandatory classes, with explicit permitted/conditional/excluded decisions. CLI rejects missing classes, owners, unknown states/obligations and provisional clearance |
| JSBSim library obligations separate from XML/manual rights | LGPL dynamic/source/replacement policy; seven retained notice files across dependencies. Scoped full-header/CMake/maintainer review in `jsbsim-scope.md`. c172x excluded; manuals and unselected data/assets excluded |
| C172S identity/source gaps explicit | `docs/sources.md`: family target only, serial/year/panel/supplements/POH acquisition/extraction rights not frozen. Original prototype fallback is issue #14 and remains excluded until authored/reviewed |
| P1 feasibility, P3 exact freeze | Manufacturer acquisition route and limits of public product metadata documented; P3 five-part configuration/source/derivation/validation/manifest gate. No guessed aircraft values or restricted source copies |
| Unknown/incomplete releases rejected | `tools/license-audit/test.mjs` tests positive conditional fixture and negative package cases; real register's null distributable-source digest blocks even a staged test source ZIP |

Validation on Windows with Node:

```text
node tools/license-audit/audit.mjs
PASS rights inventory and notice integrity (16 entries)

node tools/license-audit/test.mjs
PASS 33 rights audit checks

node tools/license-audit/audit.mjs --dependency-lock <issue-12-worktree>/third_party/dependencies.lock.json
PASS rights inventory and notice integrity (16 entries)

node tools/check-docs.mjs
Validated 76 planned issues, 36 labels, 9 phases.
Checked 147 requirements and 9 phase dispatch briefs.
Foundation checks passed (42 Markdown files).

git diff --check
PASS
```

The lock was independently authored/acquired by the toolchain owner and cross-checked against the register's exact JSBSim/godot-cpp/SQLite source revision, version and acquisition digest, plus the Godot runtime/template version. This branch does not modify the toolchain lock or workflow. The integration owner must run the same check against the merged lock, not a sibling worktree.

Remaining package gate owned by issue #15: a reviewed reproducible library-only corresponding-source bundle and independent digest, clean source build, real DLL replacement evidence, staged complete notices, authentic package file identities, and release-job invocation of the auditor. The full upstream JSBSim ZIP is an acquisition artifact containing excluded model data and is not approved as the distributable source bundle. Integrity tests do not establish the truth of legal/source/replacement assertions; scoped source and package review remain required.

Requirements addressed: REAL-001, REAL-002, PRD-001, PRD-026, PRD-034, WORLD-004 and WORLD-005. The scoped magnetic-model observation also preserves WORLD-020's current-model gate; it does not implement that model.
