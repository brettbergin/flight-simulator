extends Node
# Private original engineering observer. All movement is the unchanged reviewed
# pilot journey; no native-state injection or alternate camera model exists here.
const Existing=preload("res://first_flight_scene_tests/scene_checks.gd")
const CameraWitness=preload("res://camera_tests/scene_checks.gd")
const Checks=preload("res://camera_tests/policy_checks.gd")
const Page=preload("res://camera_tests/panel_checks.gd")
const Journey=preload("res://taxi_tests/pilot_journey.gd")
const Probe=preload("res://taxi_tests/shipping_probe.gd")
var root: Window
var _executed: bool=false
const Identity=preload("res://build/native_identity.gd")
const SIZES=[Vector2i(960,540),Vector2i(1920,1080),Vector2i(2560,1440)]
var checks: int=0
var failures: Array[String]=[]
var views: Array=[]
var binding: Dictionary={}
var current_case: Dictionary={}
var witness: RefCounted=Existing.new()
var camera_witness: RefCounted=CameraWitness.new()
var journey_result: Dictionary={}
var out: String=""
var binding_path: String=""
class CaptureHost extends Node:
	var observer: Variant
	func check(ok: bool,label: String) -> void: observer.check(ok,label)
	func begin_journey(profile: String,start: String,route: String,runway: int) -> void:
		observer.current_case={"profile":profile,"start":start,"return":route,"runway":runway}
	func observe_checkpoint(scene: Node,label: String) -> bool:
		return await observer.observe_checkpoint(scene,label)

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label)
	print("TAXI_CAMERA_CHECK ",label," ",ok)
func _frames(count: int=4) -> void:
	for index in range(count): await get_tree().process_frame
func _write(path: String,raw: PackedByteArray) -> bool:
	if FileAccess.file_exists(path): return false
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file==null: return false
	file.store_buffer(raw); file.close()
	return FileAccess.get_file_as_bytes(path)==raw
func _authority(scene: Node) -> Dictionary:
	return {"snapshot":witness._snapshot(scene),"ledger":witness._ledger(scene),"raw":scene.synthetic_raw.duplicate(true)}
func _rebase_authority(scene: Node) -> Dictionary:
	# Decode only our own typed snapshot, retaining its complete fields. The
	# origin transaction alone legitimately changes the committed origin/version.
	var snapshot: Dictionary=bytes_to_var(witness._snapshot(scene))
	snapshot.erase("origin")
	return {"snapshot":snapshot,"ledger":witness._ledger(scene),"raw":scene.synthetic_raw.duplicate(true)}
func _camera(scene: Node) -> Dictionary: return camera_witness._camera(scene)
func _bounds(scene: Node,page: String,size: Vector2i) -> Array:
	var rows: Array=[]
	var panel: Control=scene.taxi_panel if page=="taxi" else scene.views_panel
	var names: Array=["Itinerary","BeginItinerary","NextPoint","StopItinerary","ShowAids","Back","TaxiHeading","TaxiSummary","TaxiHint"] if page=="taxi" else ["Preset","Fov","ExternalResponse","RestoreDefaults","Apply","Cancel","ViewsHeading","CurrentView","DraftHint"]
	for name in names:
		var control: Control=panel.find_child(name,true,false) as Control
		var inside: bool=control!=null and Page.inside_ancestors(control,Rect2(Vector2.ZERO,Vector2(size)))
		check(inside,page+"_visible_unclipped_"+name+"_"+str(size.x))
		var row: Dictionary={"name":name,"within_viewport_and_clips":inside}
		if control!=null:
			var rect: Rect2=control.get_global_rect()
			row.rect=[rect.position.x,rect.position.y,rect.size.x,rect.size.y]
			row.visible=control.is_visible_in_tree()
			if control is Label:
				row.text=control.text
				row.visible_lines=control.get_visible_line_count(); row.total_lines=control.get_line_count()
				check(not control.clip_text and control.lines_skipped==0 and control.max_lines_visible==-1 and control.visible_characters==-1 and row.visible_lines==row.total_lines,page+"_complete_text_"+name)
		rows.append(row)
	var default_focus: Control=scene.taxi_panel.get_back_button() if page=="taxi" else scene.views_panel.get_cancel_button()
	check(root.gui_get_focus_owner()==default_focus,page+"_actual_default_focus")
	return rows
