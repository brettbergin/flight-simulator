extends Control
# Original MIT. Paused draft editor only: no native/mapper commands or autoload.
signal applied(preset: Dictionary)
signal dismissed
signal device_selected(slot: String, device: int)
const Preset=preload("res://input/input_preset.gd")
const Mapper=preload("res://input/input_mapper.gd")
var _draft: Dictionary={}
var _v2: bool=false
var _profile: Dictionary={}
var _held_systems: Dictionary={}
var _hint_label: Label
var _engine_status_label: Label
var _raw: Dictionary={"keys":[],"mouse_buttons":[],"devices":[]}
var _held: Dictionary={}
var _start: Dictionary={}
var _status: Dictionary={}
var _rows: Dictionary={}
var _capture: Dictionary={}
var _calibration: Dictionary={}
var _selected_slot: String="stick"
var _selected_device: int=-1
var _connected: Array=[]
var _built: bool=false
var _valid: bool=false
var _raw_valid: bool=false
var _status_label: Label
var _message: Label
var _name: LineEdit
var _device: OptionButton
var _slot: LineEdit
var _list: VBoxContainer
var _apply_button: Button
var _dialog: FileDialog
var _save_dialog: bool=false
func _button(text: String, callback: Callable) -> Button:
 var button:=Button.new(); button.text=text; button.pressed.connect(callback)
 button.custom_minimum_size.y=30
 return button
func _label(text: String, width: float=0.0) -> Label:
 var label:=Label.new(); label.text=text; label.custom_minimum_size.x=width
 return label
func _ensure_ui() -> void:
 if _built: return
 _built=true; set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter=Control.MOUSE_FILTER_STOP
 var backdrop:=ColorRect.new(); backdrop.color=Color(0.025,0.04,0.065,0.97)
 backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(backdrop)
 var margin:=MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,12)
 add_child(margin)
 var box:=VBoxContainer.new(); box.add_theme_constant_override("separation",7); margin.add_child(box)
 var title:=_label("CONTROLS  /  PAUSED CALIBRATION"); title.add_theme_font_size_override("font_size",20); box.add_child(title)
 var toolbar:=HBoxContainer.new(); box.add_child(toolbar)
 _name=LineEdit.new(); _name.max_length=64; _name.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 _name.text_changed.connect(func(text: String): _draft.name=text; _validate_draft()); toolbar.add_child(_name)
 _apply_button=_button("Apply",_apply); toolbar.add_child(_apply_button)
 toolbar.add_child(_button("Cancel",_cancel)); toolbar.add_child(_button("Defaults",_defaults))
 toolbar.add_child(_button("Load...",func(): _choose_file(false)))
 toolbar.add_child(_button("Save...",func(): _choose_file(true)))
 var devices:=HBoxContainer.new(); box.add_child(devices)
 devices.add_child(_label("Explicit device slot"))
 _slot=LineEdit.new(); _slot.text="stick"; _slot.max_length=32; _slot.custom_minimum_size.x=110; devices.add_child(_slot)
 _device=OptionButton.new(); _device.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 _device.add_item("No controller connected"); _device.set_item_disabled(0,true); _device.disabled=true
 _device.item_selected.connect(_select_device); devices.add_child(_device)
 devices.add_child(_label("Select device, then move each control to observe it."))
 var hint:=_label("Draft edits never change flight.  RAW -> MAPPED TARGET | NATIVE HELD.  Mixture unavailable in this prototype.")
 hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; box.add_child(hint); _hint_label=hint
 var scroll:=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; box.add_child(scroll)
 _list=VBoxContainer.new(); _list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _list.add_theme_constant_override("separation",9); scroll.add_child(_list)
 _message=_label("Guest preset ... explicit Save/Load only ... SQLite profile integration is separate")
 _message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _message.custom_minimum_size.y=38; box.add_child(_message)
 _status_label=_label("Takeover: none / brake hold: on for ground start"); _status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; box.add_child(_status_label)
 _engine_status_label=_label(""); _engine_status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _engine_status_label.hide(); box.add_child(_engine_status_label)
 _dialog=FileDialog.new(); _dialog.access=FileDialog.ACCESS_FILESYSTEM; _dialog.filters=PackedStringArray(["*.json ; Input preset JSON"])
 _dialog.file_selected.connect(_file_selected); add_child(_dialog)
