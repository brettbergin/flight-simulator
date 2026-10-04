# Cockpit display integration checks

The arithmetic fixtures in [README.md](README.md) remain independently frozen. These additional original UI checks consume the accepted [ADR009](../../docs/decisions/009-cockpit-readings.md) and controls implementation. They do not replace sensed instruments or aircraft qualification.

All three drivers expose async `new().run(host)` and report `{passed,checks,failures,scope}`. Each assertion also reaches the host's failure list. The ordinary package harness runs them in editor, portable export and rebuilt-library replacement:

| Driver | Checks | Evidence boundary |
|---|---:|---|
| adapter_checks.gd | 51 | Shared display conversion, missing channels, copies, exact source identity, retention, finite conversion overflow and actual font bounds |
| scan_checks.gd | 83 | Paused selection/dismissal, live and retained rejection, malformed input clearing, shared scalar values, mouse behavior and bounds at three resolutions |
| scene_checks.gd | 107 | Actual native session with synthetic released input; complete readback, mapper, map, origin and camera preservation; explicit resume/advance, fresh-session clearing and confirmed close |

The pure reading suite separately runs3,226 assertions. UI synthetic ReadingSets, bad/empty publications and huge numbers are explicitly fixtures. They do not establish an aircraft operating envelope. No real device is sampled by these integration drivers.

The bounded `--instrument-visual-smoke` observer uses the exported renderer and an actual paused original-model session. It captures ordinary/outside/dashboard views, all six focused dials, confirmed retained state and an explicitly labeled synthetic invalid view at960x540,1920x1080 and2560x1440. Its receipt checks native readback invariance and worker/audio joins; images still require visual inspection.
