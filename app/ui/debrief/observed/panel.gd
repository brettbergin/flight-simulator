extends Control
# Original MIT. Recorded presentation only: no simulator, input mapper or scene authority.
const Review = preload("res://replay/observed/review.gd")
const TickMath = preload("res://replay/observed/tick_math.gd")
const Display = preload("res://interactive/flight_panel.gd")
signal dismissed()
signal save_requested()
signal open_requested()
signal current_requested()
const CYAN := Color("78dce9")
const MUTED := Color("a0b5c4")
const AMBER := Color("ffc875")
const GAP := Color("ed8796")
const CHANNELS := ["tas","ground_speed","ellipsoid_height","vertical_speed","fuel_total"]
const NAMES := ["True airspeed (kt)","Ground speed (kt)","Ellipsoid height (ft)","Vertical speed (ft/min)","Fuel (kg)"]
var _review: RefCounted = Review.new()
var _record: Dictionary = {}
var _selection: Dictionary = {}
var _index := 0
var _channel := "tas"
var _open := false
var _title: Label
var _summary: Label
var _instant: Label
var _controls: Label
var _engine: Label
var _scroll: ScrollContainer
var _cursor: HSlider
var _back: Button
var _graph_choice: OptionButton
var _body: Control
var _painting: Control
var _changing := false
var _imported := false
var _file_message: Label
var _save_file: Button
var _open_file: Button
var _current_file: Button
var _details_button: Button
var _details: AcceptDialog
var _details_text: TextEdit
var _context_message := ""
var _busy := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index=35
	var background:=ColorRect.new()
	background.color=Color("101923f5")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(background)
	var margin:=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,18)
	add_child(margin)
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",8)
	margin.add_child(box)
	# Natural wrapping keeps every existing action reachable with imported-file
	# qualifiers/Details at the minimum window; the header never scrolls away.
	var header:=HFlowContainer.new()
	header.add_theme_constant_override("h_separation",8)
	header.add_theme_constant_override("v_separation",8)
	box.add_child(header)
	_title=_label("Recorded flight review",21)
	header.add_child(_title)
	_save_file=_button("Save new review",func():save_requested.emit())
	_save_file.tooltip_text="Save the current paused flight as a new file. Existing files are never overwritten."
	header.add_child(_save_file)
	_open_file=_button("Open review",func():open_requested.emit())
	_open_file.tooltip_text="Open a saved historical review without changing the current airplane."
	header.add_child(_open_file)
	_current_file=_button("This flight",func():current_requested.emit())
	header.add_child(_current_file)
	_details_button=_button("Details",func():_details.popup_centered(Vector2i(720,330)))
	_details_button.hide()
	header.add_child(_details_button)
	_back=_button("Back to paused flight",func():dismissed.emit())
	header.add_child(_back)
	_scroll=ScrollContainer.new()
	_scroll.name="RecordedContentScroll"
	_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	_scroll.follow_focus=true
	box.add_child(_scroll)
	_scroll.get_v_scroll_bar().focus_mode=Control.FOCUS_ALL
	var content:=VBoxContainer.new()
	content.name="RecordedContent"
	content.add_theme_constant_override("separation",8)
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)
	_file_message=_label("",12)
	_file_message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_file_message.hide()
	content.add_child(_file_message)
	_details=AcceptDialog.new()
	_details.title="Recorded review details"
	_details.exclusive=true
	_details_text=TextEdit.new()
	_details_text.editable=false
	_details_text.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	_details_text.custom_minimum_size=Vector2(640,240)
	_details_text.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_details.add_child(_details_text)
	add_child(_details)
	_summary=_label("RECORDED OBSERVATIONS / ORIGINAL PROTOTYPE",13)
	_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_summary)
	var wind_warning:=_label("Saved reviews do not retain wind setup or resume a flight",12)
	wind_warning.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	content.add_child(wind_warning)
	var tools:=HBoxContainer.new()
	tools.add_theme_constant_override("separation",8)
	content.add_child(tools)
	tools.add_child(_button("First",func():select_sample(0)))
	tools.add_child(_button("Previous",func():select_sample(_index-1)))
	_cursor=HSlider.new()
	_cursor.step=1
	_cursor.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_cursor.focus_mode=Control.FOCUS_ALL
	_cursor.tooltip_text="Select an actual captured sample. Arrow keys move between observations."
	_cursor.value_changed.connect(func(value: float):
		if not _changing: select_sample(int(value)))
	tools.add_child(_cursor)
	tools.add_child(_button("Next",func():select_sample(_index+1)))
	tools.add_child(_button("Latest",func():select_sample(_record.get("samples",[]).size()-1)))
	_body=Control.new()
	_body.custom_minimum_size=Vector2(0,130)
	_body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	content.add_child(_body)
	_painting=Control.new()
	_painting.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_painting.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_painting.draw.connect(_draw_recorded)
	_body.add_child(_painting)
	_graph_choice=OptionButton.new()
	for name in NAMES: _graph_choice.add_item(name)
	_graph_choice.item_selected.connect(func(index: int):
		_channel=CHANNELS[index]
		_painting.queue_redraw())
	_graph_choice.tooltip_text="Graph values are sampled native truth; missing channels and skipped targets break the line."
	_body.add_child(_graph_choice)
	_body.resized.connect(func():_graph_choice.position=Vector2(_body.size.x*0.52+12,8))
	_instant=_label("No captured sample",14)
	_instant.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_instant)
	_engine=_label("",13)
	_engine.name="RecordedEngineFacts"
	_engine.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_engine.hide()
	content.add_child(_engine)
	_controls=_label("",13)
	_controls.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_controls)
	var legend:=_label("N ↑  •  Fixed-anchor recorded path  •  Amber: late observation  •  Red: missing target  •  Lines break at gaps",12)
	legend.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	content.add_child(legend)
	_update_text()
	set_open(_open)