func open(preset: Dictionary, raw: Dictionary, held: Dictionary, start: Dictionary) -> void:
 _ensure_ui()
 var checked: Dictionary=Preset.validate_preset(preset)
 if not checked.ok: show_error(checked.error); return
 var raw_checked: Dictionary=Preset.validate_raw(raw); _raw_valid=raw_checked.ok
 _v2=false; _profile.clear(); _held_systems.clear(); _engine_status_label.hide(); _hint_label.text="Draft edits never change flight. RAW -> MAPPED TARGET | NATIVE HELD. Mixture unavailable in this prototype."
 _draft=checked.value; _raw=raw_checked.value if _raw_valid else {"keys":[],"mouse_buttons":[],"devices":[]}; _held=held.duplicate(true); _start=start.duplicate(true)
 _capture.clear(); _calibration.clear(); _name.text=_draft.name; _rebuild(); show()
 if not _raw_valid: show_error("Input readings unavailable: "+raw_checked.error)
func show_error(text: String) -> void:
 _ensure_ui(); _message.text=text; _message.modulate=Color("ffb680")
func get_draft() -> Dictionary:
 return _draft.duplicate(true)
func _clear_rows() -> void:
 for child in _list.get_children(): _list.remove_child(child); child.queue_free()
 _rows.clear()
func _axis(target: String) -> Dictionary:
 for axis in _draft.get("axes",[]):
  if axis.target==target: return axis
 return {}
func _set_axis(target: String, axis: Dictionary) -> void:
 for i in _draft.axes.size():
  if _draft.axes[i].target==target: _draft.axes[i]=axis; break
 _rebuild()
func _spin(row: HBoxContainer, axis: Dictionary, key: String, low: float, high: float, step: float) -> void:
 row.add_child(_label(key))
 var value:=SpinBox.new(); value.min_value=low; value.max_value=high; value.step=step; value.value=float(axis[key]); value.custom_minimum_size.x=78
 value.value_changed.connect(func(number: float): axis[key]=number; _validate_draft()); row.add_child(value)
func _binding_text(axis: Dictionary) -> String:
 match axis.kind:
  "key_pair": return "- "+_key_names(axis.negative)+"   + "+_key_names(axis.positive)
  "joy_axis": return axis.slot+" / observed axis "+str(axis.index)
 return "Fixed "+str(axis.value)
func _key_names(keys: Array) -> String:
 var names: PackedStringArray=[]
 for key in keys: names.append(OS.get_keycode_string(int(key)))
 return "/".join(names)
