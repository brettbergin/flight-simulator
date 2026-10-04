extends RefCounted
const Scan=preload("res://cockpit/instruments/scan_panel.gd")
const UNITS={"tas":"m/s","ground_speed":"m/s","pitch":"rad","bank":"rad","heading_true":"rad","ellipsoid_height":"m","vertical_speed":"m/s","body_yaw_rate":"rad/s","fuel_total":"kg"}
const IDS=["tas","attitude","ellipsoid_height","heading_true","body_yaw_rate","vertical_speed"]
var checks: int=0
var failures: Array=[]
var _host: Node
func _check(ok: bool,label: String)->void:
 checks+=1
 if not ok: failures.append(label)
 _host.check(ok,"scan_"+label)
func _reading_fixture(state: String="paused",session: String="scan-fixture")->Dictionary:
 var channels: Dictionary={}
 var values: Dictionary={"tas":13.0,"ground_speed":5.0,"pitch":0.0,"bank":0.0,"heading_true":0.0,"ellipsoid_height":1000.0,"vertical_speed":-12.0,"body_yaw_rate":0.125,"fuel_total":100.0}
 var unavailable: bool=state in ["empty","invalid"]
 for id in UNITS: channels[id]={"value":null if unavailable else values[id],"unit":UNITS[id],"valid":not unavailable,"error":"No source" if unavailable else ""}
 return {"session_id":null if unavailable else session,"tick":null if unavailable else "18446744073709551615","state":state,"native_truth":true,"readings":channels,"error":"No source" if unavailable else ""}
func _info(state: String="paused")->Dictionary:
 return {"view_name":"SCAN FIXTURE","paused":state=="paused","historical":state=="historical","status":"Pure UI fixture"}
