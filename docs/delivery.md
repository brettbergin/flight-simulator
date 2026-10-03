# CI, releases, and repository governance

## What exists today

`Foundation CI` validates documentation links, required files, backlog structure/dependencies, issue references, action pins, the rights register and notices, and mutation-free backlog/prompt previews on `ubuntu-24.04` and `windows-2022`. Node 22 is the CI runtime; local tooling supports Node 20+.

`Native CI` builds the pinned C++20 dependencies and native contract tests on both platforms, verifies dependency integrity, checks that JSBSim is a shared library, and requires positive native loading markers from the pinned Godot editor. Schema validation and rejection tests run before compilation. See [the bootstrap instructions](../tools/bootstrap/README.md) for local commands and [the implementation record](evidence/P1/bootstrap.md) for accepted evidence. These are engineering foundation checks; exported flight simulation and aircraft fidelity have separate tasks.

`Foundation release` handles `docs-vMAJOR.MINOR.PATCH` tags on commits reachable from main. It reruns checks, packages the repository source as a ZIP with SHA-256 checksums, creates a draft prerelease with explicit documentation-only notes, attaches the assets, then publishes it. There is no store, server, subscription, or automatic client updater. GitHub Releases is the distribution destination.

## Implementation pipeline to build in P1-P7

| Trigger | Required work | Evidence |
|---|---|---|
| Every core PR | Windows MSVC x64 build; Linux headless reference build; format/static analysis; unit/integration tests; deterministic seeded scenarios | CTest results, model/content hashes, artifacts |
| Every renderer PR | Headless Godot import validation, Windows export, extension/DLL load smoke, scene/UI checks | Export log, native-dependency manifest, screenshots |
| Nightly or manual benchmark | Representative flight corpus, performance/realism comparison, extended runtime | Trend report and replay artifacts; failures open triage, never auto-recalibrate physics |
| Release candidate | Both build paths, migration/corruption recovery, cold install, gamepad/hardware bindings, accessibility, pilot review | Signed-off candidate report with actual build SHA |
| Simulator tag `vX.Y.Z[-alpha.N|-beta.N|-rc.N]` | Repeat release checks against tag; package Windows x64 ZIP; smoke on clean Windows without development PATH; attach evidence and notices | ZIP, SHA256SUMS, SBOM, third-party notices, source/license obligations, known limits, pilot validation summary |

Create the native export pipeline in P1, before expensive cockpit content. Use exact engine/export-template/godot-cpp/JSBSim revisions from [the reviewed dependency lock](../third_party/dependencies.lock.json); do not use `latest` downloads. Runtime dependency updates need regression evidence and a small dedicated PR. The lock and verified bootstrap now implement the dependency selections; the portable export remains a separate proof.

GitHub-hosted runners handle CPU/headless/import/export checks. They are not evidence for RTX3090 graphics performance, controller feel, or VR. Use a manually dispatched trusted local benchmark on the owner's machine with documented settings and a consented report. Do not expose the owner's PC as a general runner for fork PR code. Avoid permanent self-hosted infrastructure initially.

## Release contract

Desktop Windows 11 x64 is the initial supported runtime. Portable ZIP first, installer only after save/update behavior is proven. Include a launcher/readme, engine/native dependencies, mandatory offline training pack, optional signed/checksummed content packs, notices, and a version/provenance manifest. Extracting and launching on a clean supported PC must require no developer tools. Installation must never overwrite profiles.

Use `%LOCALAPPDATA%/FlightSimulator/` for writable profiles, SQLite data, replay manifests, crash reports, and configuration. Content in the install directory is read-only. Document exports and backups. Save-format migrations occur transactionally with a recoverable backup; unsupported newer saves are rejected with an explanation. Manual GitHub release downloads initially; upgrades preserve data and support rollback to the prior binary when its save format is compatible. No silent forced update mid-flight.

Code signing: GPG commit signing and Windows Authenticode are separate. For owner-dispatched agent work, per-command unsigned commits are authorized when GPG signing requires interaction; global settings remain unchanged. Initial private alpha binaries can be unsigned with their status stated; public release signing/SmartScreen behavior is a budget and deployment decision, tracked in P7. Do not invent a signing identity or buy certificates automatically. SHA256 checksums provide integrity checks, not a publisher identity.

All artifacts are prepared and validated before release publication. Create a draft, attach all assets, then publish. Failed packaging yields no release; failed publishing preserves a draft for investigation. Retrying must inspect existing draft/tag/assets rather than overwrite a published version. Documentation tags and simulator tags are intentionally separate. A planning archive is never named or described as a playable build.

## Repository policy

Main is kept releasable for its current stage. Squash merge small PRs after required checks and domain evidence. Auto-merge can be used only for already-reviewed changes; pilots and maintainers still own domain review. Protection requires both `docs` and both `native` platform checks, up-to-date branches, resolved discussions and linear history, with no force pushes or deletion and enforcement for administrators. Add export checks after that proof lands. A self-authored owner PR may be merged without an impossible self-review requirement; get an independent agent review now and qualified domain review where specified. Configure protection only after verifying actual status-check names.

Use semantic versioning for APIs/save/content schemas independently of release marketing versions. Keep a changelog with migration, realism, assistance, and content-cycle changes. Record the merge SHA and issue closure evidence in each release candidate report. The owner accepted P0 and authorized implementation; later phase acceptance still requires its own evidence.

Labels: one `type:*`, one `phase:*`, one or more `area:*`, one `priority:*`, and one `status:*` for implementation tasks. Statuses: `ready` (all blocking gates met), `blocked` (linked dependency remains), `in-progress` (claimed branch), `needs-review` (evidence PR ready). Epics may remain blocked until the previous phase gate. A label is a queue signal; linked issue state is the actual dependency evidence. Labels are not auto-updated by the foundation sync tool; the integrator updates them as prerequisites close.

Milestones correspond to P0-P8 outcome gates, without guessed deadlines. Issue IDs in the checked-in backlog are stable keys; GitHub numbers are generated. Each task names scope, owned paths, dependencies, document/requirement references, observable acceptance, and closure evidence. An epic closes only after its children and gate evidence are complete. Later-phase issues are scoped backlog, not authorization to skip gates.

## Security, cost, and licensing

Keep workflow permissions read-only except the release job's `contents: write`. Pin external actions to official full commit SHAs and let Dependabot propose updates. Avoid `pull_request_target` execution of fork code. Do not embed event titles or issue body text into shell scripts. Secrets stay in the credential store/Actions secrets; crash/profile upload is opt-in and scrubbed. Foundation backlog publication uses the authenticated owner CLI locally and is not run with GitHub write credentials in CI.

Default budget is zero mandatory subscriptions or purchased assets. Offline flying needs no account. Use permissive/compatible libraries and openly distributable data after source-specific review; licenses/attributions are shipped per pack. JSBSim's LGPL terms need distribution/relinking/source evidence before native binaries ship. Restricted manuals, charts, trademarks, imagery, and copyrighted sound/3D assets require their own rights. Optional live weather/navigation may incur rights and freshness constraints and must have deterministic offline fixtures.

## Official references

- [GitHub secure use of Actions](https://docs.github.com/en/actions/reference/security/secure-use): action pins and least privilege.
- [GitHub Actions event reference](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows): triggers must match delivery behavior.
- [GitHub immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases): draft/asset/publish sequence. Repository immutability is a future configuration decision, not enabled by this plan.
