# Independent coupled-midpoint reference

This standard-library mathematical reference accompanies issue149 and
[ADR015](../../../../docs/decisions/015-source-law-coupled-shaft.md).
It supplies the frozen expected packet for `event_aware_coupled_midpoint_v1`.
The protected contract merge is `eb410a634a9f18b4ea9177640aff391def5e7988`.
The reference does not import the native implementation or consume native
answers when generating expectations.

The recorded Windows x64 trial passed all24 mathematical self-checks and
produced the packet without a timeout. Independent source/math review checked
41 named groups,137 native requests,104 root/floor certificates,75 absolute
coefficient intervals and nine refinement partitions. The separately authorized
native trial then passed137 isolated request comparisons,270 preserved legacy
checks and12 actual-library chronology observations. The manifest records
packet/source/model identities and evidence hashes. These observations cover
the tested arithmetic and chronology; they do not establish aircraft fidelity,
phase acceptance or aviation training credit.

## Files and representations

- `generate.py` derives coefficients from pinned original XML and explicitly
  lifted backend constants. Raw XML spark drop and the actual loaded
  `RN(1-RN(XMLdrop))` factor remain separate.
- `exact.py` provides Fraction polynomials, square-free Sturm isolation,
  nested192/384-bit root enclosures, integer IEEE conversion, floor-cell
  certificates and certified rational quadrature.
- `cases.json` freezes41 groups and their declared sided expansions.
- `native_fixture.py` realizes binary64 native inputs independently, then
  derives their own F/Sturm expectations. Ideal rational records are retained.
- `references.json` is the immutable generated packet.
- `reference-manifest.json` binds that packet, all nine source/document files,
  the roster, generator sources and model pins. It is repository provenance;
  it does not identify an executing native library by itself.
- `test_reference.py` and `test_native_fixture.py` contain24 mathematical
  checks. They do not launch the native solver.
- `COMPARISON-PLAN.md` and `NATIVE-FIXTURES.md` preserve the reviewed comparison
  design and request contract. Their prospective/source-freeze wording describes
  the design stage; the recorded results above and manifest supply later evidence.

Exact ideal coefficients, ideal algebra on loaded constants and each rounded
native law are distinct. A native scalar result compares with the independently
proved binary64 floor for its exact dyadic law, or an exact hold/stop. C/L
coefficients compare with absolute operation intervals. Their nominal RN-DAG
bits are diagnostic, including canonicalized algebraic zero signs. R01 separately
checks the incoming RPM raw bits, including both signed zeros.

K/E fixtures isolate the mathematical kernel. Abstract source surrogates do not
claim to be admitted original-engine states. Native E05 explicitly uses rho0,
t0=2,ws=4 to realize an exact equilibrium. E06 reports the source-rounded knot
identities; this recorded packet has distinct knots and explicitly separates
them. It must not be described as coincident-knot execution. C consumes held ME;
its table/key metadata does not claim that the isolated driver ran FGTable.
Actual original-model topology and engine chronology are separate library tests.

## Certified bounds and resources

The root oracle constructs F independently of the production H-map solve and
uses exact equilibrium/connected-branch classification. Source endpoints consume
exact rational time; finite stops return exact zero. Root isolation and continuous
quadrature are separate proofs. Composite Simpson uses a certified fourth-
derivative bound, at most4096 panels, and outward192-bit dyadic sample sums.
Continuous inversion uses the speed/time Lipschitz bound on nonsingular compact
intervals; finite singular stops report time intervals and a known zero endpoint.

Three smooth families retain partitions8/16/32 and their a-priori global error
bounds. Each propagated state interval is enclosed outward on a384-bit dyadic
grid before the next iteration. This bounds representation growth without
relaxing the original compact checks, tolerances or order bounds. Arithmetic
retains the131072-bit rational ceiling and a finite decimal serialization limit
derived from it. Fixed-law second-order consistency is not a claim about whole-
aircraft convergence.

## Offline reproduction

Use the repository's pinned bootstrap Python. From the repository root:

```powershell
& $Python -B -m unittest discover -s tests/engine/shaft-method/coupled-midpoint-v1 -p 'test_*.py' -v
& $Python -B tests/engine/shaft-method/coupled-midpoint-v1/generate.py --repo-root . --check tests/engine/shaft-method/coupled-midpoint-v1/references.json
```

`--check` regenerates and compares complete deterministic bytes without writing.
The recorded generation took about276 seconds; the24 self-checks took less than
one second. To prepare a proposed replacement after a reviewed source/contract
change, use `--write-new` with a fresh output path; it refuses overwrite. Review
and bind any replacement before comparing native outputs. Do not update frozen
expectations from implementation observations or change physical budgets to fit
a result.

Native execution additionally requires the selected source/build identity,
strict floating-point compiler/environment checks, actual loaded-library path
and pre/post executable/DLL hashes. The original complete twelve-process
physical/publication suite and its immutable budgets remain a separate gate.
Historical held-power and legacy packets remain unchanged. See the phase
[evidence index](../../../../docs/README.md) for project acceptance status.