func _label(text: String, font_size: int) -> Label:
	var label:=Label.new()
	label.text=text
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",MUTED)
	return label

func _button(text: String, action: Callable) -> Button:
	var button:=Button.new()
	button.text=text
	button.focus_mode=Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size",13)
	button.pressed.connect(action)
	return button

func set_recording(recording: Variant) -> bool:
	# Validate into a new candidate. A rejected file must preserve the previously
	# selected historical view, including its cursor and owned sample.
	var candidate: RefCounted=Review.new()
	if not candidate.set_recording(recording): return false
	if recording==_record and _index>=0: candidate.select(_index)
	_review=candidate
	_record=recording.duplicate(true)
	_selection=_review.selection()
	_index=_selection.sample_index if _selection.get("available",false) else 0
	_update_text()
	return true

func set_file_context(imported: bool, message: String="", busy: bool=false) -> void:
	_imported=imported
	_context_message=message
	_busy=busy
	_update_text()

func _refresh_context(sample_details: String="") -> void:
	_title.text="Opened recorded review" if _imported else "Recorded flight review"
	_current_file.visible=_imported
	for button in [_save_file,_open_file,_current_file,_details_button,_back]: button.disabled=_busy
	# Recovery paths can be long. Keep the graph and controls inside the smallest
	# viewport; full local details remain selectable/copyable in a scrollable view.
	_file_message.text=_context_message.substr(0,160).replace("\n"," · ")+(" … (Details)" if _context_message.length()>160 else "")
	_file_message.visible=not _context_message.is_empty()
	_file_message.tooltip_text="Open Details to select/copy the complete local message and recovery paths."
	_details_button.visible=not _context_message.is_empty() or not sample_details.is_empty()
	_details_text.text=_context_message
	if not sample_details.is_empty():
		_details_text.text+=("\n\n" if not _context_message.is_empty() else "")+_metadata_text()+"\n\n"+sample_details
	_summary.tooltip_text=("OPENED FILE / HISTORICAL. File authorship is unverified; the digest detects corruption only.\n" if _imported else "")+_metadata_text()
	if _imported and not sample_details.is_empty():
		_details_text.text="OPENED FILE / HISTORICAL. File authorship is unverified; the digest detects corruption only.\n\n"+_details_text.text

func _metadata_text() -> String:
	if _record.get("metadata")==null: return ""
	var metadata: Dictionary=_record.metadata
	return "Recorded session: %s\nModel: %s / %s\nSource fingerprint: %s\nPrepared world: %s\nStart: %s / first tick %s"%[metadata.session_id,metadata.model_identity.id,metadata.model_identity.version,metadata.native_source_fingerprint,metadata.prepared_world_sha256,metadata.named_start,metadata.first_tick]

func set_open(value: bool) -> void:
	var newly_open: bool=value and not _open
	_open=value
	visible=value
	mouse_filter=Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	if newly_open and _back!=null: _back.grab_focus()