func run(host: Node)->Dictionary:
 _host=host
 var panel=Scan.new()
 host.add_child(panel)
 panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
 var signals={"selected":0,"dismissed":0}
 panel.focus_selected.connect(func(_id: String):signals.selected+=1)
 panel.dismissed.connect(func():signals.dismissed+=1)
 panel.set_readings(_reading_fixture(),_info())
 _check(panel._reading_set.tick=="18446744073709551615","full_uint64_string_unchanged")
 for id in IDS:
  _check(panel.focus(id) and panel.focused()==id,"paused_select_"+id)
 _check(signals.selected==6,"six_real_focus_changes_signal")
 var before: Variant=panel.focused()
 _check(not panel.focus("fuel_total") and panel.focused()==before,"unknown_focus_no_change")
 panel.set_readings(_reading_fixture("live"),_info("live"))
 panel.clear_focus()
 _check(panel.focused()==before,"live_preserves_focus_and_clear_noop")
 _check(not panel.focus("tas") and panel.focused()==before,"live_focus_rejected_unchanged")
 _check(panel.mouse_filter==Control.MOUSE_FILTER_IGNORE,"live_mouse_does_not_capture")
 panel.set_readings(_reading_fixture("historical"),_info("historical"))
 _check(not panel.focus("tas") and panel.focused()==before,"retained_focus_rejected_unchanged")
 panel.set_readings(_reading_fixture("paused","fresh-session"),_info())
 _check(panel.focused()==null,"new_session_clears_focus")
 panel.focus("tas");panel.clear_focus()
 _check(panel.focused()==null and signals.dismissed==1,"paused_back_clears_and_signals")
 var source: Dictionary=_reading_fixture();var info: Dictionary=_info()
 panel.set_readings(source,info)
 source.readings.tas.value=99.0;info.status="MUTATED"
 _check(panel._reading_set.readings.tas.value==13.0 and panel._scan_info.status=="Pure UI fixture","recursive_owned_input_copy")
 _check(absf(panel._readings.tas_kt-13.0*3600.0/1852.0)<2e-12,"si_display_conversion_only")
 var singular: Dictionary=_reading_fixture()
 singular.readings.bank={"value":null,"unit":"rad","valid":false,"error":"Euler singularity"}
 panel.set_readings(singular,_info())
 _check(not panel._instrument_available(1) and panel._instrument_available(0) and not panel._readings.has("roll_deg"),"singular_attitude_no_zero_bank")
 _check(panel.focus("attitude"),"unavailable_dial_can_be_examined_without_fabrication")
 var overflow: Dictionary=_reading_fixture();overflow.readings.body_yaw_rate.value=1e308
 panel.set_readings(overflow,_info())
 _check(not panel._instrument_available(4) and not panel._readings.has("yaw_rate_deg_s"),"display_conversion_overflow_not_nan")
 var huge: Dictionary=_reading_fixture();huge.readings.tas.value=1e150
 panel.set_readings(huge,_info())
 _check(panel._instrument_available(0) and is_finite(panel._readings.tas_kt),"finite_huge_reading_scientific_view_available")
 for state in ["invalid","empty"]:
  panel.focus("tas");panel.set_readings(_reading_fixture(state),_info(state))
  _check(panel.focused()==null and not panel._readings.valid,state+"_auto_clear_no_stale")
 for name in ["unknown_set_key","unknown_info_key","bad_unit","nan_channel","false_truth","wrong_counter_type","contradictory_flags","StringName_unit","invalid_channel_value","missing_channel","StringName_identity","nonfinite_channel","invalid_set_retains_value"]:
  panel.set_readings(_reading_fixture(),_info());panel.focus("tas")
  var value: Dictionary=_reading_fixture();var context: Dictionary=_info()
  match name:
   "unknown_set_key": value.extra=true
   "unknown_info_key": context.extra=true
   "bad_unit": value.readings.tas.unit="kt"
   "nan_channel": value.readings.tas.value=NAN
   "false_truth": value.native_truth=false
   "wrong_counter_type": value.tick=42.0
   "contradictory_flags": context.paused=false
   "StringName_unit": value.readings.tas.unit=StringName("m/s")
   "invalid_channel_value": value.readings.tas.valid=false;value.readings.tas.error="Missing"
   "missing_channel": value.readings.erase("bank")
   "StringName_identity": value.session_id=StringName("scan-fixture")
   "nonfinite_channel": value.readings.tas.value=INF
   "invalid_set_retains_value": value.state="invalid";value.session_id=null;value.tick=null;value.error="Invalid";context=_info("invalid")
  panel.set_readings(value,context)
  _check(panel.focused()==null and not panel._readings.valid and not panel._scan_error.is_empty(),name+"_reject_clear")
 panel.set_readings(_reading_fixture(),_info())
 for dimensions in [Vector2(960,540),Vector2(1920,1080),Vector2(2560,1440)]:
  panel.size=dimensions
  for focused in [false,true]:
   if focused: panel.focus("tas")
   else: panel.clear_focus()
   var layout: Dictionary=panel._scan_layout();var viewport: Rect2=Rect2(Vector2.ZERO,dimensions)
   _check(viewport.encloses(layout.panel),"panel_bounds_"+str(dimensions)+"_"+str(focused))
   _check(layout.panel.encloses(layout.back),"back_inside_panel_"+str(dimensions)+"_"+str(focused))
   for cell in layout.cells: _check(layout.panel.encloses(cell),"dial_inside_panel_"+str(dimensions)+"_"+str(focused))
 for dimensions in [Vector2(960,540),Vector2(1920,1080),Vector2(2560,1440)]:
  panel.size=dimensions;panel.set_readings(_reading_fixture(),_info());panel.focus("tas")
  panel.set_readings(_reading_fixture("historical"),_info("historical"))
  var retained_layout: Dictionary=panel._scan_layout()
  _check(retained_layout.panel.position.y>=128.0,"retained_below_strip_"+str(dimensions))
  _check(Rect2(Vector2.ZERO,dimensions).encloses(retained_layout.panel),"retained_bounds_"+str(dimensions))
 panel.set_readings(_reading_fixture(),_info())
 var shared: Dictionary=panel.display_readings(panel._reading_set)
 _check(panel._readings==shared and panel._display_available==shared.channel_valid,"shared_adapter_exact_scalars_and_availability")
 for fuel in [1e100,-1e308]:
  var text: String=panel._native_number(fuel,1)+" kg"
  _check(panel._font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x<=119.0,"physical_huge_fuel_width_"+str(fuel))
 panel.size=Vector2(960,540);panel.clear_focus()
 var mouse=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=true;mouse.position=panel._scan_layout().cells[0].get_center()
 panel._gui_input(mouse)
 _check(panel.focused()=="tas","paused_gui_selects_reading_only")
 var key=InputEventKey.new();key.keycode=KEY_ESCAPE;key.pressed=true;panel._gui_input(key)
 _check(panel.focused()=="tas","escape_not_captured_as_scan_action")
 mouse.position=Vector2.ZERO;panel._gui_input(mouse)
 _check(panel.focused()==null,"paused_outside_click_dismisses")
 panel.set_readings(_reading_fixture("live"),_info("live"));panel._gui_input(mouse)
 _check(panel.focused()==null,"live_gui_mouse_cannot_change_focus")
 panel.set_state({},{},{},{})
 _check(not panel._readings.valid,"raw_snapshot_entry_cannot_bypass_reading_seam")
 panel.set_readings(huge,_info());panel.focus("tas")
 panel.queue_redraw();await host.get_tree().process_frame;await host.get_tree().process_frame
 panel.queue_free();await host.get_tree().process_frame
 var report={"passed":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Standalone actual Control API over exact synthetic ReadingSet. No controller/native/device/GPU/pilot/phase qualification."}
 return report
