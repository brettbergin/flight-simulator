# Original piston local-window replay (proposal)

These original MIT test sources are a private prospective publication draft. They
have not been compiled or executed. ADR024 authorizes the numerical policy;
checked ADR016 fourth-variant allocation (PR212) and reviewed corresponding-source
adoption must precede this consumer's use. No simulator, aircraft, pilot or phase
acceptance is claimed.

`recipe.json` is the unchanged 113,989-byte historical synthetic 298-call fixture
(SHA256 2ef833b13cab7127b19ae84272f9bfc015133e14c125d781c535b84ad284aba1).
Its status and expected failure are historical preparation metadata, preserved
verbatim. The actual baseline replay subsequently reproduced the failure: original
source 5e0abfeae9ffd249f8be3f4410d9903f30736698fcb276bdf72f3630132102e5,
7,726 checks, 298 calls, checkpoint ticks 0/1579/1582 and joined close. It is not a
human flight log or model calibration reference. No restricted source, personal
profile or machine path is included in these four public files.

Only generated session identity, qualified unchanged model-root path and the
reviewed new runtime source identity are rebound. There are265 step_fixed calls,
21 submit calls,10 session_control calls, one open and one close. No read_state call,
extra successful-session call, state injection, changed input, model coefficient
or physics budget is introduced.

The original input decimal tokens and all other recipe bytes remain unchanged.
Python's standard JSON decoder distinguishes original JSON integer tokens from
FLOAT tokens. The existing reviewed preparation encoded 138 payload FLOAT values
as `struct.pack('<d', value).hex()`. `argument-binary64.json` copies that exact
portable mapping, without the private binding's machine/runtime paths.
`checks.gd` uses Godot JSON only for hash-pinned structural fixture transport;
closed LE tags restore actual FLOAT bits with `PackedByteArray.decode_double`.
The only INT restorations are 31 schema_version literals and 265 bounded integral
step_fixed arguments. String tick/sequence identities and BOOLs remain unchanged.
This is a fixed-test-fixture restoration policy, not a general JSON parser.

For the prospective v2 test, original compact expectations remain authoritative
except call 296: its existing 28-tick batch must complete 28, reach String tick 1607,
remain live and nonhistorical, and report no fault. Call 297 must be the original
successful joined close. No target aircraft pose/RPM/force is fitted or introduced.
The historical failure expectation in recipe.json is never overwritten. A failed
run may perform one cleanup close; that extra call cannot make the 298-call test
pass. Raw actual replies, typed restored arguments and publications 0/295/296 are
retained in the result for independent audit.

Stage these four files under `res://local_window_replay_tests/` and use
`preload('res://local_window_replay_tests/checks.gd').run(piston_root)` from the
existing main-thread mandatory harness only for exact generated source variant
`jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2`. The driver also checks
the actual open fingerprint against `res://build/native_identity.gd`, and requires
method `event_aware_coupled_midpoint_v1`; the method name alone is insufficient.
It uses the accepted NativeWireDecoder and full Wire validators, not plain Godot
JSON for native publications. Existing source/loaded-module/model/archive/CRT and
license/replacement admission remains mandatory in the coordinating package.

Each editor, portable and rebuilt-library replacement context must execute the
real driver, save a separate closed `local-window-replay-receipt.json`, and retain
its raw log. Mandatory packaging must validate all three receipts against this
fixture/sidecar, generated exact-source identity, 298 actual call records,138/31/265
restoration counters, final 1607/28 completion, three valid publications and joined
close. Existing Facade and cold receipt schemas remain unchanged; the host adds
these checks and fails on any negative/missing result. A proposed receipt shape
and exact integration requirements are in the coordinator's private handoff.

This replay checks the previously rejected control sequence. Once-per-public
engine/fuel chronology, preserved successful paths, numerical 17 reference cases,
original 137 reference cases, physical/default/convergence suites, source closure
and complete delivery are separate required gates; this replay does not replace
them or claim to prove their internal mechanisms.

Provenance: frozen recipe derives from the original synthetic native ledger
transcript SHA256 22f00351cdfd5a271ffcc814aee19b80a99811f7813d64ec217985cfafd31970
and original observer receipt SHA256 3094ae8a2d826ec5fe41651ca7f4fb4d054408d8bde3a102879f79f760ed6c31.
The original reviewed replay driver SHA256 783630422b19241816b969fbd0ecba2d5df4c7be43ba1c35fbe6178fd966a9c4
and preparer SHA256 b0427ee746f7468d482fbb23c50973cf555527570ed31cddcb8dd7e257c9fd78
supply the restoration lineage. Baseline raw receipt SHA256 dd2ce2a158b9f7265d997c6548ab89e6d8c8587bd65f6d56eccddb07c03b478d
is historical failure reproduction evidence, not a corrected v2 run. Repository
MIT terms cover first-party fixtures/driver; backend LGPL corresponding-source
obligations remain governed by the separately reviewed package and notices.
