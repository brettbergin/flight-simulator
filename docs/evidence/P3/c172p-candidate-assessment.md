# Maintained C172P candidate source assessment

Issue: [#169 — C172P-SOURCE-ASSESSMENT](https://github.com/brettbergin/flight-simulator/issues/169).
Date: 2026-10-10. Status: conditional source assessment; independent review and checked merge remain required. This is partial preparation for REAL-001, REAL-002, REAL-003 and PRD-003. It neither authorizes a port nor changes the selected C172S target, [#28](https://github.com/brettbergin/flight-simulator/issues/28), [#76](https://github.com/brettbergin/flight-simulator/issues/76), or any phase/hardware/pilot/training gate.

## Recommendation and comparison

**Retain the maintained FlightGear team's C172P as a conditional candidate for a bounded standalone-source assessment; decline immediate runtime adoption.** Its explicit project GPL grant and developed C172-oriented implementation make it worth investigating before authoring more aircraft-specific behavior from scratch. Improved accuracy, portability and delivery time have not been measured. The bundled JSBSim c172p is a different source with an actual contrary restriction and remains excluded.

The candidate is [c172p-team/c172p release version/2024.1.3](https://github.com/c172p-team/c172p/releases/tag/version%2F2024.1.3), immutable commit [ee9bc21137cc2f96c5f86886fe908f337923389a](https://github.com/c172p-team/c172p/commit/ee9bc21137cc2f96c5f86886fe908f337923389a). Proposed assessment scope is **one conventional-panel, 160 hp land C172P**. This describes the branch to investigate, not a certified installation or an admitted simulator profile.

| Path | Evidence available | Benefit and remaining limit |
|---|---|---|
| Current original prototype | [Original source/reference history](original-piston-source.md), [loader amendment](original-piston-loader-source.md), [coupled mechanism evidence](coupled-midpoint-shaft.md), [cold-engine player](original-piston-player.md) | Working engineering interaction and independent numerical evidence. Original polynomial aerodynamics and authored propulsion maps are not calibrated Cessna behavior. Preserve its identities, recordings, references and regressions |
| Maintained C172P candidate | Actual pinned FDM, engine/propeller/system source and affirmative upstream GPL2+ grant | More developed flap/control, aerodynamic rate/cross-axis, loading/contact and engine/system behavior offers a plausible implementation saving. Source complexity is not accuracy evidence; standalone closure, applicable aircraft references and normal-flight comparison are unresolved |
| Selected analog C172S | [Source policy](../../sources.md), [ADR002](../../decisions/002-dynamics-and-timing.md), applicability and normal-baseline issues | Preserves the selected fuel-injected objective. Exact serial/equipment/propeller/POH/revisions and applicable quantitative truth remain unresolved; a current glass-aircraft sales page or C172P model cannot supply them |

[ADR001](../../decisions/001-engine-and-native-stack.md) retains a full FlightGear fork as a possible architecture fallback; that is broader than this candidate assessment. [ADR010](../../decisions/010-original-piston-profile.md) and [ADR015](../../decisions/015-source-law-coupled-shaft.md) qualify only their original prototype/source mechanisms. Their coupling implementation does not establish compatibility with the candidate's tables and host behavior.

## Exact evidence and rights boundary

The accompanying [metadata-only source index](c172p-candidate-source-index.json) records 30 actual source files retrieved and inspected for targeted licensing, dependency, configuration and host-ownership signals. It distinguishes these reads from repository-tree metadata and unresolved/uninspected transitive files. This was not a line-by-line numerical verification of all source. Git blob SHA1 values identify upstream Git file content as reported by the primary repository connector. They are **not** archive SHA256, physical package hashes or proof of a complete distributable source bundle. No candidate archive was acquired or imported by this task.

At that immutable commit, [CONTRIBUTING.md line12](https://github.com/c172p-team/c172p/blob/ee9bc21137cc2f96c5f86886fe908f337923389a/CONTRIBUTING.md#L12) grants GPL version2 or later; preceding contributor certifications address rights to contribute. [LICENSE](https://github.com/c172p-team/c172p/blob/ee9bc21137cc2f96c5f86886fe908f337923389a/LICENSE) provides GPLv2 terms. Multiple selected system files also carry explicit GPL2+ headers. The maintained FDM has no old sale restriction. An individual license header in every file is not required to recognize an express project grant.

This is affirmative licensing evidence for a candidate, **not cleared redistribution of our application or every upstream asset**. A later scoped review must retain authorship/notices, record modifications, resolve transitive exceptions and the derivative/application distribution boundary, and satisfy the applicable source/distribution obligations in GPLv2 sections1–3 and6. Do not label upstream GPL material MIT or presume either that the entire application automatically changes license or that calling interpreted files “data” removes their obligations.

[Thanks](https://github.com/c172p-team/c172p/blob/ee9bc21137cc2f96c5f86886fe908f337923389a/Thanks) identifies CC-BY/CC0 sound sources and GPL propeller mesh attribution. Their presence does not clear all assets or manufacturer publications. Initial numerical assessment should exclude sound, mesh/texture, cockpit, tutorials and copied checklist assets. No upstream XML, assets, manuals or tables are redistributed in this assessment, and the executable rights register is unchanged.

The distinct [bundled JSBSim c172p](https://github.com/JSBSim-Team/jsbsim/blob/3b25f25e49b42d0489c04ac805674fc1450ca579/aircraft/c172p/c172p.xml) at the pinned library commit has an unknown author, guessed/qualitative provenance and an actual note: “This model is not to be sold.” Its README is actually zero bytes. The library's LGPL grant does not resolve that contrary aircraft term. Its actual local source SHA256 and README identity are recorded separately in the index. Existing model and library-only source-package exclusions remain intact.

## Actual numerical and host dependency findings

The candidate [c172p.xml](https://github.com/c172p-team/c172p/blob/ee9bc21137cc2f96c5f86886fe908f337923389a/c172p.xml) is BETA and has experimental stall/spin comments. Those comments are not stall/spin qualification.

| Active FDM branch | Actual source paths | Assessment |
|---|---|---|
| First engine | `Engines/eng_io320.xml` and `Engines/prop_75in2f.xml` | Prospective 160 hp path; the engine header describes no injection despite its IO-style filename. Neither filename proves the approved Lycoming installation or propeller |
| Second engine | `Engines/eng_io360.xml` and `Engines/prop_76in2f_NACA_20deg.xml` | Optional 180 hp branch, outside proposed scope. The engine/propeller and associated loading cannot be silently left active |

There are **17 direct system references**: bushkit, fuel, c172p-engine, c172p-skis, hydrodynamics, c172p-hydrodynamics, c172p-ground-effects, c172p-damage, c172p-sounds, c172p-heat, external-heat, propulsion, indicated-airspeed, icing, static-sources, mooring-jsbsim and towbar. Sixteen corresponding candidate files were retrieved and targeted-read. **The exact path `Systems/hydrodynamics.xml` is absent from the pinned repository tree.** The similarly named candidate system and Nasal files do not satisfy that reference. Its actual external host origin/version is unverified. A future landplane transformation must either pin the real dependency or explicitly remove the unsupported branch with reviewed evidence; a guessed replacement is unacceptable.

This is a direct roster, not recursive closure. [c172p-main.xml](https://github.com/c172p-team/c172p/blob/ee9bc21137cc2f96c5f86886fe908f337923389a/c172p-main.xml) includes separate FlightGear property-system XML, Nasal scripts and external generic files. Important ownership boundaries include:

- `Systems/engine.xml` and main-property aliases participate in active-engine selection, electrical starter supply and control routing. They are separate from JSBSim's direct FDM system includes.
- `Systems/fuel.xml` consumes host active-engine/start state; float-chamber/feed and tank behavior cannot be inferred from engine XML alone.
- `Nasal/engine.nas` participates in primer, oil and carburetor-icing behavior; FDM engine/heat systems consume host-managed values.
- `Nasal/c172p.nas` contains auto-start/auto-mixture helpers and state listeners. Presence does not imply always-enabled assistance; activation/defaults and native replacement need review.
- External `Aircraft/Generic/Human/Include/walker-include.xml` and `Aircraft/Generic/updateloop.nas` are observed host references, not retrieved/pinned dependencies in this assessment.

Loading the FDM alone would not establish preservation of the FlightGear aircraft's complete systems/procedures. Native simulation must remain the one authoritative state owner; no executable Nasal import or arbitrary host-property consumer is authorized here. [ADR005](../../decisions/005-content-and-aircraft-expansion.md) content restrictions remain unchanged.

## Configuration and normal-reference gaps

The FDM's loading comment references a 1982 160 hp C172P POH. Its optional 180 hp pointmass comment references a 1998 C172S POH. Those are **implementation source locators, not acquired or applicable certified data**. Land/float/amphibious/ski contacts and extra-mass branches need explicit isolation before a single-aircraft profile could be proposed. Optional C172S loading must not become the selected C172P loading basis.

| Required input | Current assessment |
|---|---|
| Exact year/serial applicability, installed engine and approved propeller, panel/equipment/modifications | Unverified; no certified configuration selected |
| Current aircraft/engine TCDS revision and applicable notes | Unverified. [FAA's official TCDS discovery route](https://www.faa.gov/faq/how-can-i-locate-type-certificate-data-sheet-tcds-aircraft) is a route, not a retrieved certificate |
| Applicable POH/AFM, revision/addenda/supplements and permitted extraction/use | Not acquired. [Textron publication access](https://txtav.com/en/apps) does not itself grant redistribution |
| Empty/equipment mass and moment, datum/stations/CG envelope, fuel/oil accounting and restrictions | Unverified; upstream comments are not the selected aircraft's loading records |
| Normal-performance values, conditions, uncertainty and tolerance budgets | Unsupported references, not passes; no values or tolerances supplied here |
| Standalone dependency, license, solver/default and control/start compatibility | Incomplete; no load/build/flight trial performed |
| Handling/procedure and hardware/pilot evaluation | Not performed |

The [Lycoming July2025 certified-engine catalog](https://www.lycoming.com/sites/default/files/file/2025-07/SSP-110-3%20Certified%20Engines.pdf), printed p4/PDF page8 and printed p35/PDF page39, provides O-320-D2J engine-family/rating and Skyhawk172 context. It does not establish exact 172P serial/approved-propeller/POH applicability. The publication remains copyrighted; no table or manual redistribution is cleared. Manufacturer publication access, isolated public facts and permission to package a manual are distinct.

## Precise next dependency tasks

These are recommendations for later separately assigned issues, **not dispatched consumers or an accepted profile contract**:

1. **Source/applicability dossier:** pin actual current certified aircraft/engine documents and lawful applicable POH/AFM/supplements; freeze one conventional-panel 160 hp land installation, equipment/loading basis and every retained parameter's source revision/page/hash/unit/status/uncertainty and use rights. Record unknowns without copying restricted tables. Source access must remain free/lawful within present authorization; paid acquisition, accounts, outreach or special permissions need separate authorization.
2. **Recursive numerical/host and rights closure:** inventory every retained file/property/native behavior and attribution, selected GPL obligations and source/package boundaries. Resolve missing hydrodynamics and host code explicitly. Identify each retained/transformed/replaced/excluded engine, land/float/loading/system branch. Preserve original source identity and a reproducible transformation plan.
3. **Standalone interface/fallback decision:** only after review, propose a separate profile/model/package identity and source hashes, capability-qualified controls/indications, starts, assists, SI/frame boundaries, save/replay compatibility and one-owner systems chronology. Decide how the selected solver/source/defaults relate to the candidate's backend. Preserve original profile/reviews and separately tracked C172S work. No new ADR or interface is adopted by this assessment.
4. **Independent normal-reference design:** before tuning or observed trials, obtain applicable references for trim/cruise TAS/power/fuel, climb IAS **and rate**, takeoff ground roll versus specified-obstacle distance, approach/landing ground roll versus obstacle distance, and IAS/CAS calibration where supported. Freeze loading/CG/configuration/technique, atmosphere/altitude datum/wind/surface, units, extraction method, uncertainty and justified tolerances. Missing cells stay unsupported. Normal evidence belongs before scored curriculum, not deferred wholesale to P6.
5. **Offline compatibility and numerical experiment, then pilot review:** use a later reviewed port/source contract to test exact loaded library/model identity, initialization, controls, fuel/mass/CG/frames, shutdown, error admission, cadence and independent normal-performance comparisons. Preserve failures and original regressions. Pilot feedback then supplements quantitative evidence within the tested envelope; it cannot replace missing source truth.

**Conditional decision:** pursue the dossier/closure and contract proposals if lawful applicable references and scoped GPL integration are feasible; decline runtime adoption until those conditions and the subsequent compatibility/performance evidence are accepted. If references remain unavailable, finish the source task with explicit blocked cells and retain the honest original engineering model. #169 cannot satisfy the different C172S issues by substitution. Root must separately rescope affected work or create candidate-specific sibling tasks before any port.

## Verification and retained limits

The issue depends on accepted [LICENSE-REGISTER #13](https://github.com/brettbergin/flight-simulator/issues/13) and [VALIDATION-CORPUS #19](https://github.com/brettbergin/flight-simulator/issues/19); both were closed when checked on 2026-10-10. Their rights/reference frameworks do not clear this candidate or supply real-aircraft performance. Requirement mapping covers only source-assessment preparation.

Run `node tools/check-docs.mjs` for the documentation and generated mapping; exact result and final review belong in the PR. No aircraft/runtime build, launch, numerical tuning, new tolerance, manufacturer table copy, training-credit claim, or phase acceptance is part of this task. Current required CI and independent final-document/source-index review remain merge prerequisites.
