# Selected recorded-review files

Issue [#138](https://github.com/brettbergin/flight-simulator/issues/138) implements accepted [ADR012](../../decisions/012-observed-review-interchange.md) over [recorded flight review](observed-flight-review.md). [PR139](https://github.com/brettbergin/flight-simulator/pull/139) merged as `9610c4a8df264f103dff0cdb3dfe71befc01124e` after review of source `b99187157afc48d4e92fd9bb1e6255e109197195` and all four protected checks. This accepts the bounded engineering feature below; aircraft, pilot and phase gates remain open.

## Player behavior

At a verified pause or joined stop, **Save new review** saves the current recording to a new explicitly selected local Windows NTFS file. It preserves the recording and refuses existing targets. **Open review** qualifies a bounded file completely before adopting a separate historical view. **This flight** returns to the current recording. Saving while viewing an import still saves the current flight. File errors and cancellation preserve the previous selection and current airplane; a modal chooser cannot resume or control it. Saved observations cannot resume physics.

The helper exclusively creates a same-directory temporary, writes and flushes it, and lets the caller qualify its exact bytes before a no-overwrite commit. The committed target is qualified again and the helper's actual process exit precedes release of the operation gate. Failures expose temporary or uncertain target paths through selectable **Details** for manual recovery. Stable local NTFS parents are assumed; adversarial parent replacement and hardware power-loss durability are not qualified. There is no overwrite, automatic retry, library, autosave or profile inspection/upload.

## Frozen references and functional evidence

The preconsumer scalar manifest has 20 finite cases and six nonfinite rejections, SHA256 `406b00475e444f71f6e1f57fd37100c52b86c076e0dccbf664bb5bfc05c028d8`. The archive manifest has eight positive and 32 negative cases, SHA256 `961d8903f702f1d46374998db06b7517a1ca067333b3613bd2adbf3a8c06b15e`. Their ratification binds accepted contract source `2409a543af654af763fc1b84fa47a61cb030d0e5` and base `203281125d696cc567eee8133f9cda74fa56b6df`. Exact supplied types, canonical uint64 tick strings and finite binary64 bits are required. Hash integrity does not establish authorship or aviation authenticity.

The exact desktop packet `run-83e9931a81e54f748f0cdf1a5bef04ff` passed all three contexts: pinned Godot editor, portable Windows export and actual source-rebuilt JSBSim replacement. Each passed 1,560,616 codec, 516,878 actual file and 49 actual native-scene checks. The full 2,401-observation fixture retains 3,990,531 payload bytes and 4,643,883 archive bytes. Checks cover strict UTF8/JSON/closed schemas, type/bit preservation, incompatible or corrupt input, exclusive creation, collisions and recovery, foreign-thread refusal, helper retirement and modal native/controller/recorder/camera/origin invariance. Existing flight, input, instrument, landmark and observed-review regressions passed.

The actual share-lock test now requires closed PID/nonce readiness, lock ownership throughout the rejected production open, explicit release/disposal acknowledgement and observed child exit. A separate 39-check fixture proof rejected expiry and early exit and admitted delayed readiness; no forced termination counted as successful retirement. References, production actor, model and numerical budgets were unchanged.

## Exact package and fresh visual review

The package closes 251 payload files, 163 authoring source bindings, 174 PCK resources, 45 reference bindings, corresponding source/notices, selected CRT and actual loaded native modules. It compared 9,805 exact editor/portable records and 121,770 replacement numerical leaves under the existing criteria. The source-rebuilt replacement runs before six final metadata/notice additions; final payload closure is verified separately.

A fresh exported GPU observer passed 195 checks and captured 21 current/chooser/saved/opened/collision/recovery views at 960x540, 1920x1080 and 2560x1440. Independent review directly inspected all 21 new images. Earlier images were not reused. A separate earlier headless editor Delete-shortcut probe remains scoped to its unchanged scene source, not an exported physical-keyboard claim.

- Manifest: `653ac0fcffc949346fca9580eca0fb00685ffaaa05abcf1f80daf119558eb357`.
- Package inventory: `d85a0b5e02a55daa90b5aa29b5355ba2ffc98884d5a910ea07eaaf5ec16b0506`.
- Audit: `07655036d4ceb72794af0cba2275ef3a14fc3edc3978cca06cce09336a4f391f`.
- PCK: `a32c48c90acfc37738bca8e2604d7f16e850c83189a1f297390b502fda0b07c1`.
- Fresh exported visual receipt: `d350cc9df0c6d7d93151db883fb0c9b86a6b62ee2f1c1b6222e51baa4d4dc28f`.
- Independent final artifact/21-view review: `f10d10ddd3945bcacfa54f91a0c781271efa533b9cbd7dd1b3da5c0fd0ad8070`.
- Coordinator final package review: `a62754ac2003b4bf59c05791135cf66010e73c92db0543803fe050f57262be41`.
- Exact final eight-path source supplement: `1005aa2539eb90b0190fc083aee43c3d9e1dab22b5fdcecbdf9ea1fdb5d5c777`.

The final source guard covered all 75 changed blobs using exact Git hashes and retained independent reviews. Accepted native source fingerprint `35cf7b603d99b9accb123405f7569a901ed9e28d32110acbc296b376facd6416` and bridge `5fa8c9ff0bf82ce79b8110b625c17c8d62c589acc746ee05d6f785d2f6a7d256` remain unchanged; this feature changes no flight physics or model pins.

## Protected integration and limits

- [docs (ubuntu-24.04)](https://github.com/brettbergin/flight-simulator/actions/runs/37213479684/job/111469184195): completed / success at the reviewed head.
- [native (ubuntu-24.04)](https://github.com/brettbergin/flight-simulator/actions/runs/37213479722/job/111469184140): completed / success at the reviewed head.
- [docs (windows-2022)](https://github.com/brettbergin/flight-simulator/actions/runs/37213479684/job/111469184036): completed / success at the reviewed head.
- [native (windows-2022)](https://github.com/brettbergin/flight-simulator/actions/runs/37213479722/job/111469184003): completed / success at the reviewed head.

Earlier unsuccessful scratch-path, reserved-name, comparator, timeout and lock-timing trials remain separately retained. Hosted d81ff2b evidence completed its portable facade in 548.595 seconds and identified failed lock readiness/disposal/retirement checks, with helper startup substantially slower than the editor context. An unlabelled join prefix did not prove a permanent hang or solver fault. Fixed-label stage diagnostics and the corrected test handshake preserve the actual production rejection requirements.

The separate extension-free exported ABBA startup diagnostic passed with actual process and bounded-reader joins, qualified fixed metadata and restored environment. Local late-A timing overlapped B; no stable local treatment benefit, startup cause or production environment change was inferred. Exhaustive CI facade checks retain bounded 600-second operation deadlines; ordinary imports, smoke checks, compile/export and normal local calls retain 120 seconds. Unsuccessful diagnostics are retained without relaxing numerical assertions.

The owner's prior running game was preserved. Broad persistence/replay/debrief issues 34/35/52/74/75, C172 source and fidelity, hardware/pilot evaluation and phase gates remain open. No training-credit claim follows from these engineering checks.