func _rebuild() -> void:
 _clear_rows()
 for axis in _draft.axes:
  var section:=VBoxContainer.new(); _list.add_child(section)
  var row:=HBoxContainer.new(); section.add_child(row)
  row.add_child(_label(axis.target.to_upper(),92))
  var kind:=OptionButton.new(); kind.add_item("Keyboard pair"); kind.add_item("Selected axis"); kind.add_item("Fixed")
  kind.selected=["key_pair","joy_axis","fixed"].find(axis.kind); kind.disabled=axis.target=="mixture" and not _v2
  kind.item_selected.connect(func(index: int): _change_kind(axis.target,index)); row.add_child(kind)
  var binding:=_label(_binding_text(axis)); binding.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(binding)
  if axis.target=="mixture" and not _v2: row.add_child(_label("Unavailable in this prototype"))
  elif axis.kind=="key_pair":
   row.add_child(_button("Learn -",func(): _learn({"mode":"key","target":axis.target,"side":"negative"})))
   row.add_child(_button("Learn +",func(): _learn({"mode":"key","target":axis.target,"side":"positive"})))
  elif axis.kind=="joy_axis":
   row.add_child(_button("Learn axis",func(): _learn({"mode":"axis","target":axis.target})))
   row.add_child(_button("Center",func(): _center(axis.target)))
   row.add_child(_button("Sweep range",func(): _sweep(axis.target)))
  else:
   _spin(row,axis,"value",-1.0 if axis.target in ["roll","pitch","yaw","trim"] else 0.0,1.0,0.01)
  if (axis.target!="mixture" or _v2) and axis.kind!="fixed":
   var shape:=HBoxContainer.new(); section.add_child(shape)
   if axis.kind=="joy_axis":
    _spin(shape,axis,"minimum",-1,1,0.01); _spin(shape,axis,"center",-1,1,0.01); _spin(shape,axis,"maximum",-1,1,0.01)
    var invert:=CheckButton.new(); invert.text="Invert"; invert.button_pressed=axis.invert; invert.toggled.connect(func(value: bool): axis.invert=value; _validate_draft()); shape.add_child(invert)
    _spin(shape,axis,"deadzone",0,0.4,0.01)
   else: _spin(shape,axis,"rate",0.01,4,0.01)
   if axis.kind=="joy_axis" or axis.return_to_start: _spin(shape,axis,"gain",0.01,1,0.01)
   else: shape.add_child(_label("Rate control / gain does not apply"))
   if axis.kind=="joy_axis":
    var more:=HBoxContainer.new(); section.add_child(more)
    _spin(more,axis,"saturation",0.01,1,0.01); _spin(more,axis,"slew_per_s",0,4,0.01)
  var bars:=HBoxContainer.new(); section.add_child(bars)
  var raw_bar:=ProgressBar.new(); raw_bar.min_value=-1; raw_bar.max_value=1; raw_bar.show_percentage=false; raw_bar.custom_minimum_size=Vector2(135,16); bars.add_child(raw_bar)
  var mapped_bar:=ProgressBar.new(); mapped_bar.min_value=-1; mapped_bar.max_value=1; mapped_bar.show_percentage=false; mapped_bar.custom_minimum_size=Vector2(135,16); bars.add_child(mapped_bar)
  var values:=_label("Awaiting source readings"); values.size_flags_horizontal=Control.SIZE_EXPAND_FILL; bars.add_child(values)
  _rows[axis.target]={"raw":raw_bar,"mapped":mapped_bar,"values":values}
 _list.add_child(_label("ACTION BINDINGS  /  Learn replaces that action's aliases; Escape stays reserved"))
 for action in _draft.actions:
  var row:=HBoxContainer.new(); _list.add_child(row); row.add_child(_label(action.id,150))
  var sources:=_label(JSON.stringify(action.sources)); sources.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; sources.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(sources)
  row.add_child(_button("Learn",func(): _learn({"mode":"action","id":action.id})))
 if _v2:
  _list.add_child(_label("ENGINE BINDINGS / ignition & feed toggle; starter held / idealized supply"))
  for binding in _draft.systems:
   var row:=HBoxContainer.new(); _list.add_child(row); row.add_child(_label(binding.id,170))
   var sources:=_label("UNBOUND - migration draft" if binding.sources.is_empty() else JSON.stringify(binding.sources))
   sources.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; sources.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(sources)
   row.add_child(_button("Learn",func(): _learn({"mode":"system","id":binding.id})))
 _validate_draft()
func _conflicts() -> Array[String]:
 var owners: Dictionary={}; var conflicts: Array[String]=[]
 for axis in _draft.axes:
  var identities: Array=[]
  if axis.kind=="key_pair":
   for key in axis.negative+axis.positive: identities.append("key "+OS.get_keycode_string(int(key)))
  elif axis.kind=="joy_axis": identities.append(axis.slot+" axis "+str(axis.index))
  for identity in identities: owners[identity]=["axis "+axis.target] if not owners.has(identity) else owners[identity]+["axis "+axis.target]
 for action in _draft.actions+_draft.get("systems",[]):
  for source in action.sources:
   var identities: Array=[]
   if source.kind=="physical_keys":
    for key in source.keys: identities.append("key "+OS.get_keycode_string(int(key)))
   elif source.kind=="joy_button": identities.append(source.slot+" button "+str(source.index))
   else: identities.append("mouse "+str(source.button))
   for identity in identities:
    var owner: String=("engine " if action.id in Preset.SYSTEM_IDS else "action ")+action.id
    if not owners.has(identity): owners[identity]=[owner]
    elif owner not in owners[identity]: owners[identity].append(owner)
 for identity in owners:
  if owners[identity].size()>1: conflicts.append(identity+": "+", ".join(owners[identity]))
 return conflicts
