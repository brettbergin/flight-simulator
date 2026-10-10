extends RefCounted
# Original MIT. Requires accepted controls and scan integration.
# Uses actual one-executive scene plus explicitly synthetic released Raw only.
const Scene=preload("res://simulation/flight_scene.gd")
const Display=preload("res://interactive/flight_panel.gd")
const Readings=preload("res://cockpit/instruments/native_readings.gd")
const IDS=["tas","attitude","ellipsoid_height","heading_true","body_yaw_rate","vertical_speed"]
const DISPLAY_FIELDS=["tas_kt","ground_kt","pitch_deg","roll_deg","heading_deg","altitude_ft","vsi_fpm","yaw_rate_deg_s","fuel_kg"]
class SyntheticScene extends Scene:
 var synthetic_raw: Dictionary={"keys":[],"mouse_buttons":[],"devices":[]}
 func collect_input_raw(_preset: Dictionary={}) -> Dictionary:
  return synthetic_raw.duplicate(true)

var checks: int=0
var failures: Array=[]
var _host: Node
func _check(ok: bool,label: String)->void:
 checks+=1
 if not ok: failures.append(label)
 _host.check(ok,label)
func _properties(object: Object,names: Array)->Dictionary:
 var result: Dictionary={}
 for name in names:
  var value: Variant=object.get(name)
  result[name]=value.duplicate(true) if value is Dictionary or value is Array else value
 return result
func _capture(scene: Node)->Dictionary:
 return {"readback":scene.facade.readback(),"mapper":_properties(scene.mapper,["_preset","_values","_start","_pins","_edges","_takeover","_configured","_live","_brake_hold"]),"map":_properties(scene.flight_map,["_session","_sample_tick","_trail","_position","_direction","_valid","_heading_valid","_paused","_retained","_clearance_valid","_clearance_m","_runway","extent_m","_landmarks"]),"origin":scene.facade.render_origin.read_origin(),"camera":scene.camera.transform,"camera_fov":scene.camera.fov,"camera_mode":scene.camera_mode,"submitted":scene.submitted_count}
func _shared(scene: Node,label: String)->void:
 _check(scene.panel_viewport.size==Vector2i(2048,1024),label+"_physical_target_2x_pixels")
 _check(scene.cockpit_panel.size==Vector2(1024,512) and scene.cockpit_panel.scale==Vector2(2,2),label+"_physical_logical_layout_preserved")
 _check(scene.cockpit_panel.anchor_left==0.0 and scene.cockpit_panel.anchor_top==0.0 and scene.cockpit_panel.anchor_right==0.0 and scene.cockpit_panel.anchor_bottom==0.0,label+"_physical_fixed_layout_anchors")
 _check(scene.panel_viewport.render_target_update_mode==(SubViewport.UPDATE_ALWAYS if scene.camera_mode in [0,3] else SubViewport.UPDATE_DISABLED),label+"_physical_target_only_updates_in_cockpit")
 var native: Dictionary=scene.facade.readback()
 var expected: Dictionary=Readings.from_readback(native)
 _check(scene.shared_readings==expected,label+"_one_native_truth_readingset")
 _check(scene.scan_panel._reading_set==expected,label+"_scan_owned_same_readings")
 var display: Dictionary=Display.display_readings(expected)
 for field in DISPLAY_FIELDS:
  var present: bool=display.has(field)
  _check(scene.panel._readings.has(field)==present and scene.cockpit_panel._readings.has(field)==present and scene.scan_panel._readings.has(field)==present,label+"_"+field+"_availability")
  if present:
   _check(scene.panel._readings[field]==display[field] and scene.cockpit_panel._readings[field]==display[field] and scene.scan_panel._readings[field]==display[field],label+"_"+field+"_shared_scalar")
func _retire(scene: Node)->void:
 if scene.facade!=null: _check(scene.close_session(),"scan_scene_owned_native_worker_joined")
 if scene.sound!=null: await scene.sound.call("shutdown")
 scene.free()
