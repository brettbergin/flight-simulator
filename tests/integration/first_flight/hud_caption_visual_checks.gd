extends "res://first_flight_scene_tests/layout_visual_checks.gd"
## Original MIT. Opt-in actual HUD originals; Root owns execution/pixel review.
## PAUSED tick0, released synthetic Raw, no Resume/Run or synthetic flight truth.
const HudChecks=preload("res://instrument_tests/hud_caption_checks.gd")
var _passive_checks: Array[Dictionary]=[]

func _sources() -> Dictionary:
 var result: Dictionary=super._sources()
 for path in ["res://first_flight_scene_tests/visual_checks.gd","res://first_flight_scene_tests/layout_visual_checks.gd","res://cockpit/engine_controls.gd","res://instrument_tests/hud_caption_checks.gd",get_script().resource_path]:
  result[path]={"bytes":FileAccess.get_file_as_bytes(path).size(),"sha256":FileAccess.get_sha256(path)}
 return result

func _layout() -> Dictionary:
 var result: Dictionary=super._layout()
 result["hud_caption_geometry"]=HudChecks.caption_metadata(_scene.panel)
 var physical: Array[Dictionary]=[]
 for index in 6: physical.append(_scene.cockpit_panel._physical_dial_caption(index,HudChecks.TITLES[index],HudChecks.UNITS[index]))
 result["unchanged_physical_captions"]=physical
 result["actual_hud_requested_visible"]=_scene.panel._panel_visible
 result["physical_surface_visible"]=_scene.cockpit.root.is_visible_in_tree()
 return result

func _expected_roster() -> Array[String]:
 var result: Array[String]=[]
 for profile in [Scene.Facade.LEGACY_PROFILE.id,Scene.Facade.PISTON_PROFILE.id]:
  for dimensions in SIZES: result.append("hud-"+profile+"-"+str(dimensions.x)+"-mode1-requested-on.png")
  for mode in [0,3]: result.append("hud-"+profile+"-960-mode"+str(mode)+"-physical-requested-off.png")
  result.append("hud-"+profile+"-960-mode1-requested-off.png")
 return result

func _passive_view(profile: String,dimensions: Vector2i,enabled: bool,label: String) -> void:
 # Camera selection precedes this snapshot. No camera/lifecycle changes are
 # excused by a passive before/after comparison; resize + HUD visibility only.
 await _settle_layout()
 var before: PackedByteArray=var_to_bytes(_authority())
 var source_before: Dictionary=_scene.facade.readback()
 if not (await _at_size(dimensions)): return
 _scene.panel_visible=enabled;_scene.panel.set_panel_visible(enabled)
 await _settle_layout()
 var after: PackedByteArray=var_to_bytes(_authority())
 _check(before==after,"hud_passive_resize_visibility_preserve_entire_authority_"+label)
 _check(_scene.facade.readback()==source_before and source_before.host_mode=="paused" and source_before.tick=="0","hud_passive_actual_PAUSED_tick0_source_exact_"+label)
 _check(_scene.panel._panel_visible==enabled and _scene.panel_visible==enabled,"hud_requested_visibility_preserved_"+label)
 _passive_checks.append({"label":label,"profile":profile,"dimensions":[dimensions.x,dimensions.y],"requested_hud":enabled,"full_binary_authority_equal":before==after,"readback_equal":_scene.facade.readback()==source_before,"camera_mode":_scene.camera_mode,"scope":"Camera selection settled before this witness; only resize and requested HUD on/off inside comparison. Complete original Readback/facade, held intent/debt, mapper/filter/latch, recorder and origin."})

func _profile_views(profile: String) -> void:
 _scene.set_camera_mode(1)
 for dimensions in SIZES:
  var name: String="hud-"+profile+"-"+str(dimensions.x)+"-mode1-requested-on"
  await _passive_view(profile,dimensions,true,name)
  if not _failures.is_empty(): return
  _check(_scene.panel._panel_visible and _scene.camera_mode==1,"hud_actual_requested_CHASE_on_"+name)
  await _shot(name,dimensions,"ACTUAL PAUSED tick0 CHASE HUD requested ON; original source truth, no Resume/Run; actual glyph/row metadata requires independent original-pixel review")
  if not _failures.is_empty(): return
 for mode in [0,3]:
  _scene.set_camera_mode(mode)
  var name: String="hud-"+profile+"-960-mode"+str(mode)+"-physical-requested-off"
  await _passive_view(profile,Vector2i(960,540),false,name)
  if not _failures.is_empty(): return
  var actual: Dictionary=Readings.from_readback(_scene.facade.readback())
  _check(_scene.shared_readings==actual and _scene.panel._readings==_scene.cockpit_panel._readings,"hud_physical_same_actual_source_readings_"+name)
  _check(_scene.cockpit.root.is_visible_in_tree() and _scene.cockpit_panel._cockpit_surface,"hud_actual_physical_surface_requested_"+name)
  await _shot(name,Vector2i(960,540),"ACTUAL PAUSED tick0 physical mode"+str(mode)+"; HUD requested OFF; unchanged physical captions/source, auxiliary locator/gaze limitations remain separate")
  if not _failures.is_empty(): return
 _scene.set_camera_mode(1)
 var name: String="hud-"+profile+"-960-mode1-requested-off"
 await _passive_view(profile,Vector2i(960,540),false,name)
 if not _failures.is_empty(): return
 await _shot(name,Vector2i(960,540),"ACTUAL PAUSED tick0 CHASE; HUD explicitly requested OFF and remains OFF, no forced fallback")

