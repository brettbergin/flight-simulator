extends RefCounted
# Original MIT. Actual GDExtension selector/codec/native status integration.
# Root stages and authorizes this test after the native numerical gates.
const LEGACY: String = "original-interactive-prototype"
const PISTON: String = "original-piston-prop-v1"
const METHOD: String = "event_aware_coupled_midpoint_v1"
const WIND: Array[String] = ["calm", "from-north", "from-west", "from-east"]
const SYSTEMS: Dictionary = {"fuel.total":"kg", "engine.throttle":"fraction", "engine.mixture":"fraction", "propeller.angular_speed":"radps", "engine.running":"bool", "engine.ignition_left":"bool", "engine.ignition_right":"bool", "engine.starter":"bool", "fuel.feed":"bool", "engine.starved":"bool"}
# Existing ordinary encode shape plus exactly the accepted successful-open fields.
const READ_FIELDS: Array[String] = ["ok", "schema_version", "aircraft_json", "atmosphere_json", "held_axes", "outcome", "completed", "live", "historical", "paused", "time_scale", "fault", "queued", "rejection", "ground_query_valid", "surface_height_m", "plane_clearance_m", "applied_commands_json", "events_json"]
const OPEN_FIELDS: Array[String] = ["angular_integration_method", "runtime_modules", "named_start", "wind_profile", "native_source_fingerprint", "world_anchor", "prepared_world_sha256"]
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func rejected(reply: Variant, label: String) -> void:
	check(reply is Dictionary and reply.size()==2 and reply.get("ok")==false and typeof(reply.get("error"))==TYPE_STRING and not reply.error.is_empty(), label)

func reply_shape(reply: Dictionary, is_open: bool, label: String) -> void:
	var expected: Array[String] = READ_FIELDS.duplicate()
	if is_open: expected.append_array(OPEN_FIELDS)
	var actual: Array = reply.keys()
	expected.sort();actual.sort()
	check(actual==expected, label)

func aircraft(reply: Dictionary) -> Dictionary:
	var value: Variant = JSON.parse_string(reply.get("aircraft_json", ""))
	check(value is Dictionary, "Actual aircraft JSON exists")
	return value if value is Dictionary else {}

func system(state: Dictionary, id: String) -> Variant:
	var found: Array = []
	for channel in state.get("systems", []):
		if channel is Dictionary and channel.get("id")==id: found.append(channel)
	check(found.size()==1, "One actual system "+id)
	if found.size()!=1: return null
	var item: Dictionary=found[0]
	check(item.get("quantity")==SYSTEMS[id] and item.get("validity")=="valid", "Actual quantity/validity "+id)
	var value: Variant=item.get("value")
	check(typeof(value)==TYPE_BOOL if SYSTEMS[id]=="bool" else typeof(value)==TYPE_FLOAT or typeof(value)==TYPE_INT, "Actual system type "+id)
	if SYSTEMS[id]!="bool": check(is_finite(float(value)), "Actual finite system "+id)
	return value

func command(state: Dictionary, sequence: int, payload: Dictionary, tick: String="1") -> Dictionary:
	return {"type":"ControlCommand", "schema_version":1, "tick":tick, "session_id":state.session_id, "sequence":str(sequence), "source_id":"pilot.controls", "authority":"pilot", "assistance":{"profile_id":"unassisted", "active":[]}, "payload":payload.duplicate(true)}

func foreign_open(bridge: RefCounted, root: String) -> Dictionary:
	return bridge.call("open_session",root,"piston-cold-ground","calm",PISTON)