func select_sample(index: int) -> bool:
	if not _open or _record.is_empty(): return false
	var selected: Dictionary=_review.select(index)
	if not selected.available: return false
	_selection=selected
	_index=index
	_update_text()
	return true

func selection() -> Dictionary:
	return _selection.duplicate(true)

static func _number(value: Variant) -> String:
	if value==null: return "unavailable"
	return String.num_scientific(float(value)) if absf(float(value))>=10000000.0 else "%.2f"%float(value)

func _relative(tick: String) -> Variant:
	# Only a proven bounded difference enters presentation time.
	var difference: Dictionary=TickMath.bounded_difference(tick,_record.metadata.first_tick,144000)
	return float(difference.value)/120.0 if difference.ok else null

func _value(sample: Dictionary, channel: String) -> Variant:
	var reading: Dictionary=sample.readings.readings[channel]
	if not reading.valid: return null
	var factor: float=1.0
	if channel in ["tas","ground_speed"]: factor=Display.MPS_TO_KT
	elif channel=="ellipsoid_height": factor=Display.M_TO_FT
	elif channel=="vertical_speed": factor=Display.MPS_TO_FPM
	var value: float=reading.value*factor
	return value if is_finite(value) else null

func _engine_fact(sample: Dictionary, id: String) -> String:
	# This receives only an owned sample admitted by Review/Values. Invalid
	# channels retain the producer reason; false and zero remain genuine facts.
	var reading: Dictionary=sample.engine_status.readings[id]
	if not reading.valid: return "unavailable: "+reading.error
	if typeof(reading.value)==TYPE_BOOL: return "ON" if reading.value else "OFF"
	if id=="propeller.angular_speed":
		var rpm: float=reading.value*60.0/TAU
		if not is_finite(rpm): return "unavailable (display conversion overflow); captured %s rad/s"%_number(reading.value)
		return _number(rpm)
	return _number(reading.value)

func _engine_text(sample: Dictionary) -> String:
	return ("OPENED FILE / HISTORICAL · " if _imported else "")+"RECORDED ENGINE FACTS / ORIGINAL PISTON PROTOTYPE · tick %s\nFuel (kg) %s · Shaft (RPM) %s · Engine running %s\nActual throttle (fraction) %s · Actual mixture (fraction) %s\nIgnition L %s / R %s · Starter %s · Feed %s · Starved %s"%[sample.tick,
		_engine_fact(sample,"fuel.total"),_engine_fact(sample,"propeller.angular_speed"),_engine_fact(sample,"engine.running"),
		_engine_fact(sample,"engine.throttle"),_engine_fact(sample,"engine.mixture"),
		_engine_fact(sample,"engine.ignition_left"),_engine_fact(sample,"engine.ignition_right"),_engine_fact(sample,"engine.starter"),_engine_fact(sample,"fuel.feed"),_engine_fact(sample,"engine.starved")]