func _validate_draft() -> void:
 if _draft.is_empty(): return
 var checked: Dictionary=_validate_active_draft(); _valid=checked.ok
 var conflicts: Array[String]=[]
 if _valid: conflicts=_conflicts()
 if not conflicts.is_empty(): _valid=false
 if _apply_button!=null: _apply_button.disabled=not _valid
 if not checked.ok: show_error(checked.error)
 elif not conflicts.is_empty(): show_error("Binding conflict - choose separate controls: "+"; ".join(conflicts))
 elif _capture.is_empty() and _calibration.is_empty():
  _message.text="Draft ready. Apply to use these controls; Save keeps a preset file."
  _message.modulate=Color("9ed9ba")
func _change_kind(target: String, choice: int) -> void:
 if target=="mixture" and not _v2: return
 if choice==0:
  for axis in (Mapper.default_preset_v2() if _v2 else Mapper.default_preset()).axes:
   if axis.target==target and axis.kind=="key_pair": _set_axis(target,axis.duplicate(true)); return
  _set_axis(target,{"target":target,"kind":"key_pair","negative":[KEY_J],"positive":[KEY_K],"rate":0.25,"gain":1.0,"return_to_start":false})
 elif choice==1:
  if _selected_device<0 or not _draft.devices.any(func(device: Dictionary): return device.slot==_selected_slot): show_error("Explicitly select a connected device slot before binding an axis"); return
  var axis: Dictionary={"target":target,"kind":"joy_axis","slot":_selected_slot,"index":0,"range":"centered" if target in ["roll","pitch","yaw","trim"] else "unsigned","minimum":-1.0,"center":0.0,"maximum":1.0,"invert":false,"deadzone":0.05,"saturation":1.0,"gain":1.0,"slew_per_s":0.0}
  _set_axis(target,axis); _learn({"mode":"axis","target":target})
 else: _set_axis(target,{"target":target,"kind":"fixed","value":float(_held.get(target,0.0))})
func _select_device(index: int) -> void:
 if index<=0 or index>_connected.size(): return
 index-=1
 var slot: String=_slot.text.strip_edges()
 if not Preset._slot(slot): show_error("Slot must be an ASCII identifier,1..32 characters"); return
 var entry: Dictionary=_connected[index]; _selected_slot=slot; _selected_device=int(entry.id)
 var selector: Dictionary={"slot":slot,"label":str(entry.name).substr(0,64),"match":{"guid":str(entry.guid).substr(0,128),"name":str(entry.name).substr(0,128),"vendor_id":"","product_id":""}}
 var found: bool=false
 for i in _draft.devices.size():
  if _draft.devices[i].slot==slot: _draft.devices[i]=selector; found=true; break
 if not found: _draft.devices.append(selector)
 device_selected.emit(slot,_selected_device); _validate_draft()
 _message.text="Device selected explicitly. Move each axis and press/release each bound button to observe it."