func run_hud(host: Node,output_root: String) -> Dictionary:
 _host=host;_window=host.get_tree().root;_output=output_root
 _checks=0;_failures=[];_views=[];_sessions=[];_map_toggles=[];_map_sequences=[];_passive_checks=[]
 _joined=true;_audio_joined=true
 if not _check(_output_ok(output_root),"hud_fresh_absolute_empty_external_output"): return {"passed":false,"checks":_checks,"failures":_failures}
 if not _check(OS.get_name()=="Windows" and DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()=="gl_compatibility","hud_actual_Windows_Compatibility_GPU"): return {"passed":false,"checks":_checks,"failures":_failures}
 var adapter: String=RenderingServer.get_video_adapter_name().to_lower()
 if not _check(not adapter.is_empty(),"hud_actual_adapter_present"): return {"passed":false,"checks":_checks,"failures":_failures}
 for fallback in ["llvmpipe","softpipe","software","warp","microsoft basic render"]:
  if not _check(not adapter.contains(fallback),"hud_no_software_"+fallback): return {"passed":false,"checks":_checks,"failures":_failures}
 if host is Scene and not _check(host.facade==null,"hud_caller_has_no_owner_flight"): return {"passed":false,"checks":_checks,"failures":_failures}
 _source_before=_sources()
 for path in _source_before: _check(_source_before[path].bytes>0 and str(_source_before[path].sha256).length()==64,"hud_actual_source_present_"+path)
 if not _failures.is_empty(): return {"passed":false,"checks":_checks,"failures":_failures}
 var previous_size: Vector2i=_window.size
 var previous_gui: bool=_window.gui_disable_input
 var previous_mouse: int=Input.mouse_mode
 _window.gui_disable_input=true
 for profile in [Scene.Facade.LEGACY_PROFILE.id,Scene.Facade.PISTON_PROFILE.id]:
  _scene=SyntheticScene.new();host.add_child(_scene)
  _scene.set_process(false);_scene.set_physics_process(false);_scene.set_process_input(false)
  _scene.set_process_unhandled_input(false);_scene.set_process_unhandled_key_input(false);_scene.set_process_shortcut_input(false)
  if _scene.sound!=null: _scene.sound.set_process(false)
  var focus_callback: Callable=Callable(_scene,"on_focus_lost")
  if _window.focus_exited.is_connected(focus_callback): _window.focus_exited.disconnect(focus_callback)
  var device_callback: Callable=Callable(_scene,"on_joy_connection_changed")
  if Input.joy_connection_changed.is_connected(device_callback): Input.joy_connection_changed.disconnect(device_callback)
  if _check(_scene.facade!=null and _scene.mapper!=null and _scene.landmark_board!=null and _scene.engine_controls!=null,"hud_actual_integrated_owners_present_"+profile) and (await _choose_profile(profile)):
   await _profile_views(profile)
  var joined: bool=_scene.close_session()
  _joined=joined and _joined;_check(joined,"hud_finish_actual_native_join_"+profile)
  var audio_joined: bool=true
  if _scene.sound!=null: audio_joined=bool(await _scene.sound.shutdown())
  _audio_joined=audio_joined and _audio_joined;_check(audio_joined,"hud_finish_actual_audio_join_"+profile)
  _check(_scene.failures.is_empty(),"hud_production_scene_clean_"+profile)
  _scene.free();_scene=null
  if not _failures.is_empty(): break
 var actual_roster: Array[String]=[]
 for view in _views: actual_roster.append(view.file)
 _check(actual_roster==_expected_roster() and _views.size()==12,"hud_exact_twelve_original_views")
 var source_after: Dictionary=_sources()
 _check(source_after==_source_before,"hud_all_staged_source_bytes_unchanged")
 DisplayServer.window_set_size(previous_size);_window.size=previous_size
 _window.gui_disable_input=previous_gui;Input.mouse_mode=previous_mouse
 var receipt: Dictionary={"schema":"HUDCaptionVisual/v1","passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),"expected_roster":_expected_roster(),"views":_views.duplicate(true),"sessions":_sessions.duplicate(true),"passive_checks":_passive_checks.duplicate(true),"map_toggles":_map_toggles.duplicate(true),"sources_before":_source_before,"sources_after":source_after,"native_joined":_joined,"audio_joined":_audio_joined,"display_backend":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info(),"editor":OS.has_feature("editor"),"scope":"12 original Windows GPU images and24 paired complete binary truth/layout files over actual PAUSED tick0 native source. Both profiles×3 CHASE HUD-on sizes; both profiles×960 physical0/3 HUD-off; both profiles×960 CHASE HUD-off. Actual chooser/four landmarks; released synthetic Raw/manual render schedule; passive resize/hide full-authority witnesses. No Resume/Run/continuous flight, physical input, forged native truth or pixel acceptance from metadata. Original39/27/29 observers unchanged. Independent original-resolution image review, source/package binding and protected checks remain required. No C172/aircraft/pilot/training-credit or phase acceptance."}
 var path: String=_output.path_join("hud-caption-receipt.json")
 if _check(not FileAccess.file_exists(path),"hud_fresh_receipt"):
  var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
  if _check(file!=null,"hud_receipt_open"):
   receipt.passed=_failures.is_empty();receipt.checks=_checks;receipt.failures=_failures.duplicate()
   file.store_string(JSON.stringify(receipt,"  ",false,true));file.close()
 receipt.passed=_failures.is_empty();receipt.checks=_checks;receipt.failures=_failures.duplicate()
 return receipt