func run(host: Node)->Dictionary:
 _host=host
 var scene: Node=SyntheticScene.new()
 host.add_child(scene)
 scene.set_process(false)
 _check(scene.facade!=null and scene.mapper!=null and scene.scan_panel!=null,"scan_scene_actual_new_worker_mapper_and_panel")
 if scene.facade==null or scene.mapper==null or scene.scan_panel==null or scene.facade.readback().aircraft==null:
  await _retire(scene)
  return {"passed":false,"checks":checks,"failures":failures,"scope":"Actual initialization unavailable"}
 _check(scene.facade.readback().host_mode=="paused","scan_scene_explicit_start_paused")
 scene.show_state(0.0)
 _shared(scene,"scan_initial")
 var before: Dictionary=_capture(scene)
 for id in IDS:
  scene.open_instrument_scan()
  _check(scene.scan_open and scene.scan_panel.visible and not scene.menu.visible,"scan_scene_open_paused_"+id)
  _check(scene.scan_panel.focus(id) and scene.scan_panel.focused()==id,"scan_scene_focus_"+id)
  _check(not scene.scan_open and scene.menu.visible and scene.paused,"scan_scene_selection_returns_menu_without_resume_"+id)
  _check(_capture(scene)==before,"scan_scene_focus_full_native_mapper_map_origin_camera_invariant_"+id)
  scene.open_instrument_scan()
  scene.scan_panel.clear_focus()
  scene.dismiss_instrument_scan()
  _check(scene.scan_panel.focused()==null and _capture(scene)==before,"scan_scene_paused_dismiss_full_invariant_"+id)
 scene.open_instrument_scan();scene.scan_panel.focus("tas")
 var fixed: Dictionary=scene.facade.readback()
 _check(scene.pause_session(false),"scan_scene_explicit_released_raw_native_resume")
 scene.menu_open=false;scene.menu.hide();scene.show_state(0.0)
 var live: Dictionary=scene.facade.readback()
 _check(live.tick==fixed.tick and live.aircraft==fixed.aircraft and live.atmosphere==fixed.atmosphere and live.held_axes==fixed.held_axes,"scan_scene_resume_no_implicit_physics_step")
 _check(scene.scan_panel.focused()=="tas" and scene.scan_panel.visible,"scan_scene_live_persistent_focus")
 var live_before: Dictionary=_capture(scene)
 _check(not scene.scan_panel.focus("heading_true"),"scan_scene_live_focus_reject")
 scene.scan_panel.clear_focus();scene.dismiss_instrument_scan()
 _check(scene.scan_panel.focused()=="tas" and _capture(scene)==live_before,"scan_scene_live_clear_dismiss_noop_all_state")
 scene.process_input_interval(25000)
 scene.show_state(0.0)
 _check(scene.facade.readback().tick=="3","scan_scene_only_explicit_wall_interval_steps_three_ticks")
 _shared(scene,"scan_actual_tick3")
 _check(scene.pause_session(true),"scan_scene_pause_before_reset")
 scene.named_start="airborne-prepared"
 var old_session: String=scene.facade.readback().session_id
 _check(scene.restart(true),"scan_scene_actual_fresh_start")
 scene.show_state(0.0)
 _check(scene.facade.readback().session_id!=old_session and scene.facade.readback().tick=="0" and scene.scan_panel.focused()==null,"scan_scene_reset_fresh_session_clears_stale_focus")
 _shared(scene,"scan_fresh_airborne")
 var closed: Dictionary=scene.facade.close()
 _check(closed.ok and closed.readback.host_mode=="closed","scan_scene_actual_native_close_confirmed")
 scene.publish_readings(closed.readback,{"view_name":"CLOSED FIXTURE","paused":false,"outcome":"completed","status":"Closed retained"})
 _check(scene.shared_readings.state=="historical" and scene.panel._info.retained and scene.cockpit_panel._info.retained and scene.scan_panel._reading_set.state=="historical","scan_scene_closed_native_truth_explicit_retained_not_live")
 _check(not scene.scan_panel.focus("tas"),"scan_scene_retained_focus_rejected")
 var empty: Dictionary=closed.readback.duplicate(true)
 for key in ["session_id","tick","aircraft","atmosphere","held_axes","native_outcome","named_start","model_identity","native_source_fingerprint","prepared_world_sha256","world_anchor","canonical"]: empty[key]=null
 empty.error="";empty.native_fault="";empty.time_scale=1.0;empty.debt_quanta=0
 # UI-only synthetic empty/invalid readbacks after actual native worker is closed.
 scene.publish_readings(empty,{"view_name":"EMPTY FIXTURE","paused":false,"status":"Empty"})
 _check(scene.shared_readings.state=="empty" and scene.scan_panel.focused()==null and not scene.panel._readings.valid and not scene.cockpit_panel._readings.valid,"scan_scene_empty_clears_all_views")
 var bad: Dictionary=empty.duplicate(true);bad.tick=0.0
 scene.publish_readings(bad,{"view_name":"INVALID FIXTURE","paused":false,"status":"Malformed UI source"})
 _check(scene.shared_readings.state=="invalid" and scene.scan_panel.focused()==null and not scene.panel._readings.valid and not scene.cockpit_panel._readings.valid,"scan_scene_invalid_clears_all_views_never_stale")
 await _retire(scene)
 return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"scope":"Actual bounded one-worker scene with synthetic released input; view-only state preservation, shared scalar identity and explicit lifecycle. No device, GPU, sensor, C172 or phase qualification."}
