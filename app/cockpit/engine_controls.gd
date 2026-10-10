extends Control
## Original MIT. ADR017 copied view and gestures only; the host owns all input admission.
signal gesture_requested(gesture: Dictionary)
signal capture_invalidated(reason: String)
signal denied_press(control: String, reason: String)
signal expansion_changed(expanded: bool)
# Host seam: set_state consumes copied ADR017 pointer_view + actual EngineStatus +
# active InputPreset. eligible is LIVE/profile/modal eligibility independent of
# binding/fixed paint. hit_control supports host preflight before complete Raw.
# Queue exact gesture signals into mapper; denied_press requests normal host pause.
# On lifecycle use retire(); invalidate_local() clears local state without signals.
# Host assigns width before expanded_height(): <600px uses an ADR019 216px sidebar;
# 600..899px uses a 156px strip; >=900px retains the original 140px strip.
# Collapsed height is always 30px; this widget never chooses its host position.
const AXES: Array[String]=["throttle","mixture"]
const SWITCHES: Array[String]=["engine.ignition_left","engine.ignition_right","fuel.feed","engine.starter"]
const LABELS: Dictionary={"throttle":"THROTTLE","mixture":"MIXTURE","engine.ignition_left":"IGN LEFT","engine.ignition_right":"IGN RIGHT","fuel.feed":"FUEL FEED","engine.starter":"HOLD STARTER"}
const INK: Color=Color("e8edf3")
const MUTED: Color=Color("9cafbf")
const ACTUAL: Color=Color("79d7e4")
const REQUESTED: Color=Color("f4d179")
const PREVIEW: Color=Color("ffac72")
var _pointer: Dictionary={}
var _engine: Dictionary={}
var _preset: Dictionary={}
var _eligible: bool=false
var _reason: String="No live original piston session"
var _look_hint: String=""
var _hover: String=""
var _expanded: bool=true
var _capture: Dictionary={}
var _preview: Variant=null
var _terminal: bool=false
var _await_release: bool=false
var _font: Font=ThemeDB.fallback_font
var _status_label: Label

func _init() -> void:
	_status_label=Label.new()
	_status_label.visible=false
	_status_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_status_label.text_overrun_behavior=TextServer.OVERRUN_NO_TRIMMING
	_status_label.add_theme_font_size_override("font_size",10)
	_status_label.add_theme_color_override("font_color",MUTED)
	add_child(_status_label)

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	focus_mode=Control.FOCUS_NONE
	custom_minimum_size=Vector2(0,expanded_height())
	visibility_changed.connect(_visibility_changed)
	resized.connect(_layout_resized)

func _compact() -> bool:
	return size.x<600.0

func _medium() -> bool:
	return size.x>=600.0 and size.x<900.0

