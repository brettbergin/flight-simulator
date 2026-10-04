extends RefCounted
# Original MIT actual adapter/Node3D fixtures; no native or GPU operations.
const Participant = preload("res://simulation/origin_participant.gd")
const Registry = preload("res://simulation/render_origin.gd")
const Frames = preload("res://simulation/canonical_frames.gd")
const ANCHOR = [6378137.0,0.0,0.0]
const ROTATION = [0.0,1.0,0.0,1.0,0.0,0.0,0.0,0.0,-1.0]
func _candidate(version: String, origin: Array = ANCHOR) -> Dictionary:
	return {"session_id":"adapter-fixture","origin_ecef_m":origin.duplicate(true),"ecef_to_eus":ROTATION.duplicate(true),"version":version}
func _node(parent: Node) -> Node3D:
	var node := Node3D.new()
	node.set_script(Participant)
	parent.add_child(node)
	return node
func run(host: Node) -> Dictionary:
	var container := Node3D.new()
	host.add_child(container)
	var root: Node3D = _node(container)
	var child := Node3D.new()
	root.add_child(child)
	child.transform=Transform3D(Basis.from_euler(Vector3(0.1,-0.2,0.3)),Vector3(0.003,0.2,-0.5))
	var child_local: Transform3D=child.transform
	root.transform=Transform3D(Basis.from_euler(Vector3(0.2,0.3,0.4)),Vector3(4,5,6))
	var scene_before: Transform3D=root.transform
	var anchor: Array=ANCHOR.duplicate(true)
	var rotation: Array=ROTATION.duplicate(true)
	var canonical: Array=[13.0,2.0,-7.0]
	var artist:=Basis.from_euler(Vector3(0.15,-0.2,0.1))
	host.check(root.configure("adapter-fixture",anchor,rotation,canonical,artist),"origin_adapter_configure_existing_node")
	anchor[0]=0.0; rotation[0]=9.0; canonical[0]=999.0
	host.check(root.transform==scene_before and child.transform==child_local and root._anchor==ANCHOR and root._canonical_ecef==[6378139.0,13.0,7.0],"origin_adapter_configure_copies_without_scene_mutation")
	host.check(not root.configure("new-session",ANCHOR,ROTATION,[0.0,0.0,0.0]),"origin_adapter_immutable_session_configuration")
	var plan: Dictionary=root.prepare_origin(_candidate("1"))
	host.check(plan.ok and plan.keys().size()==5 and plan.data.keys()==["transform"] and root.transform==scene_before,"origin_adapter_prepare_exact_owned_shape_no_scene_mutation")
	var tampered: Dictionary=plan.duplicate(true)
	tampered.data.transform.origin.x+=1.0
	host.check(not root.commit_origin(tampered).ok and root.transform==scene_before,"origin_adapter_mutated_plan_rejected_without_scene_change")
	host.check(root.commit_origin(plan).ok and root.position==Vector3(13,2,-7) and root.basis==artist and child.transform==child_local,"origin_adapter_commit_exact_translation_artist_rotation_descendants")
	host.check(not root.commit_origin(plan).ok,"origin_adapter_committed_plan_cannot_replay")
	for modification in ["session","version","rotation","extra","nan","integer"]:
		var bad: Dictionary=_candidate("2")
		match modification:
			"session":bad.session_id="prior-session"
			"version":bad.version="1"
			"rotation":bad.ecef_to_eus[0]=0.1
			"extra":bad.extra=true
			"nan":bad.origin_ecef_m[0]=NAN
			"integer":bad.origin_ecef_m=[1,2,3]
		var position_before: Vector3=root.position
		host.check(not root.prepare_origin(bad).ok and root.position==position_before,"origin_adapter_malformed_"+modification+"_no_scene_change")
	var fresh: Dictionary=root.prepare_origin(_candidate("2"))
	host.check(root.set_canonical_pose([6378140.0,20.0,4.0],Basis.IDENTITY) and not root.commit_origin(fresh).ok,"origin_adapter_pose_update_invalidates_prepared_plan")
	var current: Dictionary=root.prepare_origin(_candidate("2",[6378140.0,2000.0,0.0]))
	host.check(root.commit_origin(current).ok and root.position==Vector3(-1980,0,-4) and root.basis==Basis.IDENTITY,"origin_adapter_uses_current_canonical_pose_and_rotation")
	var prepared: Dictionary=root.prepare_origin(_candidate("3"))
	child.position.x+=0.2
	host.check(not root.commit_origin(prepared).ok,"origin_adapter_descendant_changes_after_prepare_rejected")
	child.transform=child_local
	var accepted: Dictionary=root.prepare_origin(_candidate("3"))
	var held: Array=root._canonical_ecef.duplicate(true)
	host.check(not root.set_canonical_pose([NAN,0.0,0.0],Basis.IDENTITY) and not root.set_canonical_pose([1.0,2.0,3.0],Basis.from_scale(Vector3(1,2,1))) and root._canonical_ecef==held and root.commit_origin(accepted).ok,"origin_adapter_invalid_updates_preserve_accepted_canonical_plan")
	child.position.x=NAN
	host.check(not root.prepare_origin(_candidate("4")).ok,"origin_adapter_nonfinite_descendant_rejected")
	child.transform=child_local

	# A fresh session registry receives fresh adapters; direct-test versions cannot replay.
	root = _node(container)
	child = Node3D.new()
	root.add_child(child)
	child.transform = child_local
	root.configure("adapter-fixture",ANCHOR,ROTATION,[13.0,2.0,-7.0],artist)

	# Actual Camera3D accepts the reusable Node3D script without new parenting.
	var camera := Camera3D.new()
	camera.set_script(Participant)
	container.add_child(camera)
	host.check(camera.configure("adapter-fixture",ANCHOR,ROTATION,[1.0,3.0,5.0],Basis.IDENTITY),"origin_adapter_attaches_existing_camera3d")
	var registry: RefCounted=Registry.new("adapter-fixture",ANCHOR,ROTATION)
	registry.register_participant("body",root,["ownship","cockpit"])
	registry.register_participant("camera",camera,["camera"])
	registry.register_participant("absent",null,["world","light","spatial_audio","local_particles"])
	host.check(registry.rebase(ANCHOR).ok,"origin_adapter_actual_registry_initial_adoption")
	var max_error: float=0.0
	for index in range(20):
		var ecef: Array=[6378137.0+float(index)*0.1,float(index)*2100.0+10.0,7.0]
		var basis:=Basis.from_euler(Vector3(0.02*sin(index),0.03*cos(index),0.01*sin(index*0.2)))
		root.set_canonical_pose(ecef,basis)
		var candidate_origin: Array=[6378137.0,float(index)*2100.0,0.0]
		var immutable: Array=ecef.duplicate(true)
		var result: Dictionary=registry.rebase(candidate_origin)
		var expected:=Vector3(10.0,float(index)*0.1,-7.0)
		max_error=maxf(max_error,root.position.distance_to(expected))
		host.check(result.ok and ecef==immutable and root.basis==basis and child.transform==child_local,"origin_adapter_canonical_repeat_artist_child_invariants_"+str(index))
	host.check(max_error<=0.00001,"origin_adapter_20_actual_transactions_no_float_delta_accumulation")
	var before_thread: Transform3D=root.transform
	var thread := Thread.new()
	thread.start(func() -> Dictionary:return root.prepare_origin(_candidate("99")))
	var thread_result: Dictionary=thread.wait_to_finish()
	host.check(not thread_result.ok and root.transform==before_thread,"origin_adapter_wrong_thread_no_scene_or_prepared_mutation")

	# A nonidentity unregistered parent must not double-apply its transform.
	var parent := Node3D.new()
	container.add_child(parent)
	parent.transform=Transform3D(Basis.from_euler(Vector3(0.1,0.2,0.3)),Vector3(5,6,7))
	var nested: Node3D=_node(parent)
	nested.configure("adapter-fixture",ANCHOR,ROTATION,[13.0,2.0,-7.0],artist)
	var nested_plan: Dictionary=nested.prepare_origin(_candidate("1"))
	host.check(nested.commit_origin(nested_plan).ok and nested.global_transform.origin.distance_to(Vector3(13,2,-7))<0.00001 and nested.global_basis.is_equal_approx(artist),"origin_adapter_global_eus_pose_under_nonidentity_parent")
	var parent_plan: Dictionary=nested.prepare_origin(_candidate("2"))
	parent.position.x+=1.0
	host.check(not nested.commit_origin(parent_plan).ok,"origin_adapter_parent_changes_after_prepare_rejected")
	parent.position.x-=1.0
	nested.set_canonical_pose([1e300,-1e300,0.0],Basis.IDENTITY)
	host.check(not nested.prepare_origin(_candidate("2")).ok,"origin_adapter_double_finite_but_float_unrepresentable_projection_rejected")
	var invalid: Node3D=_node(container)
	host.check(not invalid.configure("adapter-fixture",ANCHOR,ROTATION,[0.0,0.0,0.0],Basis.from_scale(Vector3(-1,1,1))),"origin_adapter_reflected_artist_basis_rejected")
	container.free()
	return {"scope":"actual-scene-origin-adapter-only","native_calls":0,"rebases":20,"root_error_m":max_error}