func _update_text() -> void:
	if _title==null: return
	var samples: Array=_record.get("samples",[])
	_current_file.visible=_imported
	_changing=true
	_cursor.max_value=maxi(0,samples.size()-1)
	_cursor.value=_index
	_cursor.editable=not samples.is_empty()
	_changing=false
	if samples.is_empty() or not _selection.get("available",false):
		_summary.text="RECORDED OBSERVATIONS / ORIGINAL PROTOTYPE · No qualified captured flight"
		if _imported: _summary.text="OPENED FILE / HISTORICAL · "+_summary.text
		_instant.text=_selection.get("error","No captured sample")
		_instant.tooltip_text=""
		_controls.text=""
		_controls.tooltip_text=""
		_engine.text=""
		_engine.hide()
		_refresh_context()
		_painting.queue_redraw()
		return
	var first: Dictionary=samples[0]
	var last: Dictionary=samples[-1]
	var tail: Variant=_relative(_record.last_observed_tick)
	var span: String=_number(tail)+" s" if tail!=null else "window clipped at 1200 s; endpoint tick "+_record.last_observed_tick
	var prefix: String=""
	if _record.metadata.first_tick!="0": prefix=" · Recording starts at native tick "+_record.metadata.first_tick+"; earlier flight not recorded"
	var fuel_start: Variant=_value(first,"fuel_total")
	var fuel_end: Variant=_value(last,"fuel_total")
	var delta: Variant=null
	if fuel_start!=null and fuel_end!=null and is_finite(fuel_end-fuel_start): delta=fuel_end-fuel_start
	_summary.text="RECORDED OBSERVATIONS / ORIGINAL PROTOTYPE · 2 Hz target / observed states\n%d samples · %d late · %d skipped (%d tail) · %s · %s%s\nSampled planar track: %s m · Sampled fuel change: %s kg · Last sample tick %s / observed tick %s"%[samples.size(),_record.late_sample_count,_record.skipped_target_count,_record.uncaptured_tail_targets,span,_record.seal_reason if _record.seal_reason!=null else "recording",prefix,_number(_track_length()),_number(delta),last.tick,_record.last_observed_tick]
	if _imported: _summary.text="OPENED FILE / HISTORICAL · "+_summary.text
	var sample: Dictionary=_selection.sample
	var reasons: Array[String]=[]
	for channel in sample.readings.readings:
		var reading: Dictionary=sample.readings.readings[channel]
		if not reading.valid: reasons.append(channel+": "+reading.error)
	_instant.tooltip_text="\n".join(reasons)
	_instant.text="RECORDED sample %d/%d · +%s s · tick %s · target %s · %d ticks late%s\nTAS %s kt · Ground %s kt · Ellipsoid height %s ft · Vertical %s ft/min · Fuel %s kg"%[_index+1,samples.size(),_number(_relative(sample.tick)),sample.tick,sample.target_tick,sample.late_by_ticks," · GAP" if sample.gap_before else "",_number(_value(sample,"tas")),_number(_value(sample,"ground_speed")),_number(_value(sample,"ellipsoid_height")),_number(_value(sample,"vertical_speed")),_number(_value(sample,"fuel_total"))]
	var axes: Dictionary=sample.held_axes
	_controls.text="RECORDED held controls · Roll %s · Pitch %s · Yaw %s · Trim %s · Throttle %s%% · L/R brake %s%% / %s%%"%[_number(axes.roll),_number(axes.pitch),_number(axes.yaw),_number(axes.trim),_number(axes.throttle*100.0),_number(axes.left_brake*100.0),_number(axes.right_brake*100.0)]
	_controls.tooltip_text="Held native axes at this captured instant, not the complete pilot command history. Mixture is fixed at 1 in this original profile."
	_engine.visible=_record.contract_version==2
	_engine.text=_engine_text(sample) if _engine.visible else ""
	if _engine.visible:
		_controls.text+=" · Mixture %s%%"%_number(axes.mixture*100.0)
		_controls.tooltip_text="Held native axes at this captured instant, including mixture; not the complete pilot command history or queued UI requests."
		_refresh_context(_instant.text+"\n\n"+_engine.text+"\n\n"+_controls.text)
	else: _refresh_context()
	_painting.queue_redraw()

func _track_length() -> Variant:
	var total:=0.0
	var samples: Array=_record.samples
	for i in range(1,samples.size()):
		if samples[i].gap_before: continue
		var older: Array=samples[i-1].anchor_eus_position_m
		var newer: Array=samples[i].anchor_eus_position_m
		var dx: float=newer[0]-older[0]
		var dz: float=newer[2]-older[2]
		var square: float=dx*dx+dz*dz
		if not is_finite(square): return null
		total+=sqrt(square)
		if not is_finite(total): return null
	return total