func update_diagnostics(raw: Dictionary, mapped: Dictionary, held: Dictionary, status: Dictionary={}) -> void:
 _ensure_ui()
 var raw_checked: Dictionary=Preset.validate_raw(raw); _raw_valid=raw_checked.ok
 if not _raw_valid:
  _capture.clear(); _calibration.clear(); show_error("Invalid input readings; calibration stopped: "+raw_checked.error); return
 _raw=raw_checked.value; _held=held.duplicate(true); _status=status.duplicate(true)
 var connected: Array=status.get("connected_devices",[])
 if connected!=_connected:
  _connected=connected.duplicate(true); _device.clear()
  _device.add_item("No controller connected" if _connected.is_empty() else "Select a controller...")
  _device.set_item_disabled(0,true); _device.disabled=_connected.is_empty()
  for device in _connected: _device.add_item(str(device.name)+"  [connection "+str(device.id)+"]")
  _device.select(0)
  for i in _connected.size():
   if int(_connected[i].id)==_selected_device: _device.select(i+1)
 if not _capture.is_empty() and not _capture.armed and _released(raw): _capture.armed=true; _message.text="Ready: press a key/button or deliberately move the selected axis."
 if not _calibration.is_empty():
  var reading: Variant=_reading(_calibration.slot,_calibration.index)
  if reading==null or _generation(_calibration.slot)!=_calibration.generation: _calibration.clear(); show_error("Calibration connection changed; draft range unchanged")
  else: _calibration.minimum=minf(_calibration.minimum,float(reading)); _calibration.maximum=maxf(_calibration.maximum,float(reading))
 for axis in _draft.get("axes",[]):
  if not _rows.has(axis.target): continue
  var row: Dictionary=_rows[axis.target]; var value: Variant=null; var target: float=float(mapped.get(axis.target,held.get(axis.target,0.0)))
  if axis.kind=="joy_axis":
   value=_reading(axis.slot,int(axis.index))
   if value!=null and _valid: target=Mapper.mapped_axis(axis,float(value))
  elif axis.kind=="fixed": value=float(axis.value); target=float(axis.value)
  else:
   var positive: bool=axis.positive.any(func(key: int): return key in raw.get("keys",[]))
   var negative: bool=axis.negative.any(func(key: int): return key in raw.get("keys",[]))
   value=float(int(positive)-int(negative))
   if axis.return_to_start: target=clampf(float(_start.get(axis.target,0.0))+float(axis.gain)*float(value),-1,1)
  target=clampf(target,-1.0 if axis.target in ["roll","pitch","yaw","trim"] else 0.0,1.0)
  row.raw.value=float(value) if value!=null else 0.0; row.mapped.value=target
  row.values.text=("RAW unavailable" if value==null else "RAW %.3f"%float(value))+"  -> target %.3f | native held %.3f"%[target,float(held.get(axis.target,0.0))]
 if _v2: _update_engine_diagnostics(status)
 _status_label.text="Takeover: "+(", ".join(status.get("takeover",[])) if not status.get("takeover",[]).is_empty() else "none")+" / brake hold: "+("ON" if status.get("brake_hold",false) else "off")
 if _valid and not str(status.get("error","")).is_empty() and _capture.is_empty() and _calibration.is_empty(): show_error(str(status.error))
func _generation(slot: String) -> Variant:
 for device in _raw.get("devices",[]):
  if device.slot==slot: return device.generation
 return null
func _reading(slot: String, index: int) -> Variant:
 for device in _raw.get("devices",[]):
  if device.slot==slot:
   for axis in device.axes:
    if int(axis.index)==index: return axis.value
 return null
func _released(raw: Dictionary) -> bool:
 if not raw.get("keys",[]).is_empty(): return false
 for button in raw.get("mouse_buttons",[]):
  if button not in [4,5,6,7]: return false
 for device in raw.get("devices",[]):
  for button in device.buttons:
   if button.pressed: return false
 return true
func _learn(capture: Dictionary) -> void:
 if not _raw_valid: show_error("Observe valid input readings before Learn"); return
 _calibration.clear(); _capture=capture.duplicate(true); _capture.armed=false
 _capture.baselines={}
 _capture.generation=_generation(_selected_slot)
 for device in _raw.get("devices",[]):
  if device.slot==_selected_slot:
   for axis in device.axes: _capture.baselines[int(axis.index)]=float(axis.value)
 _message.text="Release all keys/buttons, then provide a deliberate input. Axis motion under0.25 is ignored."
