extends RefCounted
# Original MIT. Separate Windows viewport observations; no training authority.
const Scene=preload("res://simulation/flight_scene.gd")
const Facade=preload("res://simulation/session_facade.gd")
const Observer=preload("res://instrument_tests/cockpit_visual.gd")
const EXTRA_SOURCES: Array[String]=["res://pointer_scene_tests/pointer_visual.gd","res://cockpit/engine_controls.gd"]
class SyntheticScene extends Scene:
 var synthetic_raw: Dictionary={"keys":[],"mouse_buttons":[],"devices":[]}
 func collect_input_raw(_preset: Dictionary={}) -> Dictionary:
  return synthetic_raw.duplicate(true)
var failures: Array[String]=[]
var views: Array[Dictionary]=[]
var scene: Node
var observer: RefCounted
var viewport: Window
var output: String=""
var sources_before: Dictionary={}
var sequence_truth: Dictionary={}
func check(ok: bool,label: String) -> bool:
 if not ok: failures.append(label)
 return ok
func sources() -> Dictionary:
 var result: Dictionary=observer._sources()
 for path in EXTRA_SOURCES:
  result[path]={"bytes":FileAccess.get_file_as_bytes(path).size(),"sha256":FileAccess.get_sha256(path)}
 return result
func truth() -> Dictionary:
 var result: Dictionary=observer._truth()
 result.engine_controls=observer._data(scene.engine_controls)
 return result
func save_truth(name: String,value: Dictionary) -> Dictionary:
 var bytes: PackedByteArray=var_to_bytes(value)
 var path: String=output.path_join(name)
 if not check(not FileAccess.file_exists(path),"fresh_truth_"+name): return {}
 var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
 if not check(file!=null,"truth_open_"+name): return {}
 file.store_buffer(bytes);file.close()
 return {"file":name,"bytes":bytes.size(),"sha256":FileAccess.get_sha256(path)}
func button(control: String,down: bool,fraction: float=0.5) -> void:
 var panel: Control=scene.engine_controls
 var point: Vector2=panel._rects()[control].get_center()
 if control in ["throttle","mixture"]:
  var track: Rect2=panel._track(control)
  point=Vector2(track.position.x+fraction*track.size.x,track.get_center().y)
 var event: InputEventMouseButton=InputEventMouseButton.new()
 event.position=panel.get_global_transform_with_canvas()*point
 event.global_position=event.position
 event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
 event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
 scene.synthetic_raw.mouse_buttons=[1] if down else []
 scene._input(event)
 viewport.push_input(event,true)
func shot(label: String,size: Vector2i,mode: int) -> void:
 # Real gestures use enabled GUI. Resize-only observation cannot add OS motion
 # to the locally pending drag while waiting for two complete frame draws.
 var gui_before: bool=viewport.gui_disable_input
 viewport.gui_disable_input=true
 DisplayServer.window_set_size(size);viewport.size=size
 scene.set_camera_mode(mode);scene.look_angles=Vector2.ZERO
 scene.show_state(0.0)
 var before: Dictionary=truth()
 check(var_to_bytes(before)==var_to_bytes(sequence_truth),"full_truth_unchanged_by_setup_"+label+"_"+str(size.x)+"_"+str(mode))
 await RenderingServer.frame_post_draw
 await RenderingServer.frame_post_draw
 var pixels: Image=viewport.get_texture().get_image()
 var name: String=label+"-"+str(size.x)+"-mode"+str(mode)+".png"
 var path: String=output.path_join(name)
 if check(pixels!=null and pixels.get_size()==size,"dimensions_"+name) and check(not FileAccess.file_exists(path),"fresh_"+name):
  check(pixels.save_png(path)==OK,"saved_"+name)
 var after: Dictionary=truth()
 check(var_to_bytes(before)==var_to_bytes(after),"unchanged_full_truth_"+name)
 var before_pin: Dictionary=save_truth(name+".before.truth",before)
 var after_pin: Dictionary=save_truth(name+".after.truth",after)
 check(before_pin.get("bytes")==after_pin.get("bytes") and before_pin.get("sha256")==after_pin.get("sha256") and not before_pin.is_empty(),"saved_full_truth_exact_"+name)
 views.append({"file":name,"sha256":FileAccess.get_sha256(path),"width":size.x,"height":size.y,"mode":mode,
  "truth_before":observer._digest(before),"truth_after":observer._digest(after),"truth_before_file":before_pin,"truth_after_file":after_pin,
  "native":scene.facade.readback(),
  "pointer":scene.mapper.pointer_view(),"panel":{"rect":str(scene.engine_controls.get_global_rect()),"eligible":scene.engine_controls._eligible,
  "reason":scene.engine_controls._reason,"capture":scene.engine_controls._capture.duplicate(true),"preview":scene.engine_controls._preview,
  "expanded":scene.engine_controls.is_expanded()}})
 viewport.gui_disable_input=gui_before