func _module_witness(snapshot: PackedByteArray) -> Dictionary:
	var state: Dictionary=bytes_to_var(snapshot)
	var rows: Dictionary={}
	for name in state.native.runtime_modules:
		var key: String=str(name).to_lower()
		var path: String=str(state.native.runtime_modules[name]).replace("\\","/")
		check(not rows.has(key) and binding.expected_modules.has(key),"closed_actual_loaded_module_"+key)
		check(path.get_base_dir().to_lower() in [binding.payload.to_lower(),binding.payload.path_join("bin").to_lower()],"actual_module_inside_copied_shipping_payload_"+key)
		var record: Dictionary={"bytes":FileAccess.get_file_as_bytes(path).size(),"sha256":FileAccess.get_sha256(path)}
		check(record==binding.expected_modules.get(key),"actual_loaded_module_bytes_"+key)
		rows[key]={"path":path,"bytes":record.bytes,"sha256":record.sha256}
	check(rows.size()==7,"actual_all_seven_shipping_modules")
	return rows
func _capture(scene: Node,name: String,size: Vector2i,page: String="") -> void:
	root.size=size; await _frames()
	scene.show_state(0.0); await _frames()
	var source: Dictionary=scene.facade.readback()
	check(source.native_live and source.paused and scene.paused and source.native_source_fingerprint==Identity.SOURCE_FINGERPRINT and source.native_fault.is_empty() and source.error.is_empty(),name+"_actual_valid_paused_source")
	var bounds: Array=_bounds(scene,page,size) if not page.is_empty() else []
	var before: Dictionary={"authority":_authority(scene),"camera":_camera(scene),"navigation":scene.taxi_navigation.observe(source),"map":scene.flight_map.get("_position"),"map_visible":scene.map_visible,"marker_visible":scene._taxi_marker.visible}
	var modules: Dictionary=_module_witness(before.authority.snapshot)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image=root.get_texture().get_image()
	var after: Dictionary={"authority":_authority(scene),"camera":_camera(scene),"navigation":scene.taxi_navigation.observe(scene.facade.readback()),"map":scene.flight_map.get("_position"),"map_visible":scene.map_visible,"marker_visible":scene._taxi_marker.visible}
	check(Checks.exact(before,after),name+"_complete_passive_span_exact")
	check(image!=null and image.get_width()==size.x and image.get_height()==size.y,name+"_actual_dimensions")
	var prefix: String=out.path_join(name)
	check(not FileAccess.file_exists(prefix+".png") and image.save_png(prefix+".png")==OK,name+"_fresh_png")
	check(_write(prefix+"-before.bin",var_to_bytes(before)),name+"_before_binary")
	check(_write(prefix+"-after.bin",var_to_bytes(after)),name+"_after_binary")
	views.append({"name":name,"width":size.x,"height":size.y,"png_sha256":FileAccess.get_sha256(prefix+".png"),"before_sha256":FileAccess.get_sha256(prefix+"-before.bin"),"after_sha256":FileAccess.get_sha256(prefix+"-after.bin"),"profile":source.model_identity.id,"start":source.named_start,"tick":source.tick,"session_id":source.session_id,"checkpoint":current_case.duplicate(true),"settings":scene.camera_view_settings(),"page":page,"bounds":bounds,"runtime_modules":modules})
func _apply(scene: Node,settings: Dictionary) -> void:
	scene.open_menu()
	check(scene.open_views(),"ordinary_open_Views")
	var before: Dictionary=_authority(scene)
	Page.choose(scene.views_panel,settings.preset)
	Page.edit_fov(scene.views_panel,settings.fov_deg)
	Page.response(scene.views_panel,settings.external_response)
	Page.press(scene.views_panel,"Apply")
	check(Checks.exact(scene.camera_view_settings(),settings) and Checks.exact(before,_authority(scene)),"ordinary_Views_apply_only_camera")
	scene.close_menu(); check(scene.pause_session(true),"ordinary_menu_close_then_repause_no_interval")
func _presets(scene: Node,prefix: String) -> void:
	for size in SIZES:
		for preset in Checks.PRESETS:
			_apply(scene,{"preset":preset,"fov_deg":72.0,"external_response":"immediate"})
			await _capture(scene,prefix+"-"+str(size.x)+"-"+preset,size)