func _input(event: InputEvent) -> void:
 if not visible: return
 if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_ESCAPE:
  if not _capture.is_empty(): _capture.clear(); _validate_draft()
  else: _cancel()
  get_viewport().set_input_as_handled(); return
 if not _raw_valid or _capture.is_empty() or not _capture.armed: return
 var source: Dictionary={}
 if event is InputEventKey and event.pressed and not event.echo and Preset._key(event.physical_keycode): source={"kind":"physical_keys","keys":[event.physical_keycode]}
 elif event is InputEventJoypadButton and event.pressed and event.device==_selected_device and event.button_index>=0 and event.button_index<JOY_BUTTON_MAX and _capture.generation!=null and _generation(_selected_slot)==_capture.generation: source={"kind":"joy_button","slot":_selected_slot,"index":event.button_index}
 elif event is InputEventMouseButton and event.pressed and event.button_index>=1 and event.button_index<=9: source={"kind":"mouse_button","button":event.button_index}
 elif event is InputEventJoypadMotion and _capture.mode=="axis" and event.device==_selected_device and event.axis>=0 and event.axis<JOY_AXIS_MAX:
  if _capture.generation==null or _generation(_selected_slot)!=_capture.generation:
   _capture.clear(); show_error("Learn source connection changed; explicitly select it again"); return
  if not _capture.baselines.has(event.axis):
   _capture.baselines[event.axis]=event.axis_value
   _message.text="First actual axis observation recorded. Move it deliberately again to bind."
   return
  var baseline: float=float(_capture.baselines[event.axis])
  if absf(event.axis_value-baseline)<0.25: return
  var axis: Dictionary=_axis(_capture.target); axis.slot=_selected_slot; axis.index=event.axis
  _capture.clear(); _rebuild(); return
 if source.is_empty(): return
 if _capture.mode=="key" and source.kind=="physical_keys": _axis(_capture.target)[_capture.side]=source.keys
 elif _capture.mode=="system":
  if source.kind=="mouse_button" and int(source.button) in [4,5,6,7]: show_error("Starter/engine bindings require a held source, not wheel pulses"); return
  for binding in _draft.systems:
   if binding.id==_capture.id: binding.sources=[source]; break
 elif _capture.mode=="action":
  for action in _draft.actions:
   if action.id==_capture.id: action.sources=[source]; break
 else: return
 _capture.clear(); _rebuild()
func _center(target: String) -> void:
 if not _raw_valid: show_error("Observe valid input readings before calibration"); return
 var axis: Dictionary=_axis(target); var value: Variant=_reading(axis.slot,int(axis.index))
 if value==null: show_error("Axis has not been observed on this selected connection"); return
 axis.center=float(value); _rebuild()
func _sweep(target: String) -> void:
 if not _raw_valid: show_error("Observe valid input readings before calibration"); return
 var axis: Dictionary=_axis(target)
 if not _calibration.is_empty():
  if _calibration.target!=target: show_error("Finish the current range sweep first"); return
  axis.minimum=_calibration.minimum; axis.maximum=_calibration.maximum; _calibration.clear(); _rebuild(); return
 var value: Variant=_reading(axis.slot,int(axis.index))
 if value==null: show_error("Observe the selected axis before calibration"); return
 _capture.clear(); _calibration={"target":target,"slot":axis.slot,"index":axis.index,"generation":_generation(axis.slot),"minimum":float(value),"maximum":float(value)}
 _message.text="Sweep from actual rest to both endpoints, then click Sweep range again. Small/invalid spans reject Apply."
func _apply() -> void:
 _capture.clear(); _calibration.clear()
 _validate_draft()
 if not _valid: return
 var checked: Dictionary=_validate_active_draft()
 applied.emit(checked.value.duplicate(true)) # Coordinator alone ACKs and hides.
func _cancel() -> void:
 _capture.clear(); _calibration.clear(); dismissed.emit()
func _defaults() -> void:
 _draft=(Mapper.default_preset_v2() if _v2 else Mapper.default_preset()).duplicate(true); _name.text=_draft.name; _capture.clear(); _calibration.clear(); _rebuild()
func _choose_file(save_file: bool) -> void:
 _capture.clear(); _calibration.clear(); _save_dialog=save_file
 _dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE if save_file else FileDialog.FILE_MODE_OPEN_FILE
 _dialog.title="Save explicit guest preset" if save_file else "Load preset into draft (not applied)"
 _dialog.current_file="controls.json" if save_file else ""
 _dialog.popup_centered_ratio(0.75)
