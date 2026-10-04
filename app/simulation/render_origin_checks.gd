extends RefCounted
# Original MIT synthetic renderer transaction checks; no aircraft/backend data.
const Origin = preload("res://simulation/render_origin.gd")
const ANCHOR = [6378137.0, 0.0, 0.0]
const ROTATION = [0.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, -1.0]

class Participant extends Node3D:
	var mode: String = "good"
	var registry: RefCounted
	var peer: Node3D
	var prepare_count: int = 0
	var commit_count: int = 0
	var canonical: Array = [6378139.0, 13.0, 7.0]
	var saved_plan: Dictionary = {}
	func prepare_origin(candidate: Dictionary) -> Variant:
		prepare_count += 1
		var delta: Array = [canonical[0]-candidate.origin_ecef_m[0], canonical[1]-candidate.origin_ecef_m[1], canonical[2]-candidate.origin_ecef_m[2]]
		var local: Array = [0.0, 0.0, 0.0]
		for row in range(3):
			for axis in range(3):
				local[row] += candidate.ecef_to_eus[row*3+axis]*delta[axis]
		var plan: Dictionary = {"ok": true, "error": "", "session_id": candidate.session_id, "version": candidate.version, "data": {"position": Vector3(local[0],local[1],local[2]), "nested": [{"label": "owned"}]}}
		match mode:
			"malformed": plan.extra = 0
			"wrong_type": plan.ok = 1
			"stale_session": plan.session_id = "prior-session"
			"stale_version": plan.version = "0"
			"prepare_fail": plan.ok = false; plan.error = "Fixture prepare rejection"; plan.data = null
			"candidate_mutation": candidate.origin_ecef_m[0] += 1.0
			"prepare_mutation": position.x += 1.0
			"reentrant_prepare": registry.unregister_participant("a-root")
			"object_data": plan.data.resource = RefCounted.new()
			"nan_data": plan.data.samples = PackedFloat64Array([NAN])
			"cross_plan_mutation": peer.saved_plan.data.position = Vector3(999,999,999)
		saved_plan = plan
		return plan
	func commit_origin(plan: Dictionary) -> Variant:
		commit_count += 1
		position = plan.data.position
		if mode == "commit_fail":
			return {"ok": false, "error": "Fixture partial failure"}
		if mode == "commit_malformed":
			return {"ok": true, "error": "", "extra": 0}
		if mode == "reentrant_commit":
			registry.rebase([6378137.0, 1.0, 0.0])
		return {"ok": true, "error": ""}

var _roots: Array[Node3D] = []
func _participant() -> Participant:
	var root: Participant = Participant.new()
	_roots.append(root)
	return root

func _registry(root: Participant, session: String = "origin-fixture") -> RefCounted:
	var registry: RefCounted = Origin.new(session, ANCHOR.duplicate(true), ROTATION.duplicate(true))
	root.registry = registry
	registry.register_participant("a-root", root, ["ownship", "cockpit", "camera"])
	registry.register_participant("z-absent", null, ["world", "light", "spatial_audio", "local_particles"])
	return registry

