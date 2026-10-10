extends RefCounted
# Original MIT. Actual profile admission must not silently expand wind cue scope.
const Facade=preload("res://simulation/session_facade.gd")
const Readings=preload("res://cockpit/instruments/native_readings.gd")
const Cue=preload("res://world/wind/wind_cue.gd")

static func run(root: String) -> Dictionary:
	var failures: Array[String]=[]
	var checks: int=0
	var facade: RefCounted=Facade.new()
	var opened: Dictionary=facade.start(root,"piston-cold-ground","calm",Facade.PISTON_PROFILE.id)
	checks+=1
	if not opened.ok: failures.append("actual_cold_profile_open")
	if opened.ok:
		var source: Dictionary=facade.readback()
		var before: Dictionary=source.duplicate(true)
		var readings: Dictionary=Readings.from_readback(source)
		checks+=1
		if readings.state!="live": failures.append("full_piston_readback_valid_for_shared_instruments")
		var cue: Dictionary=Cue.from_readback(source)
		checks+=1
		if cue.state!="invalid" or cue.error.is_empty(): failures.append("piston_not_silently_adopted_by_legacy_wind_cue")
		for key in ["session_id","tick","wind_toward_ned_mps","speed_mps","from_true_rad","wind_toward_airfield_eus_mps"]:
			checks+=1
			if cue[key]!=null: failures.append("unsupported_cue_clears_"+key)
		checks+=1
		if source!=before: failures.append("cue_does_not_modify_native_readback")
	checks+=1
	if not facade.close().ok: failures.append("actual_worker_joined")
	return {"passed":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Actual original cold Readback admission with deliberately unsupported ADR013 wind presentation; existing legacy arithmetic suite remains separate"}