func view_set(label: String) -> void:
 sequence_truth=truth()
 var native: Dictionary=scene.facade.readback()
 var expected_paused: bool=label.begins_with("paused")
 if not check(native.native_live and not native.historical and native.tick=="0" and native.paused==expected_paused and scene.paused==expected_paused and native.model_identity==Facade.PISTON_PROFILE,"expected_native_state_"+label): return
 if not check(scene.mapper.pointer_view().session_id==native.session_id,"matching_pointer_session_"+label): return
 if label=="unsampled-preview":
  if not check(scene.mapper.pointer_view().capture!=null and scene.mapper.pointer_view().capture.control=="mixture" and is_equal_approx(float(scene.engine_controls._preview),0.75),"expected_unsampled_preview"): return
 check(scene.engine_controls.is_expanded()==(label!="paused-collapsed"),"expected_expansion_"+label)
 for size in [Vector2i(960,540),Vector2i(1920,1080),Vector2i(2560,1440)]:
  for mode in [0,3,1,2]: await shot(label,size,mode)
 check(var_to_bytes(truth())==var_to_bytes(sequence_truth),"full_truth_unchanged_across_sequence_"+label)
func reason_views() -> void:
 for label in ["fixed-throttle","bound-primary","remapped-look-held"]:
  scene.synthetic_raw={"keys":[],"mouse_buttons":[],"devices":[]}
  if not check(scene.pause_session(true),"reason_pause_"+label): return
  var preset: Dictionary=Scene.Mapper.default_preset_v2()
  if label=="fixed-throttle":
   for index in preset.axes.size():
    if preset.axes[index].target=="throttle": preset.axes[index]={"target":"throttle","kind":"fixed","value":0.35}
  elif label=="bound-primary":
   for action in preset.actions:
    if action.id=="both_brakes": action.sources=[{"kind":"mouse_button","button":1}]
  else:
   for action in preset.actions:
    if action.id=="look_hold": action.sources=[{"kind":"physical_keys","keys":[KEY_L]}]
  scene.apply_controls(preset)
  if not check(scene.active_preset==preset,"reason_preset_adopted_"+label): return
  if not check(scene.pause_session(false),"reason_resume_"+label): return
  scene.menu_open=false;scene.menu.hide();scene.engine_controls.set_expanded(true)
  if label=="remapped-look-held":
   scene.synthetic_raw.keys=[KEY_L];scene.process_input_interval(0)
   check(scene.engine_pointer_look_active and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"actual_remapped_look_capture")
  scene.show_state(0)
  check(scene.facade.readback().tick=="0","no_reason_Run_"+label)
  if label=="fixed-throttle": check(scene.engine_controls._control_reason("throttle").contains("35%"),"actual_fixed_binding_reason")
  if label=="bound-primary": check(scene.engine_controls._control_reason("engine.starter").contains("both_brakes"),"actual_primary_binding_reason")
  if label=="remapped-look-held": check(not scene.pointer_ui_eligible() and scene.engine_controls._look_hint.contains("L"),"actual_remapped_look_reason")
  sequence_truth=truth()
  for size in [Vector2i(960,540),Vector2i(2560,1440)]: await shot(label,size,1)
  check(var_to_bytes(truth())==var_to_bytes(sequence_truth),"full_truth_across_reason_"+label)
  scene.synthetic_raw={"keys":[],"mouse_buttons":[],"devices":[]};scene.process_input_interval(0)
