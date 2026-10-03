# Risks and decisions with evidence gates

These are planning uncertainties to resolve through owned issues. They are not reasons to stop building the reversible prototype.

| Risk | Consequence | First owner/gate | Mitigation and fallback |
|---|---|---|---|
| Analog C172S reference applicability and rights | Incorrect procedures/limits or inaccessible source material | Aviation owner; LICENSE-REGISTER, AIRCRAFT-EVIDENCE | Record exact configuration and lawful references; keep generic aircraft labeled prototype; reviewed variant/scope ADR if unavailable |
| Published performance cannot identify all aerodynamic coefficients | A model matches cruise but handles incorrectly | Physics/validation; VALIDATION-CORPUS, BASELINE-PERFORMANCE, FDM-CALIBRATION | Independent traces, sensitivity/envelope testing, qualitative pilot review, uncertainty report |
| Native ABI/CRT/export mismatch | Works in editor but will not launch on another PC | Delivery; NATIVE-EXPORT | Early clean exported Windows ZIP and locked engine/extension/compiler pairing |
| JSBSim/terrain contact boundary | Ground snapping, unstable gear, double-solving contacts | Physics/world; GROUND-PROOF | One solver, datum/normal/frame fixtures, tile seam and contact trials |
| Hidden state cannot be completely serialized | Mid-flight resume diverges | Persistence; SAVE-PROOF | Verified command reconstruction or named safe restart/checkpoints; never promise exact continuation without evidence |
| Godot terrain/cockpit performance or authoring limits | Scope takes too long or reference PC misses budgets | Presentation; RENDER-PROOF | Bounded region, proxy benchmarks, two measured corrections then renderer fallback ADR |
| Vertical datum or magnetic/true confusion | Runway elevation/navigation inconsistency | World; GEODESY | Explicit WGS84/ECEF/NED, geoid source, independent fixtures and conversions |
| Airport sources conflict or age | Wrong pattern/runway/closure behavior | World/aviation; WORLD-PROVENANCE, REGIONAL-AIRPORTS | Source priority by field, dated historical packs, traced overrides, scenario-only temporary closures |
| Chart/imagery/asset redistribution rights | Cannot lawfully ship content | Content/delivery; LICENSE-REGISTER | Original assets/open data after review; no bulk mirror/scrape; source links instead of restricted manuals |
| Formal instruction reviewer unavailable | Scored content exceeds reviewed scope | Training; LESSON-CURRICULUM, INSTRUCTOR-TOOLS | Keep unreviewed lessons visibly preview-only; no mastery/device-credit claims; optional father's feedback stays qualitative |
| Consumer controls lack actual force/sight/motion cues | Handling habits transfer incompletely | Input/validation; CONTROLLER-QA, PILOT-ACCEPTANCE | Calibrated controls, clear limitations, readable cockpit, independent aircraft measurements; future hardware gates |
| Fleet changes shared schemas concurrently | Merge conflicts and incompatible modules | Integrator; CORE-CONTRACTS | Contract-first PRs, path ownership, fixtures, one integrator, isolated worktrees |
| Save migration/crash/full disk | Lost history or inconsistent flight state | Persistence; LOCAL-PERSISTENCE, SAVE-UPGRADE | Transactions, SQLite backup API, previous valid generations, failure fixtures and truthful save status |
| Safety scoring rewards outcomes without decisions | Unsafe incentives or misleading competence | Training; TRAINING-EVALUATOR, ACHIEVEMENTS | Safe alternatives succeed, evidence-tagged assists, separate skills, negative/exploit fixtures |
| Large-world/VR/network scope overtakes core flight | No useful experience reaches the user | Integrator; FIRST-FLIGHT, FULL-CIRCUIT | One bounded aircraft/circuit first; P8 requires measured value and a new scoped decision |
| Public binaries need signing/budget decisions | Launch friction and publisher uncertainty | Delivery; RELEASE-CANDIDATE | Separate checksums from identity; record unsigned alpha status; do not buy/provision without owner decision |

Review risks at every phase gate using the [roadmap evidence template](roadmap.md). Assign newly discovered defects to an issue with an observable resolution condition. Do not erase an uncertainty by changing its label to validated.