func _label_pixels(control: String, width: float) -> int:
	if _medium():
		for pixels in [11,10,9]:
			if _font.get_string_size(LABELS[control],HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x<=width: return pixels
		return 9
	return 11

func _fit_text(value: String, width: float, pixels: int) -> String:
	if _font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x<=width: return value
	var shortened: String=value
	while not shortened.is_empty():
		shortened=shortened.left(shortened.length()-1)
		if _font.get_string_size(shortened+"…",HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x<=width: return shortened+"…"
	return ""

func _compact_look_text() -> String:
	# The host supplies its current remapped look binding. Reserve release guidance
	# even when that binding needs an explicit ellipsis; the full hint stays in the
	# tooltip. Captured mouse look cannot rely on hover to discover its release.
	if _look_hint.is_empty(): return "Look unavailable · open Controls"
	if not _look_hint.begins_with("Look: "): return "Release mouse look · open Controls"
	var binding: String=_look_hint.trim_prefix("Look: ")
	var release_at: int=binding.find(" · release")
	if release_at>=0: binding=binding.left(release_at)
	else:
		var extra_at: int=binding.find(";")
		if extra_at>=0: binding=binding.left(extra_at)
	var prefix: String="Look: "
	var suffix: String=" · release to use"
	if _font.get_string_size(prefix+binding+suffix,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x<=size.x-16: return prefix+binding+suffix
	while not binding.is_empty():
		binding=binding.left(binding.length()-1)
		if _font.get_string_size(prefix+binding+"…"+suffix,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x<=size.x-16: return prefix+binding+"…"+suffix
	# Below the supported minimum, keep the action intact; a bounds check must
	# reject the presentation rather than trim the release instruction.
	return prefix+"…"+suffix

func _layout_resized() -> void:
	if not _capture.is_empty(): retire("Engine controls resized")
	if custom_minimum_size.y!=expanded_height(): custom_minimum_size.y=expanded_height()
	_refresh_presentation()

func expanded_height() -> float:
	return (216.0 if _compact() else (156.0 if _medium() else 140.0)) if _expanded else 30.0

func _header_text() -> String:
	if _compact(): return ("▾" if _expanded else "▸")+" ENGINE CONTROLS · PROTOTYPE"
	return ("▾ COLLAPSE" if _expanded else "▸ EXPAND")+" ENGINE CONTROLS · PROTOTYPE"

func _legend_text() -> String:
	return "A actual · R request · orange P preview" if _compact() else "ACTUAL cyan · REQUEST gold · PREVIEW orange"

func is_expanded() -> bool:
	return _expanded

func set_expanded(value: bool) -> void:
	if value==_expanded: return
	if not value: retire("Engine controls collapsed")
	_expanded=value
	custom_minimum_size.y=expanded_height()
	expansion_changed.emit(value)
	_refresh_presentation()

func invalidate_local(_reason_value: String="") -> void:
	_capture.clear();_preview=null;_terminal=false;_await_release=true
	_refresh_presentation()

func retire(reason: String) -> void:
	# The host invalidates mapper metadata/rearm. Actual feedback is never cleared.
	invalidate_local(reason)
	capture_invalidated.emit(reason)

func _visibility_changed() -> void:
	if not is_visible_in_tree(): retire("Engine controls hidden")

func _exit_tree() -> void:
	retire("Engine controls retired")

func set_state(pointer_view: Dictionary, engine_status: Dictionary, active_preset: Dictionary, eligible: bool, reason: String="", look_hint: String="") -> void:
	var old_session: Variant=_pointer.get("session_id")
	var old_generation: Variant=_pointer.get("generation")
	_pointer=pointer_view.duplicate(true)
	_engine=engine_status.duplicate(true)
	_preset=active_preset.duplicate(true)
	_look_hint=look_hint
	_eligible=eligible and _engine.get("state")=="live" and _engine.get("native_truth")==true and _pointer.get("session_id") is String and _pointer.get("session_id")==_engine.get("session_id") and _pointer.get("requested_axes") is Dictionary and _pointer.get("requested_systems") is Dictionary and str(_pointer.get("error","")).is_empty()
	_reason=reason if not reason.is_empty() else ("Live · primary left pointer" if _eligible else "Paused / retained / unavailable · resume explicitly")
	if old_session!=_pointer.get("session_id") or old_generation!=_pointer.get("generation") or not _eligible:
		_capture.clear();_preview=null;_terminal=false
	# Real Raw rearm is mapper-owned. No Input polling or fabricated button-up.
	if _pointer.get("rearm_buttons") is Array and 1 in _pointer.rearm_buttons: _await_release=true
	elif _capture.is_empty(): _await_release=false
	if not _capture.is_empty():
		var sampled: Variant=_pointer.get("capture")
		if sampled is Dictionary and sampled.get("token")!=_capture.token:
			_capture.clear();_preview=null;_terminal=false
		elif sampled==null and int(_pointer.get("last_token",0))>=int(_capture.token):
			_capture.clear();_preview=null;_terminal=false
		elif _preview!=null and _requested(_capture.control)==_preview:
			_preview=null
	_refresh_presentation()

func _rects() -> Dictionary:
	var w: float=maxf(size.x,1.0)
	if _compact():
		var column_w: float=maxf((w-24.0)*0.5,1.0)
		var compact_rects: Dictionary={}
		for i in AXES.size(): compact_rects[AXES[i]]=Rect2(8.0+i*(column_w+8.0),32.0,column_w,58.0)
		for i in SWITCHES.size(): compact_rects[SWITCHES[i]]=Rect2(8.0+(i%2)*(column_w+8.0),92.0+floorf(float(i)/2.0)*38.0,column_w,34.0)
		return compact_rects
	var available: float=maxf(w-24.0,1.0)
	var lever_w: float=available*(0.24 if _medium() else 0.245)
	var button_w: float=(available-2.0*lever_w-4.0*8.0)/4.0
	var result: Dictionary={}
	var row_y: float=62.0 if _medium() else 46.0
	for i in AXES.size(): result[AXES[i]]=Rect2(12.0+i*(lever_w+8.0),row_y,lever_w-8.0,54.0)
	var start: float=12.0+2.0*lever_w+8.0
	for i in SWITCHES.size(): result[SWITCHES[i]]=Rect2(start+i*(button_w+8.0),row_y,button_w,54.0)
	return result

func hit_control(local_position: Vector2) -> String:
	# Binding/fixed disabled paint must not bypass host bound-button preflight.
	if not _eligible or not _expanded or not is_visible_in_tree(): return ""
	for control in _rects():
		if _rects()[control].has_point(local_position): return control
	return ""

func _axis_binding(control: String) -> Dictionary:
	for axis in _preset.get("axes",[]):
		if axis is Dictionary and axis.get("target")==control: return axis
	return {}

func _button_binding(value: Variant, path: String="preset") -> String:
	if value is Dictionary:
		if value.get("kind")=="mouse_button" and value.get("button")==1: return path
		for key in value:
			var found: String=_button_binding(value[key],path+"/"+str(value.get("id",value.get("target",key))))
			if not found.is_empty(): return found
	elif value is Array:
		for i in value.size():
			var found: String=_button_binding(value[i],path+"/"+str(i))
			if not found.is_empty(): return found
	return ""

func _actual(control: String) -> Variant:
	var id: String="engine."+control if control in AXES else control
	var readings: Variant=_engine.get("readings")
	if not readings is Dictionary: return null
	var channel: Variant=readings.get(id)
	if not channel is Dictionary or channel.get("valid")!=true: return null
	var value: Variant=channel.get("value")
	if control in AXES:
		return float(value) if (value is float or value is int) and is_finite(float(value)) and float(value)>=0.0 and float(value)<=1.0 else null
	return value if value is bool else null

func _binding_caption(path: String) -> String:
	for category in ["actions","systems","axes"]:
		for binding in _preset.get(category,[]):
			var id: String=str(binding.get("id",binding.get("target","")))
			if not id.is_empty() and path.contains("/"+id+"/"):
				return id.replace("."," ").replace("_"," ").capitalize()
	return "another control"

func _requested(control: String) -> Variant:
	var group: Variant=_pointer.get("requested_axes" if control in AXES else "requested_systems")
	if not group is Dictionary: return null
	var value: Variant=group.get(control)
	if control in AXES:
		return float(value) if (value is float or value is int) and is_finite(float(value)) and float(value)>=0.0 and float(value)<=1.0 else null
	return value if value is bool else null

func _control_reason(control: String) -> String:
	if not _eligible: return _reason
	var conflict: String=_button_binding(_preset)
	if not conflict.is_empty(): return "Left bound: "+conflict+" · release / remap in Controls"
	if control in AXES:
		var axis: Dictionary=_axis_binding(control)
		if axis.get("kind")=="fixed": return "Fixed %.0f%% · remap in Controls"%(float(axis.get("value",0.0))*100.0)
	if _actual(control)==null or _requested(control)==null: return "Native/requested channel unavailable"
	if _await_release or (_pointer.get("rearm_buttons") is Array and 1 in _pointer.rearm_buttons): return "Release left button before a fresh press"
	return ""

func _track(control: String) -> Rect2:
	var rect: Rect2=_rects()[control]
	if _compact(): return Rect2(rect.position.x+10.0,73.0,rect.size.x-20.0,10.0)
	return Rect2(rect.position+Vector2(10,29),Vector2(rect.size.x-20,12))

func _axis_value(control: String, x: float) -> float:
	var track: Rect2=_track(control)
	return clampf((x-track.position.x)/track.size.x,0.0,1.0)

func _emit(phase: String, value: Variant) -> void:
	var gesture: Dictionary={"session_id":_capture.session_id,"generation":_capture.generation,"token":_capture.token,"control":_capture.control,"phase":phase,"button":1,"value":value}
	gesture_requested.emit(gesture.duplicate(true))

func _begin(control: String, position_value: Vector2) -> void:
	if not _capture.is_empty() or _pointer.get("capture")!=null: return
	var reason: String=_control_reason(control)
	if not reason.is_empty(): denied_press.emit(control,reason);return
	var token: int=int(_pointer.get("last_token",0))+1
	if token>2147483647: denied_press.emit(control,"Pointer tokens exhausted · fresh attempt required");return
	var value: Variant=_requested(control)
	if control in AXES:
		var track: Rect2=_track(control)
		var thumb: float=track.position.x+float(value)*track.size.x
		if absf(position_value.x-thumb)>9.0: value=_axis_value(control,position_value.x)
	elif control=="engine.starter": value=true
	else: value=not bool(value)
	_capture={"session_id":_pointer.session_id,"generation":int(_pointer.generation),"token":token,"control":control,"button":1}
	_terminal=false;_preview=value
	_emit("begin",value)
	_refresh_presentation()

func _end(cancel: bool=false) -> void:
	if _capture.is_empty() or _terminal: return
	var control: String=_capture.control
	var value: Variant=null if cancel or control not in AXES else (_preview if _preview!=null else _requested(control))
	if control=="engine.starter" and not cancel:
		value=false
		_preview=false
	_terminal=true
	if cancel: _preview=null
	if control=="engine.starter": _await_release=true
	_emit("cancel" if cancel else "end",value)
	_refresh_presentation()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover=hit_control(event.position)
		_refresh_presentation()
	if event is InputEventMouseButton:
		if event.button_index!=MOUSE_BUTTON_LEFT: return
		if not event.pressed:
			_end();_await_release=false;accept_event();return
		if Rect2(0,0,size.x,30).has_point(event.position):
			set_expanded(not _expanded);accept_event();return
		var control: String=hit_control(event.position)
		if not control.is_empty(): _begin(control,event.position);accept_event()
	elif event is InputEventMouseMotion and not _capture.is_empty() and not _terminal:
		if _capture.control=="engine.starter":
			if not _rects()["engine.starter"].has_point(event.position): _end()
		elif _capture.control in AXES:
			_preview=_axis_value(_capture.control,event.position.x)
			_emit("move",_preview)
		_refresh_presentation();accept_event()

func _text(at: Vector2,value: String,color: Color=INK,pixels: int=12,max_width: float=-1) -> void:
	draw_string(_font,at,value,HORIZONTAL_ALIGNMENT_LEFT,max_width,pixels,color)

func _display(value: Variant) -> String:
	if value==null: return "—"
	return ("ON" if value else "OFF") if value is bool else "%.0f%%"%(float(value)*100.0)

func _keys_hint(keys: Array) -> String:
	var names: PackedStringArray=[]
	for key in keys: names.append(OS.get_keycode_string(int(key)))
	return "/".join(names) if not names.is_empty() else "none"

func _source_hint(source: Dictionary) -> String:
	match source.get("kind"):
		"physical_keys": return _keys_hint(source.get("keys",[]))
		"mouse_button": return "Mouse "+str(source.get("button","?"))
		"joy_button": return "Button %s:%s"%[source.get("slot","?"),source.get("index","?")]
	return "Unknown binding"

func _binding_hint(control: String) -> String:
	if control in AXES:
		var binding: Dictionary=_axis_binding(control)
		match binding.get("kind"):
			"fixed": return "Fixed %.0f%%"%(float(binding.get("value",0.0))*100)
			"key_pair": return "%s − / %s + · release to drag"%[_keys_hint(binding.get("negative",[])),_keys_hint(binding.get("positive",[]))]
			"joy_axis": return "Axis %s:%s · release arms .03 pickup"%[binding.get("slot","?"),binding.get("index","?")]
	var sources: PackedStringArray=[]
	for binding in _preset.get("systems",[]):
		if binding is Dictionary and binding.get("id")==control:
			for source in binding.get("sources",[]): sources.append(_source_hint(source))
	return ("Hold · leave releases" if control=="engine.starter" else "Desired click")+" · "+(" / ".join(sources) if not sources.is_empty() else "no physical alias")

func _pending_text() -> String:
	var pending: String=_reason
	var conflict: String=_button_binding(_preset)
	if _eligible and not conflict.is_empty(): pending="Left bound: "+_binding_caption(conflict)+" · release / remap in Controls"
	elif _terminal: pending="Release queued · waiting for ordinary sample"
	elif _preview!=null: pending="Orange preview queued · not yet sampled or native-applied"
	elif not _capture.is_empty(): pending="Capture active · gold is sampled request; cyan is actual native"
	elif not _hover.is_empty(): pending=LABELS[_hover]+" · "+(_control_reason(_hover) if not _control_reason(_hover).is_empty() else _binding_hint(_hover))
	return pending

func _refresh_presentation() -> void:
	# Hover and accessibility guidance must not depend on a GPU draw callback.
	tooltip_text=_pending_text()+" · "+(_binding_hint(_capture.control)+" · " if not _capture.is_empty() else "")+_look_hint
	_status_label.visible=_compact() and _expanded
	_status_label.position=Vector2(8,168)
	_status_label.size=Vector2(maxf(1,size.x-16),31)
	_status_label.text=_compact_status_text()
	queue_redraw()

func _compact_denial_category() -> String:
	var lower: String=_reason.to_lower()
	if "input" in lower or "preset" in lower or "device" in lower or "binding" in lower: return "Input unavailable · open Controls"
	if "look" in lower: return "Release mouse look to use controls"
	if "release left button" in lower: return "Release left button before a fresh press"
	if _engine.get("state")=="historical": return "Retained · no current control"
	if _engine.get("state")=="paused": return "Paused · resume explicitly"
	if lower=="paused / retained / unavailable · resume explicitly": return "Unavailable · resume explicitly"
	if "retained" in lower or "historical" in lower: return "Retained · no current control"
	if "paused" in lower: return "Paused · resume explicitly"
	return "Controls unavailable · see full reason"

func _compact_status_text() -> String:
	var rearm: bool=_await_release or (_pointer.get("rearm_buttons") is Array and 1 in _pointer.rearm_buttons)
	var conflict: String=_button_binding(_preset)
	var status: String="Live · left pointer · hover for guidance"
	if not _eligible: status=_compact_denial_category()
	elif not conflict.is_empty(): status="Left bound · release / remap in Controls"
	elif _terminal: status="Release queued · awaiting sample"
	elif _preview!=null: status="Preview queued · not native-applied"
	elif not _capture.is_empty(): status="Capture active · A actual / R requested"
	elif not _hover.is_empty() and not _control_reason(_hover).is_empty(): status=_control_reason(_hover)
	elif rearm: return "Release left button before a fresh press"
	if rearm:
		# Two complete category/action rows, never a fake button-up or a clipped
		# reason. Detailed source reason and aliases remain synchronous tooltip.
		if status=="Release left button before a fresh press": return status
		if not conflict.is_empty() and _eligible: status="Left bound · remap in Controls"
		status+="\nRelease left button before a fresh press"
	return status

func _compact_values(control: String) -> Array:
	var result: Array=[["A "+_display(_actual(control)),ACTUAL],["R "+_display(_requested(control)),REQUESTED]]
	if control not in AXES and _capture.get("control")==control and _preview!=null: result.append(["P "+_display(_preview),PREVIEW])
	return result

func _draw_compact() -> void:
	_text(Vector2(8,20 if not _expanded else 13),_header_text(),INK,11,size.x-16)
	if not _expanded: return
	_text(Vector2(8,29),_legend_text(),MUTED,10,size.x-16)
	for control in _rects():
		var rect: Rect2=_rects()[control]
		var color: Color=INK if _control_reason(control).is_empty() else MUTED
		if control not in AXES: draw_style_box(_background(),rect)
		_text(rect.position+Vector2(0,12),LABELS[control],color,11,rect.size.x)
		var x: float=rect.position.x
		for part in _compact_values(control):
			_text(Vector2(x,rect.position.y+(29 if control in AXES else 28)),part[0],part[1],11)
			x+=_font.get_string_size(part[0]+("  " if control in AXES else " "),HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
		if control in AXES:
			var track: Rect2=_track(control)
			draw_style_box(_background(),track)
			var actual: Variant=_actual(control);var requested: Variant=_requested(control)
			if actual!=null: draw_line(Vector2(track.position.x+float(actual)*track.size.x,track.position.y-5),Vector2(track.position.x+float(actual)*track.size.x,track.end.y+5),ACTUAL,3)
			if requested!=null: draw_circle(Vector2(track.position.x+float(requested)*track.size.x,track.get_center().y),5,REQUESTED)
			if _capture.get("control")==control and _preview!=null: draw_circle(Vector2(track.position.x+float(_preview)*track.size.x,track.get_center().y),3,PREVIEW)
	_text(Vector2(8,212),_compact_look_text(),INK,10,size.x-16)

func _draw() -> void:
	draw_style_box(_background(),Rect2(Vector2.ZERO,Vector2(size.x,expanded_height())))
	if _compact():
		_draw_compact()
		return
	_text(Vector2(12,20),_header_text(),INK,10 if _compact() else 12,size.x-24)
	if _expanded or (not _compact() and not _medium()):
		var legend_at: Vector2=Vector2(12,42) if _compact() else (Vector2(12,36) if _medium() else Vector2(maxf(350,size.x-365),20))
		_text(legend_at,_legend_text(),MUTED,10 if _compact() else 11,size.x-24 if _compact() or _medium() else 355)
	if not _expanded: return
	for control in _rects():
		var rect: Rect2=_rects()[control]
		var reason: String=_control_reason(control)
		var color: Color=INK if reason.is_empty() else MUTED
		_text(rect.position+Vector2(0,-5),LABELS[control],color,_label_pixels(control,rect.size.x),rect.size.x)
		if control in AXES:
			var track: Rect2=_track(control)
			draw_style_box(_background(),track)
			var actual: Variant=_actual(control);var requested: Variant=_requested(control)
			_text(rect.position+Vector2(0,12),"A "+_display(actual)+"  R "+_display(requested),color,11,rect.size.x)
			if actual!=null: draw_line(Vector2(track.position.x+float(actual)*track.size.x,track.position.y-5),Vector2(track.position.x+float(actual)*track.size.x,track.end.y+5),ACTUAL,3)
			if requested!=null: draw_circle(Vector2(track.position.x+float(requested)*track.size.x,track.get_center().y),5,REQUESTED)
			if _capture.get("control")==control and _preview!=null: draw_circle(Vector2(track.position.x+float(_preview)*track.size.x,track.get_center().y),3,PREVIEW)
		else:
			draw_style_box(_background(),rect)
			_text(rect.position+Vector2(8,18),"A "+_display(_actual(control)),ACTUAL,12,rect.size.x-12)
			_text(rect.position+Vector2(8,34),"R "+_display(_requested(control)),REQUESTED,12,rect.size.x-12)
			if _capture.get("control")==control and _preview!=null: _text(rect.position+Vector2(8,48),"P "+_display(_preview),PREVIEW,11,rect.size.x-12)
		if not _compact():
			_text(rect.position+Vector2(0,68),reason if not reason.is_empty() else _binding_hint(control),MUTED,10,rect.size.x)
	if _compact(): _text(Vector2(12,125),"Hover for bindings / release guidance",MUTED,10,size.x-24)
	var pending: String=_pending_text()
	var conflict: String=_button_binding(_preset)
	# Keep the full state, denial path, release guidance and remapped look hint in
	# tooltip_text. Compact visible status names the condition without suggesting
	# an unsampled request or local preview has already changed native feedback.
	var compact_status: String="Live · left pointer · hover for guidance"
	if not _eligible: compact_status=_reason
	elif not conflict.is_empty(): compact_status="Left bound · release / remap in Controls"
	elif _terminal: compact_status="Release queued · awaiting sample"
	elif _preview!=null: compact_status="Preview queued · not native-applied"
	elif not _capture.is_empty(): compact_status="Capture active · A actual / R requested"
	elif _await_release or (_pointer.get("rearm_buttons") is Array and 1 in _pointer.rearm_buttons): compact_status="Release left button before a fresh press"
	if _compact():
		_text(Vector2(12,284),_fit_text(compact_status,size.x-24,9),MUTED,9,size.x-24)
		_text(Vector2(12,297),_compact_look_text(),INK,9,size.x-24)
	elif _medium():
		_text(Vector2(12,140),_fit_text(pending,size.x-24,9),MUTED,9,size.x-24)
		_text(Vector2(12,153),_fit_text(_look_hint,size.x-24,9),INK,9,size.x-24)
	else:
		_text(Vector2(12,133),pending+" · "+_look_hint,MUTED,11,size.x-24)

func _background() -> StyleBoxFlat:
	var box: StyleBoxFlat=StyleBoxFlat.new()
	box.bg_color=Color("111d29");box.border_color=Color("385568")
	box.set_border_width_all(1);box.set_corner_radius_all(5)
	return box