func _file_selected(path: String) -> void:
 if _save_dialog:
  var result: Dictionary=Preset.save_v2(path,_draft) if _v2 else Preset.save(path,_draft)
  if result.ok: _message.text="Explicit preset saved after verified replacement. No automatic profile storage."
  else: show_error(result.error)
 else:
  var file=FileAccess.open(path,FileAccess.READ)
  if file==null: show_error("Cannot read selected preset; draft preserved"); return
  if file.get_length()>Preset.MAX_BYTES: file.close(); show_error("Preset exceeds64KiB; draft preserved"); return
  var bytes: PackedByteArray=file.get_buffer(file.get_length()); file.close()
  var result: Dictionary=Preset.decode_v2(bytes) if _v2 else Preset.decode(bytes)
  var migrated: bool=false
  if _v2 and not result.ok:
   var legacy: Dictionary=Preset.decode(bytes)
   if legacy.ok: result=Preset.migrate_v1_draft(legacy.value); migrated=result.ok
  if not result.ok: show_error(result.error+"; draft preserved"); return
  _draft=result.value; _name.text=_draft.name; _capture.clear(); _calibration.clear(); _rebuild()
  _message.text="V1 migration DRAFT: mixture fixed full rich; engine controls UNBOUND. Choose bindings, then explicitly Apply." if migrated else "Preset loaded into guest draft only. Select ambiguous devices explicitly, then Apply while paused."

func _validate_active_draft() -> Dictionary:
 return Preset.validate_preset_v2(_draft) if _v2 else Preset.validate_preset(_draft)
func open_v2(preset: Dictionary, raw: Dictionary, heldaxes: Dictionary, startaxes: Dictionary, profile: Dictionary, heldsystems: Dictionary) -> void:
 _ensure_ui()
 var checked: Dictionary=Preset.validate_preset_v2(preset)
 if not checked.ok: show_error(checked.error); return
 if not Preset.valid_profile(profile) or not Preset.valid_systems(heldsystems) or not Preset.valid_axes_v2(heldaxes) or not Preset.valid_axes_v2(startaxes): show_error("Verified piston profile/held controls unavailable; draft preserved"); return
 var raw_checked: Dictionary=Preset.validate_raw(raw)
 _v2=true; _profile=profile.duplicate(true); _held_systems=heldsystems.duplicate(true)
 _draft=checked.value; _raw_valid=raw_checked.ok; _raw=raw_checked.value if _raw_valid else {"keys":[],"mouse_buttons":[],"devices":[]}
 _held=heldaxes.duplicate(true); _start=startaxes.duplicate(true); _capture.clear(); _calibration.clear()
 _hint_label.text="PISTON PROTOTYPE / idealized external starter supply. Draft edits never change flight. Mixture and engine bindings require explicit Apply."
 _engine_status_label.show(); _update_engine_diagnostics({"profile":profile,"held_systems":heldsystems,"pending_systems":{}})
 _name.text=_draft.name; _rebuild(); show()
 if not _raw_valid: show_error("Input readings unavailable: "+raw_checked.error)
func _update_engine_diagnostics(info: Dictionary) -> void:
 var held: Variant=info.get("held_systems")
 var pending: Variant=info.get("pending_systems")
 if not Preset.valid_profile(info.get("profile")) or not Preset.valid_systems(held):
  _engine_status_label.text="Engine native-held unavailable / pending is local intent only"; return
 _held_systems=held.duplicate(true)
 var lines: PackedStringArray=[]
 for id in Preset.SYSTEM_IDS:
  var name: String=id.trim_prefix("engine.").trim_prefix("fuel.")
  lines.append(name+" "+("ON" if held[id] else "off"))
 var intent: String="unavailable"
 if Preset.valid_systems(pending):
  var values: PackedStringArray=[]
  for id in Preset.SYSTEM_IDS: values.append(id.trim_prefix("engine.").trim_prefix("fuel.")+" "+("ON" if pending[id] else "off"))
  intent=", ".join(values)
 _engine_status_label.text="NATIVE HELD: "+", ".join(lines)+"\nPENDING (not admission): "+intent