func _draw_recorded() -> void:
	var width: float=_painting.size.x
	var height: float=_painting.size.y
	var map_rect:=Rect2(12,36,width*0.49-24,height-62)
	var graph_rect:=Rect2(width*0.52+12,48,width*0.48-24,height-74)
	for rectangle in [map_rect,graph_rect]:
		_painting.draw_rect(rectangle,Color("192735"))
		_painting.draw_rect(rectangle,Color("41586b"),false)
	_painting.draw_string(ThemeDB.fallback_font,Vector2(12,22),"RECORDED PATH · NORTH ↑",HORIZONTAL_ALIGNMENT_LEFT,-1,13,CYAN)
	if _record.get("samples",[]).is_empty(): return
	var samples: Array=_record.samples
	var min_x: float=samples[0].anchor_eus_position_m[0]
	var max_x:=min_x
	var min_z: float=samples[0].anchor_eus_position_m[2]
	var max_z:=min_z
	var lo:=INF
	var hi:=-INF
	for sample in samples:
		min_x=minf(min_x,sample.anchor_eus_position_m[0]);max_x=maxf(max_x,sample.anchor_eus_position_m[0])
		min_z=minf(min_z,sample.anchor_eus_position_m[2]);max_z=maxf(max_z,sample.anchor_eus_position_m[2])
		var value: Variant=_value(sample,_channel)
		if value!=null: lo=minf(lo,value);hi=maxf(hi,value)
	var extent: float=maxf(10.0,maxf(max_x-min_x,max_z-min_z))
	var map_ok: bool=is_finite(extent) and is_finite(max_x-min_x) and is_finite(max_z-min_z)
	var graph_ok: bool=is_finite(lo) and is_finite(hi) and is_finite(hi-lo)
	var map_scale: float=minf(map_rect.size.x,map_rect.size.y)/extent*0.86 if map_ok else 0.0
	var duration: Variant=_relative(samples[-1].tick)
	var last_map: Variant=null
	var last_graph: Variant=null
	var graph_span: float=maxf(1.0,hi-lo) if graph_ok else 1.0
	var selected_map: Variant=null
	for i in samples.size():
		var sample: Dictionary=samples[i]
		var color: Color=GAP if sample.gap_before else (AMBER if sample.late_by_ticks>0 else CYAN)
		if map_ok:
			# Subtract and normalize in binary64 before constructing drawing Vector2.
			var center_x: float=min_x+(max_x-min_x)*0.5
			var center_z: float=min_z+(max_z-min_z)*0.5
			var point:=map_rect.get_center()+Vector2((sample.anchor_eus_position_m[0]-center_x)*map_scale,(sample.anchor_eus_position_m[2]-center_z)*map_scale)
			if last_map!=null and not sample.gap_before: _painting.draw_line(last_map,point,CYAN,1.5,true)
			if sample.gap_before or sample.late_by_ticks>0: _painting.draw_circle(point,2.2,color)
			if i==_index: selected_map=point
			last_map=point
		var value: Variant=_value(sample,_channel)
		if graph_ok and value!=null:
			var time: Variant=_relative(sample.tick)
			if time==null: last_graph=null;continue
			var point:=Vector2(graph_rect.position.x+float(time)/maxf(0.5,float(duration))*graph_rect.size.x,graph_rect.end.y-(value-lo)/graph_span*graph_rect.size.y)
			if last_graph!=null and not sample.gap_before: _painting.draw_line(last_graph,point,CYAN,1.5,true)
			if sample.gap_before or sample.late_by_ticks>0: _painting.draw_circle(point,2.2,color)
			last_graph=point
		else: last_graph=null
	if selected_map!=null:
		var selected_sample: Dictionary=samples[_index]
		var selected_color: Color=GAP if selected_sample.gap_before else (AMBER if selected_sample.late_by_ticks>0 else CYAN)
		_painting.draw_circle(selected_map,5,Color.WHITE)
		_painting.draw_circle(selected_map,3,selected_color)
	if graph_ok:
		_painting.draw_string(ThemeDB.fallback_font,graph_rect.position+Vector2(6,16),"min %s / max %s"%[_number(lo),_number(hi)],HORIZONTAL_ALIGNMENT_LEFT,-1,12,MUTED)
		var cursor_time: Variant=_relative(samples[_index].tick)
		if cursor_time!=null:
			var cursor_x: float=graph_rect.position.x+float(cursor_time)/maxf(0.5,float(duration))*graph_rect.size.x
			_painting.draw_line(Vector2(cursor_x,graph_rect.position.y),Vector2(cursor_x,graph_rect.end.y),Color.WHITE,1.0)
	else:
		var reason: String="Graph range unavailable / overflow" if is_finite(lo) and is_finite(hi) else "Channel unavailable"
		if _selection.get("available",false):
			var channel_error: String=_selection.sample.readings.readings[_channel].error
			if not channel_error.is_empty(): reason=channel_error.left(48)
		_painting.draw_string(ThemeDB.fallback_font,graph_rect.get_center(),reason,HORIZONTAL_ALIGNMENT_CENTER,-1,13,MUTED)
	_painting.draw_string(ThemeDB.fallback_font,Vector2(graph_rect.position.x,graph_rect.end.y+18),"0 s → %s s sampled · no interpolation"%_number(duration),HORIZONTAL_ALIGNMENT_LEFT,-1,12,MUTED)
	if not map_ok: _painting.draw_string(ThemeDB.fallback_font,map_rect.get_center(),"Geometry unavailable",HORIZONTAL_ALIGNMENT_CENTER,-1,13,MUTED)

func _unhandled_key_input(event: InputEvent) -> void:
	if not _open or not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode==KEY_ESCAPE:
		dismissed.emit()
		get_viewport().set_input_as_handled()