func _taxi_pages(scene: Node,prefix: String) -> void:
	for size in SIZES:
		root.size=size; await _frames()
		scene.open_menu(); check(scene.open_taxi(),prefix+"_ordinary_Taxi_open")
		await _capture(scene,prefix+"-"+str(size.x)+"-taxi",size,"taxi")
		var before: Dictionary=_authority(scene)
		var aids: CheckBox=scene.taxi_panel.find_child("ShowAids",true,false) as CheckBox
		var saved_aids: bool=scene.taxi_navigation.observe(scene.facade.readback()).aids_visible
		var saved_map: bool=scene.map_visible
		aids.set_pressed_no_signal(false); aids.toggled.emit(false)
		check(Checks.exact(before,_authority(scene)),"hide_aids_no_native_mapper_recording_calls")
		scene.taxi_panel.get_back_button().pressed.emit()
		check(not scene.taxi_open and scene.paused and scene.menu_open and Checks.exact(before,_authority(scene)),"Back_keeps_paused_and_authority_exact")
		await _capture(scene,prefix+"-"+str(size.x)+"-Back",size)
		scene.close_menu(); check(scene.pause_session(true),"Back_menu_explicit_repause")
		check(not scene._taxi_marker.visible,"actual_optional_world_aids_hidden")
		before=_authority(scene)
		if scene.map_visible: scene.dispatch_input_action("map_toggle")
		check(not scene.map_visible and not scene.flight_map.visible and Checks.exact(before,_authority(scene)),"ordinary_map_hide_authority_exact")
		await _capture(scene,prefix+"-"+str(size.x)+"-map-hidden",size)
		if saved_map!=scene.map_visible: scene.dispatch_input_action("map_toggle")
		scene.open_menu(); check(scene.open_taxi(),"reopen_to_restore_aid_setting")
		aids.set_pressed_no_signal(saved_aids); aids.toggled.emit(saved_aids)
		scene.taxi_panel.get_back_button().pressed.emit()
		scene.close_menu(); check(scene.pause_session(true),"restored_aids_repause")
func _rebase(scene: Node,prefix: String) -> void:
	_apply(scene,{"preset":"chase","fov_deg":72.0,"external_response":"immediate"})
	var origin: Dictionary=scene.facade.render_origin.read_origin().committed
	var original: Array=origin.origin_ecef_m.duplicate()
	var candidate: Array=[]
	for axis in range(3): candidate.append(float(original[axis])+float(origin.ecef_to_eus[axis])*16.0+float(origin.ecef_to_eus[6+axis])*(-8.0))
	for size in SIZES:
		await _capture(scene,prefix+"-"+str(size.x)+"-before-rebase",size)
		var before: Dictionary=_rebase_authority(scene)
		var map_position: Variant=scene.flight_map.get("_position")
		var body: Vector3=scene.airplane.position
		var camera: Vector3=scene.camera.position
		var gaze: Basis=scene.camera.basis
		scene.update_canonical_scene_sources()
		check(scene.facade.render_origin.rebase(candidate).ok,"ordinary_transactional_rebase")
		scene.show_state(0.0)
		var after: Dictionary=_rebase_authority(scene)
		check(Checks.exact(before,after) and scene.flight_map.get("_position")==map_position,"rebase_only_origin_changes_authority_and_map_exact")
		check((scene.airplane.position-(body-Vector3(16.0,0.0,-8.0))).length()<=Checks.POSITION_ERROR and (scene.camera.position-(camera-Vector3(16.0,0.0,-8.0))).length()<=Checks.POSITION_ERROR and (scene.camera.basis.z-gaze.z).length()<=Checks.DIRECTION_ERROR,"existing_B08_camera_body_common_translation_budgets")
		await _capture(scene,prefix+"-"+str(size.x)+"-after-rebase",size)
		scene.update_canonical_scene_sources(); check(scene.facade.render_origin.rebase(original).ok,"restore_origin_transaction")
		scene.show_state(0.0)
func observe_checkpoint(scene: Node,label: String) -> bool:
	var first_case: bool=current_case["return"]=="return-south"
	var initial: bool=label=="actual_initial_paused" and first_case
	var hold_east: bool=current_case.profile=="original-interactive-prototype" and current_case["return"] in ["return-south","return-middle"] and label=="actual_stop_before_runway_crossing"
	var hold_west: bool=current_case.profile=="original-interactive-prototype" and label=="backtaxi_to_"+current_case["return"]+"_stopped"
	if not (initial or hold_east or hold_west): return true
	var initial_failures: int=failures.size()
	var was_paused: bool=scene.paused
	var was_menu: bool=scene.menu_open
	var saved: Dictionary=scene.camera_view_settings()
	# Capture uses ordinary explicit pause; no elapsed wall interval is submitted.
	if not scene.paused: scene.open_menu("Actual measured taxi checkpoint; visual observer pause")
	check(scene.paused,"checkpoint_ordinary_pause")
	var prefix: String=current_case.start+"-"+current_case["return"]+"-"+label
	if initial:
		await _presets(scene,prefix)
		await _taxi_pages(scene,prefix)
		await _rebase(scene,prefix)
	else:
		for size in SIZES:
			for preset in ["cockpit","left_window","right_window"]:
				_apply(scene,{"preset":preset,"fov_deg":72.0,"external_response":"immediate"})
				await _capture(scene,prefix+"-"+str(size.x)+"-"+preset,size)
	_apply(scene,saved)
	if was_menu: scene.open_menu()
	elif not was_paused: scene.close_menu()
	check(scene.paused==was_paused and scene.menu_open==was_menu,"restore_original_paused_menu_lifecycle")
	return failures.size()==initial_failures
