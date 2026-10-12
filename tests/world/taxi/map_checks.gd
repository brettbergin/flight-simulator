extends RefCounted
# Original MIT. Synthetic presentation DTOs test the real map boundary only.
# No source-qualified Readback, native flight or rendered legibility is claimed.
const Map=preload("res://interactive/flight_map.gd")
var _checks: int=0
var _failures: Array[String]=[]

func _check(value: bool,label: String) -> void:
	_checks+=1
	if not value: _failures.append(label)

func _view() -> Dictionary:
	return {"layout_id":"original-taxi-navigation","layout_revision":1,"state":"active",
		"session_id":"synthetic-map-fixture","tick":"18446744073709551615","qualified":true,"paused":true,"historical":false,
		"itinerary_id":"map-test","itinerary_label":"Synthetic presentation fixture","runway":36,"point_index":0,"point_count":2,
		"target_id":"first","target_label":"Synthetic first reference","target_eus_m":[108.0,0.0,18.0],
		"points":[{"id":"first","label":"Synthetic first reference","point_eus_m":[108.0,0.0,18.0]},{"id":"second","label":"Synthetic second reference","point_eus_m":[82.0,0.0,0.0]}],
		"planar_range_m":109.48972554536795,"anchor_bearing_deg":99.46232220802563,"available":true,"aids_visible":true,"error":""}

func _other_state(map: Control) -> Dictionary:
	return {"zoom":map.extent_m,"runway":map._runway,"position":map._position,"direction":map._direction,
		"valid":map._valid,"session":map._session,"tick":map._publication_tick,"route":map._route.duplicate(true),
		"circuit":map._circuit.duplicate(true),"trail":map._trail.duplicate(),"wind":map._wind_cue.duplicate(true)}

func run(host: Node) -> Dictionary:
	var map: Control=Map.new()
	host.add_child(map)
	map.hide()
	var before: Dictionary=_other_state(map)
	var view: Dictionary=_view()
	_check(map.set_taxi_navigation(view),"valid_full_u64_presentation")
	_check(map._taxi_navigation==view,"complete_owned_view")
	view.points[0].point_eus_m[0]=999.0
	view.target_eus_m[0]=888.0
	view.target_label="mutated"
	_check(map._taxi_navigation==_view(),"caller_mutation_cannot_change_layer")
	_check(_other_state(map)==before,"valid_setter_preserves_other_map_layers")
	var foreign:=Thread.new()
	_check(foreign.start(func(): return map.set_taxi_navigation(null))==OK,"foreign_thread_started")
	_check(foreign.wait_to_finish()==false,"foreign_thread_rejected")
	_check(map._taxi_navigation==_view(),"foreign_thread_does_not_clear_owner_layer")
	for mutation in ["extra","missing","stringname_key","revision_bool","point_count_float","tick_overflow","session_null","historical","duplicate_point","point_int","nested_stringname","target_mismatch","range_int","bearing_range","not_paused_error"]:
		var bad: Dictionary=_view()
		match mutation:
			"extra": bad.extra=true
			"missing": bad.erase("target_label")
			"stringname_key": bad.erase("state"); bad[StringName("state")]="active"
			"revision_bool": bad.layout_revision=true
			"point_count_float": bad.point_count=2.0
			"tick_overflow": bad.tick="18446744073709551616"
			"session_null": bad.session_id=null
			"historical": bad.historical=true
			"duplicate_point": bad.points[1].id="first"
			"point_int": bad.points[1].point_eus_m[0]=82
			"nested_stringname": bad.points[1].erase("id"); bad.points[1][StringName("id")]="second"
			"target_mismatch": bad.target_eus_m[2]=17.0
			"range_int": bad.planar_range_m=0
			"bearing_range": bad.anchor_bearing_deg=360.0
			"not_paused_error": bad.error="not_paused"
		_check(map.set_taxi_navigation(_view()),"seed_"+mutation)
		_check(not map.set_taxi_navigation(bad) and map._taxi_navigation.is_empty(),"reject_and_clear_only_taxi_"+mutation)
		_check(_other_state(map)==before,"preserve_other_layers_"+mutation)
	view=_view(); view.aids_visible=false
	_check(map.set_taxi_navigation(view) and map._taxi_navigation.is_empty(),"hidden_aids_clear_layer")
	view=_view(); view.qualified=false; view.paused=false; view.session_id=null; view.tick=null; view.error="session_mismatch"; view.available=false
	for key in ["target_id","target_label","target_eus_m","planar_range_m","anchor_bearing_deg"]: view[key]=null
	view.points=[]
	_check(map.set_taxi_navigation(view) and map._taxi_navigation.is_empty(),"unqualified_diagnostic_clear_layer")
	view=_view(); view.state="manual-ended"; view.point_index=1; view.available=false
	for key in ["target_id","target_label","target_eus_m","planar_range_m","anchor_bearing_deg"]: view[key]=null
	view.points=[]
	_check(map.set_taxi_navigation(view) and map._taxi_navigation.is_empty(),"manual_ended_has_no_current_target")
	_check(map.set_taxi_navigation(null) and map._taxi_navigation.is_empty(),"explicit_null_clear")
	_check(_other_state(map)==before,"all_setters_preserve_other_map_layers")
	map.free()
	return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),"scope":"Actual map setter admission/copy/foreign-thread/isolation over synthetic presentation DTOs only; no native navigation or rendered legibility"}