func run(host: Node) -> Dictionary:
	var root: Participant = _participant()
	var registry: RefCounted = _registry(root)
	var empty: Dictionary = registry.read_origin()
	host.check(empty.keys().size() == 5 and not empty.valid and empty.committed == null, "origin_initial_exact_invalid_shape")
	host.check(not registry.rebase([6378137.0, 1.0, 0.0]).ok and root.prepare_count == 0, "origin_initial_requires_same_anchor")
	var adopted: Dictionary = registry.rebase(ANCHOR.duplicate(true))
	host.check(adopted.keys().size() == 3 and adopted.ok and adopted.origin.valid and adopted.origin.committed.version == "1" and root.position == Vector3(13,2,-7), "origin_initial_adopts_all_categories_and_eus_rotation")
	adopted.origin.committed.origin_ecef_m[0] = 0.0
	adopted.origin.active_ids.clear()
	host.check(registry.read_origin().committed.origin_ecef_m[0] == ANCHOR[0] and registry.read_origin().active_ids == ["a-root"], "origin_result_recursively_owned")
	var candidate: Array = [6378140.0, 2000.0, -900.0]
	var moved: Dictionary = registry.rebase(candidate)
	candidate[0] = 0.0
	host.check(moved.ok and root.position == Vector3(-1987,-1,-907) and registry.read_origin().committed.version == "2" and registry.read_origin().committed.origin_ecef_m[0] == 6378140.0, "origin_ecef_subtract_rotate_before_float_and_copied_input")
	var before: Dictionary = registry.read_origin()
	var prepare_count: int = root.prepare_count
	for bad in [[1.0,2.0], [INF,0.0,0.0], [NAN,0.0,0.0], [1,2,3]]:
		host.check(not registry.rebase(bad).ok, "origin_invalid_scalar_shape_rejected")
	host.check(root.prepare_count == prepare_count and registry.read_origin() == before, "origin_invalid_input_no_version_scene_mutation")
	var missing: RefCounted = Origin.new("missing", ANCHOR, ROTATION)
	host.check(not missing.rebase(ANCHOR).ok, "origin_missing_categories_rejected")
	var wrong_root := Node.new()
	host.check(not registry.register_participant("bad", wrong_root, ["world"]).ok, "origin_nonroot_participant_rejected")
	wrong_root.free()
	host.check(not registry.register_participant("dup", null, ["ownship"]).ok and not registry.register_participant("dup", null, ["bad"]).ok, "origin_duplicate_unknown_category_rejected")
	var child: Participant = Participant.new()
	root.add_child(child)
	child.position = Vector3(0.003,0.2,-0.5)
	host.check(not registry.register_participant("child", child, []).ok, "origin_parent_child_roots_reject_double_shift")
	var child_local: Vector3 = child.position
	host.check(registry.rebase([6378141.0, 4000.0, -900.0]).ok and child.position == child_local, "origin_owned_child_keeps_relative_transform")
	registry.unregister_participant("z-absent")
	host.check(not registry.read_origin().valid and not registry.rebase([6378141.0,6000.0,-900.0]).ok, "origin_registry_change_invalidates_and_forbids_shift_before_readoption")
	registry.register_participant("z-absent", null, ["world","light","spatial_audio","local_particles"])
	host.check(registry.rebase([6378141.0,4000.0,-900.0]).ok, "origin_absent_replacement_complete_same_origin_readoption")

	for mode in ["malformed","wrong_type","stale_session","stale_version","prepare_fail","candidate_mutation","object_data","nan_data","reentrant_prepare"]:
		var probe: Participant = _participant()
		var trial: RefCounted = _registry(probe)
		trial.rebase(ANCHOR)
		probe.mode = mode
		var prior_position: Vector3 = probe.position
		var prior: Dictionary = trial.read_origin()
		var failed: Dictionary = trial.rebase([6378137.0,2100.0,0.0])
		host.check(not failed.ok and failed.origin.valid and not trial._has_terminal_failure() and failed.origin.committed == prior.committed and probe.position == prior_position and probe.commit_count == 1, "origin_"+mode+"_prepare_preserves_coherent_scene")
		probe.mode = "good"
		host.check(trial.rebase([6378137.0,2100.0,0.0]).ok, "origin_"+mode+"_recovery_by_valid_adoption")

	for mode in ["prepare_mutation","commit_fail","commit_malformed","reentrant_commit"]:
		var probe: Participant = _participant()
		var trial: RefCounted = _registry(probe)
		trial.rebase(ANCHOR)
		probe.mode = mode
		var prior: Dictionary = trial.read_origin().committed
		var failed: Dictionary = trial.rebase([6378137.0,2200.0,0.0])
		host.check(not failed.ok and not failed.origin.valid and trial._has_terminal_failure() and failed.origin.committed == prior and not trial.rebase(ANCHOR).ok and not trial.register_participant("extra",null,[]).ok, "origin_"+mode+"_terminal_no_false_old_scene_or_retry")
		host.check(not trial.read_origin().valid and trial.read_origin().committed == prior, "origin_"+mode+"_historical_committed_metadata_retained")

	var first: Participant = _participant()
	var second: Participant = _participant()
	var isolated: RefCounted = Origin.new("owned-plans", ANCHOR, ROTATION)
	isolated.register_participant("a",first,["ownship"])
	isolated.register_participant("b",second,["world"])
	isolated.register_participant("z",null,["cockpit","camera","light","spatial_audio","local_particles"])
	second.mode = "cross_plan_mutation"
	second.peer = first
	host.check(isolated.rebase(ANCHOR).ok and first.position == Vector3(13,2,-7), "origin_stored_plan_ownership_survives_later_participant_alias_mutation")
	second.mode = "commit_fail"
	var last_committed: Dictionary = isolated.read_origin().committed
	var partial: Dictionary = isolated.rebase([6378137.0,2500.0,0.0])
	host.check(not partial.ok and not partial.origin.valid and partial.origin.committed == last_committed and first.position.x == -2487 and second.position.x == -2487, "origin_partial_commit_records_invalid_scene_without_fake_rollback")

	var retired: Participant = _participant()
	var dead: RefCounted = _registry(retired)
	dead.rebase(ANCHOR)
	_roots.erase(retired)
	retired.free()
	host.check(not dead.read_origin().valid and not dead.rebase([6378137.0,2001.0,0.0]).ok, "origin_retired_weak_participant_invalid_before_commit")
	var ancestor: Participant = _participant()
	var descendant: Participant = _participant()
	var hierarchy: RefCounted = Origin.new("hierarchy",ANCHOR,ROTATION)
	hierarchy.register_participant("a",ancestor,["ownship"])
	hierarchy.register_participant("b",descendant,["world"])
	_roots.erase(descendant)
	ancestor.add_child(descendant)
	hierarchy.register_participant("z",null,["cockpit","camera","light","spatial_audio","local_particles"])
	host.check(not hierarchy.rebase(ANCHOR).ok and ancestor.prepare_count == 0, "origin_reparented_overlap_rechecked_at_transaction")
	var capacity: RefCounted = Origin.new("capacity",ANCHOR,ROTATION)
	for index in range(64):
		host.check(capacity.register_participant("p%02d"%index,_participant(),[]).ok, "origin_bounded_registration_"+str(index))
	host.check(not capacity.register_participant("overflow",_participant(),[]).ok and capacity.read_origin().active_ids.size() == 64, "origin_registry_limit64_no_overflow_mutation")
	var large: Participant = _participant()
	var versions: RefCounted = _registry(large)
	versions.rebase(ANCHOR)
	# Explicit internal fault injection covers unreachable runtime counter extremes.
	versions._version = "9223372036854775808"
	host.check(versions.rebase([6378137.0,2100.0,0.0]).origin.committed.version == "9223372036854775809", "origin_version_above_signed64_exact_decimal")
	versions._version = "18446744073709551615"
	var version_before: Dictionary = versions.read_origin()
	host.check(not versions.rebase(ANCHOR).ok and versions.read_origin() == version_before, "origin_uint64_exhaustion_preflight_no_mutation")
	var invalid_rotation: RefCounted = Origin.new("rotation",ANCHOR,[1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0])
	host.check(not invalid_rotation.register_participant("x",null,[]).ok, "origin_reflection_basis_rejected")
	var current: Dictionary = registry.read_origin()
	current.committed.ecef_to_eus[0] = 9.0
	host.check(registry.read_origin().committed.ecef_to_eus == ROTATION, "origin_rotation_readback_owned_fixed_anchor")
	var thread_before: Dictionary = registry.read_origin()
	var thread := Thread.new()
	thread.start(func() -> Dictionary: return registry.register_participant("wrong-thread",null,[]))
	var thread_result: Dictionary = thread.wait_to_finish()
	host.check(not thread_result.ok and not thread_result.origin.valid and registry.read_origin() == thread_before, "origin_nonmain_thread_rejects_without_registry_access_mutation")

	var aircraft: Participant = _participant()
	var camera: Participant = _participant()
	var audio := Node3D.new()
	aircraft.add_child(audio)
	audio.position = Vector3(0.003,0.2,-0.5)
	var geometry: RefCounted = Origin.new("geometry-only",ANCHOR,ROTATION)
	geometry.register_participant("body",aircraft,["ownship","cockpit","spatial_audio","local_particles"])
	geometry.register_participant("camera",camera,["camera"])
	geometry.register_participant("absent",null,["world","light"])
	camera.canonical = [6378139.3,13.5,3.0]
	geometry.rebase(ANCHOR)
	var pixel_max: float = 0.0
	var audio_max: float = 0.0
	var focal: float = 720.0/tan(deg_to_rad(35.0))
	for leg in range(20):
		aircraft.canonical = [6378139.0, float(leg+1)*2100.0+13.0, 7.0]
		camera.canonical = [6378139.3, float(leg+1)*2100.0+13.5, 3.0]
		camera.basis = Basis.from_euler(Vector3(0.02*sin(leg),0.05*cos(leg),0))
		var canonical_before: Array = aircraft.canonical.duplicate(true)
		# Update current canonical positions within the existing committed frame.
		geometry.rebase(geometry.read_origin().committed.origin_ecef_m)
		var view_before: Vector3 = camera.basis.inverse()*(aircraft.position-camera.position)
		var px_before := Vector2(focal*view_before.x/-view_before.z,focal*view_before.y/-view_before.z)
		var audio_before: Vector3 = aircraft.position+aircraft.basis*audio.position-camera.position
		var shifted: Dictionary = geometry.rebase([6378140.0,float(leg+1)*2100.0,0.0])
		var view_after: Vector3 = camera.basis.inverse()*(aircraft.position-camera.position)
		var px_after := Vector2(focal*view_after.x/-view_after.z,focal*view_after.y/-view_after.z)
		var audio_after: Vector3 = aircraft.position+aircraft.basis*audio.position-camera.position
		pixel_max = maxf(pixel_max,px_before.distance_to(px_after))
		audio_max = maxf(audio_max,audio_before.distance_to(audio_after))
		host.check(shifted.ok and aircraft.canonical == canonical_before and audio.position == Vector3(0.003,0.2,-0.5), "origin_repeated_rebase_canonical_child_invariant_"+str(leg))
	host.check(pixel_max <= 0.5 and audio_max <= 0.001, "origin_20_rebases_70deg_2560x1440_halfpixel_millimeter_audio")
	for item in _roots:
		if is_instance_valid(item):
			item.free()
	_roots.clear()
	return {"scope": "synthetic-render-origin-only", "native_calls": 0, "capacity": 64, "session_bound": true, "rebases":20, "projection_error_px":pixel_max, "audio_relative_error_m":audio_max, "projection_fov_vertical_deg":70, "projection_width_px":2560, "projection_height_px":1440}