func run(legacy_root: String, piston_root: String) -> Dictionary:
	checks=0;failures=[]
	check(ClassDB.class_exists("FlightInteractiveSession"), "Actual extension class available")
	if not ClassDB.class_exists("FlightInteractiveSession"):
		return {"passed":false,"checks":checks,"failures":failures.duplicate()}
	var bridge: RefCounted=ClassDB.instantiate("FlightInteractiveSession") as RefCounted
	# Exercise actual ClassDB default arguments: two, three and four arguments.
	var opened: Dictionary=bridge.call("open_session",legacy_root,"ground-ready")
	check(opened.get("ok")==true and opened.get("wind_profile")=="calm" and opened.has("angular_integration_method") and opened.angular_integration_method==null, "Actual two-argument defaults and null direct method")
	if opened.get("ok")!=true:
		bridge.call("close")
		return {"passed":false,"checks":checks,"failures":failures.duplicate()}
	reply_shape(opened,true,"Closed successful-open field set")
	var before: Dictionary=bridge.call("read_state")
	reply_shape(before,false,"Closed ordinary copied readback field set")
	check(not before.has("angular_integration_method"), "Open-only method metadata does not change ordinary reply shape")
	var bad_values: Array=[null,false,1,1.0,&"calm",&"original-interactive-prototype",&"original-piston-prop-v1",[],{},"","Calm","unknown"]
	for bad in bad_values:
		rejected(bridge.call("open_session","invalid-model-path","ground-ready",bad), "Reject exact third selector type/ID")
		check(bridge.call("read_state")==before, "Rejected wind preserves current worker/publication")
		rejected(bridge.call("open_session","invalid-model-path","ground-ready","calm",bad), "Reject exact fourth selector type/ID")
		check(bridge.call("read_state")==before, "Rejected profile preserves current worker/publication")
	var unsupported_pairs: Array = [["piston-cold-ground","from-north",PISTON],["piston-cold-ground","from-west",PISTON],["piston-cold-ground","from-east",PISTON],["airborne-prepared","calm",PISTON],["ground-ready","calm",PISTON],["piston-cold-ground","calm",LEGACY]]
	for pair in unsupported_pairs:
		rejected(bridge.call("open_session",piston_root,pair[0],pair[1],pair[2]), "Reject unsupported profile/start/wind pair")
		check(bridge.call("read_state")==before, "Unsupported pair does not replace current worker")
	rejected(bridge.call("open_session",piston_root,"piston-cold-ground",PISTON), "Third-argument piston ID remains an invalid wind")
	check(bridge.call("read_state")==before, "Old worker survives three-argument profile mistake")
	var replacement: Dictionary=bridge.call("open_session","invalid-model-path","ground-ready","calm",LEGACY)
	rejected(replacement, "Existing worker cannot be implicitly replaced")
	check(replacement.get("error")=="Close before a fresh interactive attempt", "Replacement rejects before inspecting invalid root")
	check(bridge.call("read_state")==before, "Bad root replacement request leaves accepted state")
	# Legacy system commands and mixture remain rejected without consuming sequence.
	var state: Dictionary=aircraft(before)
	rejected(bridge.call("submit",command(state,1,{"kind":"system","control_id":"engine.starter","value":true})), "Legacy codec still rejects systems")
	var axes: Dictionary=before.held_axes.duplicate(true);axes.mixture=0.5
	var reply: Dictionary=bridge.call("submit",command(state,1,axes))
	check(reply.get("ok")==true and reply.get("queued")==false and reply.get("rejection")!=0, "Legacy native mixture rejection preserved")
	check(bridge.call("read_state")==before, "Legacy rejected commands preserve publication")
	check(bridge.call("close").get("joined")==true, "Legacy close joins")
	# Fresh selector rejection must precede even inspection of an invalid root.
	for pair in unsupported_pairs:
		var pair_rejected: Dictionary=bridge.call("open_session","invalid-model-path",pair[0],pair[1],pair[2])
		rejected(pair_rejected,"Fresh unsupported pair rejection")
		var expected_error: String="Piston profile supports only piston-cold-ground with calm wind" if pair[2]==PISTON else "Only ground-ready and airborne-prepared starts are supported"
		check(pair_rejected.get("error")==expected_error,"Unsupported pair rejects before native model allocation")
	for bad in bad_values:
		var wind_rejected: Dictionary=bridge.call("open_session","invalid-model-path","ground-ready",bad)
		rejected(wind_rejected,"Fresh third selector rejection")
		check(wind_rejected.get("error")=="Wind profile requires an exact String" or wind_rejected.get("error")=="Unknown steady-wind profile","Third selector rejects before native model allocation")
		var fresh_rejected: Dictionary=bridge.call("open_session","invalid-model-path","ground-ready","calm",bad)
		rejected(fresh_rejected,"Fresh fourth selector rejection")
		check("Aircraft profile" in fresh_rejected.get("error","") or "Unknown interactive profile" in fresh_rejected.get("error",""), "Fourth selector rejects before native model allocation")
	for wind in WIND:
		opened=bridge.call("open_session",legacy_root,"ground-ready",wind)
		check(opened.get("ok")==true and opened.get("wind_profile")==wind and opened.has("angular_integration_method") and opened.angular_integration_method==null, "Actual three-argument wind semantics "+wind)
		reply_shape(opened,true,"Closed selected-wind open shape "+wind)
		check(bridge.call("close").get("joined")==true, "Selected wind close joins")
	opened=bridge.call("open_session",legacy_root,"ground-ready","calm",LEGACY)
	check(opened.get("ok")==true and opened.get("angular_integration_method")==null, "Explicit four-argument legacy")
	check(bridge.call("close").get("joined")==true, "Explicit legacy close joins")
	opened=bridge.call("open_session",piston_root,"piston-cold-ground","calm",PISTON)
	check(opened.get("ok")==true and typeof(opened.get("angular_integration_method"))==TYPE_STRING and opened.angular_integration_method==METHOD, "Actual checked piston method open metadata")
	if opened.get("ok")!=true:
		bridge.call("close")
		return {"passed":false,"checks":checks,"failures":failures.duplicate()}
	reply_shape(opened,true,"Closed piston open metadata shape")
	state=aircraft(opened)
	check(state.get("tick")=="0" and state.get("systems",[]).size()==10 and opened.held_axes.mixture==0.0 and opened.held_axes.left_brake==1.0 and opened.held_axes.right_brake==1.0, "Native cold tick0/brakes/mixture")
	var cold: Dictionary={"fuel.total":100.0,"engine.throttle":0.0,"engine.mixture":0.0,"propeller.angular_speed":0.0,"engine.running":false,"engine.ignition_left":false,"engine.ignition_right":false,"engine.starter":false,"fuel.feed":true,"engine.starved":false}
	for id in SYSTEMS:
		var observed: Variant=system(state,id)
		# Reuse the existing native cold100kg arithmetic allowance; no new budget.
		check(absf(float(observed)-100.0)<=0.0000000001 if id=="fuel.total" else observed==cold[id], "Actual cold source "+id)
	before=bridge.call("read_state")
	reply_shape(before,false,"Piston tick0 read retains ordinary shape")
	check(aircraft(before)==state and before.held_axes==opened.held_axes,"Opening and reading do not advance cold tick0 or alter held controls")
	# Wrong source/type/authority/assistance and aliases reject without sequence use.
	var valid: Dictionary=command(state,1,{"kind":"system","control_id":"engine.starter","value":true})
	for field in ["control_id","value","extra"]:
		var malformed: Dictionary=valid.duplicate(true)
		if field=="control_id": malformed.payload.control_id="engine.master"
		elif field=="value": malformed.payload.value=1
		else: malformed.payload.extra=false
		rejected(bridge.call("submit",malformed), "Strict piston payload "+field)
	for field in ["source_id","authority","assistance"]:
		var malformed: Dictionary=valid.duplicate(true)
		if field=="source_id": malformed.source_id="scenario.test"
		elif field=="authority": malformed.authority="scenario"
		else: malformed.assistance.active=["automatic"]
		rejected(bridge.call("submit",malformed), "Strict common envelope "+field)
	var future: Dictionary=command(state,1,valid.payload,"2")
	reply=bridge.call("submit",future)
	check(reply.get("ok")==true and reply.get("queued")==false and reply.get("rejection")!=0, "Piston system targets only immediate next tick")
	check(bridge.call("read_state")==before, "All malformed/system timing rejects retain current truth")
	var thread:=Thread.new()
	check(thread.start(foreign_open.bind(bridge,piston_root))==OK, "Foreign four-argument open thread starts")
	var foreign: Variant=thread.wait_to_finish()
	rejected(foreign,"Foreign four-argument open rejected")
	check(bridge.call("read_state")==before, "Foreign profile selection retains worker")
	# One disclosed actual boundary checks codec and native applied-system readback.
	axes=before.held_axes.duplicate(true);axes.mixture=0.25
	var payloads: Array=[axes,{"kind":"system","control_id":"engine.ignition_left","value":true},{"kind":"system","control_id":"engine.ignition_right","value":true},{"kind":"system","control_id":"engine.starter","value":true},{"kind":"system","control_id":"fuel.feed","value":true}]
	for i in payloads.size():
		reply=bridge.call("submit",command(state,i+1,payloads[i]))
		if reply.get("ok")==true: reply_shape(reply,false,"Submit retains ordinary shape "+str(i+1))
		check(reply.get("ok")==true and reply.get("queued")==true and reply.get("rejection")==0, "Accepted prefix native command "+str(i+1))
		if reply.get("queued")!=true:
			bridge.call("close")
			return {"passed":false,"checks":checks,"failures":failures.duplicate()}
	reply=bridge.call("step_fixed",1)
	check(reply.get("ok")==true and reply.get("completed")==1 and reply.get("outcome")=="completed", "One actual fixed boundary completed")
	if reply.get("ok")==true:
		reply_shape(reply,false,"Step retains ordinary shape without open-only getter")
		state=aircraft(reply)
		check(state.get("tick")=="1" and reply.held_axes.mixture==0.25, "Actual tick1 held mixture")
		check(reply.get("applied_commands_json",[]).size()==5, "Five honest separately admitted records")
		for i in mini(reply.get("applied_commands_json",[]).size(),payloads.size()):
			var applied: Variant=JSON.parse_string(reply.applied_commands_json[i])
			check(applied is Dictionary and applied.sequence==str(i+1) and applied.tick=="1" and applied.payload==payloads[i], "Exact actual command echo "+str(i+1))
		for id in ["engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed"]:
			check(system(state,id)==true, "Actual native applied Boolean "+id)
		check(system(state,"engine.mixture")==0.25, "Actual native mixture position")
		# Native Running is independently observed; no throttle/switch inference.
		check(typeof(system(state,"engine.running"))==TYPE_BOOL, "Actual combustion observation")
	check(bridge.call("close").get("joined")==true, "Piston close joins actual worker")
	return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"scope":"actual selector/codec/native status smoke; no aircraft/startup/convergence acceptance"}