func run(host: Node) -> Dictionary:
 viewport=host.get_tree().root
 var gui_before: bool=viewport.gui_disable_input
 var window_before: Vector2i=viewport.size
 var mouse_before: int=Input.mouse_mode
 observer=Observer.new()
 var args: PackedStringArray=OS.get_cmdline_user_args()
 var at: int=args.find("--pointer-visual-output")
 if at>=0 and at+1<args.size() and args.count("--pointer-visual-output")==1 and observer._output_ok(args[at+1]): output=args[at+1]
 if not check(not output.is_empty(),"fresh_absolute_external_output"): return {"passed":false,"failures":failures}
 if not check(OS.get_name()=="Windows" and DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()=="gl_compatibility","actual_Windows_Compatibility_GPU"): return {"passed":false,"failures":failures}
 var adapter: String=RenderingServer.get_video_adapter_name().to_lower()
 if not check(not adapter.is_empty(),"adapter_present"): return {"passed":false,"failures":failures}
 for fallback in ["llvmpipe","softpipe","software","warp","microsoft basic render"]:
  if not check(not adapter.contains(fallback),"no_software_"+fallback): return {"passed":false,"failures":failures}
 sources_before=sources()
 for path in sources_before: check(sources_before[path].bytes>0 and str(sources_before[path].sha256).length()==64,"source_present_"+path)
 scene=SyntheticScene.new();host.add_child(scene)
 scene.set_process(false);scene.set_physics_process(false);scene.set_process_input(false)
 scene.set_process_unhandled_input(false);scene.set_process_unhandled_key_input(false);scene.set_process_shortcut_input(false)
 if scene.sound!=null: scene.sound.set_process(false)
 # View-only resize trials deliberately isolate external focus/device events.
 # Separate host fixtures exercise the production loss/rearm callbacks.
 var focus_callback: Callable=Callable(scene,"on_focus_lost")
 if viewport.focus_exited.is_connected(focus_callback): viewport.focus_exited.disconnect(focus_callback)
 var device_callback: Callable=Callable(scene,"on_joy_connection_changed")
 if Input.joy_connection_changed.is_connected(device_callback): Input.joy_connection_changed.disconnect(device_callback)
 observer._scene=scene
 var initialized: bool=check(scene.facade!=null and scene.mapper!=null,"ordinary_owners_present")
 if initialized: initialized=check(scene.restart(true,"calm","original-piston-prop-v1","piston-cold-ground"),"actual_cold_adoption")
 if initialized: initialized=check(scene.pause_session(false),"explicit_resume")
 if initialized:
  scene.menu_open=false;scene.menu.hide()
  scene.engine_controls.set_expanded(true);scene.show_state()
  await host.get_tree().process_frame
  await view_set("live-expanded")
  scene.set_camera_mode(0);scene.show_state()
  button("mixture",true,0.75)
  check(scene.mapper.pointer_view().capture!=null,"real_GUI_preview_capture")
  check(scene.engine_controls._preview!=null,"actual_local_preview")
  await view_set("unsampled-preview")
  button("mixture",false,0.75);scene.process_input_interval(0)
  check(scene.pause_session(true),"actual_pause")
  scene.menu_open=false;scene.menu.hide();scene.show_state()
  await view_set("paused-expanded")
  scene.engine_controls.set_expanded(false);scene.show_state()
  await view_set("paused-collapsed")
  await reason_views()
 var joined: bool=scene.close_session()
 check(joined,"native_joined")
 var audio_joined: bool=true
 if scene.sound!=null: audio_joined=bool(await scene.sound.shutdown())
 check(audio_joined,"audio_joined")
 check(scene.failures.is_empty(),"production_scene_checks_clean")
 scene.free()
 check(sources_before==sources(),"source_bytes_unchanged")
 DisplayServer.window_set_size(window_before);viewport.size=window_before
 viewport.gui_disable_input=gui_before;Input.mouse_mode=mouse_before
 var receipt: Dictionary={"schema":"PointerEngineVisual/v1","passed":failures.is_empty() and views.size()==54,"failures":failures,
  "views":views,"source_before":sources_before,"source_after":sources(),"native_joined":joined,"audio_joined":audio_joined,
  "display_backend":DisplayServer.get_name(),"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),
  "renderer":RenderingServer.get_current_rendering_method(),"editor":OS.has_feature("editor"),
  "scope":"Fifty-four actual Windows viewport observations with full view-truth invariance, separate GUI preview, fixed/conflicting/remapped binding reasons and complete synthetic Raw. Two-frame samples do not observe every OS presentation. No hardware, pilot, flight performance, sensed/C172 or phase acceptance."}
 var path: String=output.path_join("receipt.json")
 if check(not FileAccess.file_exists(path),"fresh_receipt"):
  var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
  if check(file!=null,"receipt_open"):
   file.store_string(JSON.stringify(receipt,"  ",false,true));file.close()
 receipt.passed=receipt.passed and failures.is_empty()
 return receipt