func _original_visuals(host: Node) -> void:
	var scene: Node=Existing.SyntheticScene.new()
	scene.set_process(false); scene.set_physics_process(false)
	host.add_child(scene)
	scene.set_process(false); scene.set_process_input(false); scene.set_process_unhandled_input(false); scene.set_process_unhandled_key_input(false)
	check(scene.restart(true,"calm","original-interactive-prototype","airborne-prepared") and scene.pause_session(true),"original_airborne_native_start")
	await _presets(scene,"original")
	for size in SIZES+[Vector2i(1360,768)]:
		root.size=size; await _frames()
		scene.open_menu(); check(scene.open_views(),"original_public_Views")
		await _capture(scene,"original-"+str(size.x)+"-views",size,"views")
		Page.press(scene.views_panel,"Cancel")
	check(scene.close_session(),"original_worker_join")
	if scene.sound!=null: check(bool(await scene.sound.shutdown()),"original_audio_join")
	scene.free()
func execute(path: String,output_root: String,requested_driver: String) -> void:
	if _executed:
		push_error("TAXI_PACKED_CAPTURE_DUPLICATE_EXECUTION");get_tree().quit(1);return
	_executed=true
	root=get_tree().root
	var selected: Dictionary=Probe.request(OS.get_cmdline_user_args())
	if selected.is_empty() or selected.mode!="capture" or selected.binding_path!=path or selected.driver!=requested_driver:
		push_error("TAXI_PACKED_CAPTURE_REQUEST_INVALID");get_tree().quit(1);return
	binding=Probe.admit(path,selected.binding_sha256,"capture")
	if binding.is_empty() or binding.output_root!=output_root:
		push_error("TAXI_PACKED_CAPTURE_BINDING_INVALID");get_tree().quit(1);return
	binding_path=path
	out=output_root
	check(FileAccess.get_sha256(OS.get_executable_path())==binding.executable.sha256 and FileAccess.get_sha256(binding.pck.path)==binding.pck.sha256,"actual_shipping_EXE_and_unchanged_PCK")
	for row in binding.resource_files:
		check(FileAccess.get_file_as_bytes("res://"+row.path).size()==int(row.bytes) and FileAccess.get_sha256("res://"+row.path)==row.sha256,"exact_packed_resource_"+row.path)
	check(DisplayServer.get_name()=="Windows","actual_Windows_graphics")
	check(Identity.SOURCE_FINGERPRINT==binding.source_fingerprint and Identity.SOURCE_VARIANT==binding.source_variant,"actual_current_qualified_native")
	for row in binding.source_files:
		check(FileAccess.get_file_as_bytes(row.path).size()==int(row.bytes) and FileAccess.get_sha256(row.path)==row.sha256,"exact_source_"+row.path)
	check(RenderingServer.get_current_rendering_method()=="gl_compatibility" and RenderingServer.get_current_rendering_driver_name()==requested_driver,"actual_renderer_matches_explicit_request")
	var host: CaptureHost=CaptureHost.new(); host.observer=self; root.add_child(host)
	if failures.is_empty():
		await _original_visuals(host)
		journey_result=await Journey.new().run(host)
		check(journey_result.passed and journey_result.journeys.size()==6,"all_original_complete_six_journeys_still_required")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var result: Dictionary={"schema":"PrivateQualifiedTaxiCameraVisual/v1","passed":failures.is_empty() and views.size()==142,"checks":checks,"failures":failures,"views":views,"journey_result":journey_result,"native_identity":{"source_fingerprint":Identity.SOURCE_FINGERPRINT,"source_variant":Identity.SOURCE_VARIANT},"binding_sha256":FileAccess.get_sha256(binding_path),"execution_context":binding.context,"executable_sha256":FileAccess.get_sha256(OS.get_executable_path()),"pck_sha256":FileAccess.get_sha256(binding.pck.path),"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"display_server":DisplayServer.get_name(),"mouse_mode_after_cleanup":Input.mouse_mode,"scope":"Actual shipping EXE/PCK with fixed packed engineering observer, same142 criteria and unchanged complete pilot journeys. Independent pixels required; no installed-user/FPS/hardware/pilot/phase acceptance."}
	check(_write(out.path_join("visual-receipt.json"),JSON.stringify(result,"  ",false,true).to_utf8_buffer()),"full_precision_fresh_visual_receipt")
	print("TAXI_CAMERA_ROOT_COMPLETE ",JSON.stringify({"passed":result.passed,"images":views.size(),"checks":checks}))
	get_tree().quit(0 if result.passed and failures.is_empty() else 1)
