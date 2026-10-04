extends RefCounted
# Original MIT. ADR008 copied preset/raw validation and explicit interchange only.
const TARGETS=["roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim"]
const ACTIONS=["pause_menu","restart","start_ground","start_airborne","idle","left_brake","right_brake","both_brakes","brake_hold","view_cycle","view_cockpit","view_chase","view_orbit","view_panel","map_toggle","runway_toggle","map_zoom_in","map_zoom_out","look_hold","view_zoom_in","view_zoom_out","recenter","help","overlay","controller_select","audio","fullscreen","speed_down","speed_up","controls_panel"]
const MAX_BYTES=65536
static func _bad(message: String) -> Dictionary:
 return {"ok":false,"error":message,"value":null}
static func _good(value: Variant) -> Dictionary:
 return {"ok":true,"error":"","value":value}
static func _closed(value: Variant, names: Array) -> bool:
 if not value is Dictionary or value.size()!=names.size(): return false
 for key in value:
  if typeof(key)!=TYPE_STRING or not names.has(key): return false
 return true
static func _number(value: Variant, low: float, high: float) -> bool:
 return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value)>=low and float(value)<=high
static func _integer(value: Variant, low: int, high: int) -> bool:
 return _number(value,float(low),float(high)) and floor(float(value))==float(value)
static func _text(value: Variant, low: int, high: int) -> bool:
 return typeof(value)==TYPE_STRING and value.length()>=low and value.length()<=high
static func _slot(value: Variant) -> bool:
 if not _text(value,1,32): return false
 for i in value.length():
  var code: int=value.unicode_at(i)
  if not (code>=65 and code<=90 or code>=97 and code<=122 or i>0 and (code>=48 and code<=57 or code in [45,46,95])): return false
 return true
static func _key(value: Variant) -> bool:
 if not _integer(value,1,2147483647): return false
 var code: int=int(value)
 if code==KEY_UNKNOWN or code==KEY_NONE or (code<32): return false
 return OS.find_keycode_from_string(OS.get_keycode_string(code))==code
static func _keys(value: Variant, low: int=1, high: int=4) -> bool:
 if not value is Array or value.size()<low or value.size()>high: return false
 var seen: Array=[]
 for code in value:
  if not _key(code) or seen.has(int(code)): return false
  seen.append(int(code))
 return true
static func _axis(value: Variant, slots: Array) -> bool:
 if not value is Dictionary or not TARGETS.has(value.get("target")) or typeof(value.get("kind"))!=TYPE_STRING: return false
 var target: String=value.target
 if target=="mixture": return _closed(value,["target","kind","value"]) and value.kind=="fixed" and _number(value.value,1.0,1.0)
 var minimum: float=-1.0 if target in ["roll","pitch","yaw","trim"] else 0.0
 match value.kind:
  "fixed": return _closed(value,["target","kind","value"]) and _number(value.value,minimum,1.0)
  "key_pair":
   if not _closed(value,["target","kind","negative","positive","rate","gain","return_to_start"]) or not _keys(value.negative) or not _keys(value.positive): return false
   for key in value.negative:
    if value.positive.has(key): return false
   return _number(value.rate,0.0,4.0) and value.rate>0 and _number(value.gain,0.0,1.0) and value.gain>0 and typeof(value.return_to_start)==TYPE_BOOL and (not value.return_to_start or target in ["roll","pitch","yaw"])
  "joy_axis":
   if not _closed(value,["target","kind","slot","index","range","minimum","center","maximum","invert","deadzone","saturation","gain","slew_per_s"]): return false
   if not slots.has(value.slot) or not _integer(value.index,0,JOY_AXIS_MAX-1) or value.range not in ["centered","unsigned"] or typeof(value.invert)!=TYPE_BOOL: return false
   for field in ["minimum","center","maximum"]:
    if not _number(value[field],-1.0,1.0): return false
   if value.range=="centered" and (float(value.center)-float(value.minimum)<0.05 or float(value.maximum)-float(value.center)<0.05): return false
   if value.range=="unsigned" and float(value.maximum)-float(value.minimum)<0.05: return false
   return _number(value.deadzone,0.0,0.4) and _number(value.saturation,0.0,1.0) and value.saturation>value.deadzone and _number(value.gain,0.0,1.0) and value.gain>0 and _number(value.slew_per_s,0.0,4.0)
 return false
static func _source(value: Variant, slots: Array) -> bool:
 if not value is Dictionary: return false
 match value.get("kind"):
  "physical_keys": return _closed(value,["kind","keys"]) and _keys(value.keys)
  "joy_button": return _closed(value,["kind","slot","index"]) and slots.has(value.slot) and _integer(value.index,0,JOY_BUTTON_MAX-1)
  "mouse_button": return _closed(value,["kind","button"]) and _integer(value.button,1,9)
 return false
static func _source_id(value: Dictionary) -> String:
 match value.kind:
  "physical_keys":
   var codes: Array=value.keys.duplicate(); codes.sort()
   return "keys:"+JSON.stringify(codes)
  "joy_button": return "button:"+value.slot+":"+str(int(value.index))
 return "mouse:"+str(int(value.button))
static func validate_preset(value: Variant) -> Dictionary:
 if not _closed(value,["type","version","name","devices","axes","actions"]) or value.type!="InputPreset" or not _integer(value.version,1,1) or not _text(value.name,1,64): return _bad("Unknown or malformed InputPreset/v1 header")
 if not value.devices is Array or value.devices.size()>8 or not value.axes is Array or value.axes.size()!=8 or not value.actions is Array or value.actions.size()>64: return _bad("Preset device/axis/action bounds rejected")
 var slots: Array=[]
 for device in value.devices:
  if not _closed(device,["slot","label","match"]) or not _slot(device.slot) or slots.has(device.slot) or not _text(device.label,0,64) or not _closed(device.match,["guid","name","vendor_id","product_id"]): return _bad("Invalid, duplicate or unbounded device selector")
  for field in ["guid","name","vendor_id","product_id"]:
   if not _text(device.match[field],0,128 if field in ["guid","name"] else 16): return _bad("Invalid device metadata")
  slots.append(device.slot)
 var targets: Array=[]
 for axis in value.axes:
  if not _axis(axis,slots) or targets.has(axis.target): return _bad("Invalid or duplicate axis; mixture must remain fixed1")
  targets.append(axis.target)
 var actions: Array=[]
 for action in value.actions:
  if not _closed(action,["id","sources"]) or not ACTIONS.has(action.id) or actions.has(action.id) or not action.sources is Array or action.sources.size()<1 or action.sources.size()>4: return _bad("Invalid or duplicate action")
  var aliases: Array=[]
  for source in action.sources:
   if not _source(source,slots): return _bad("Invalid action source")
   var identity: String=_source_id(source)
   if aliases.has(identity): return _bad("Duplicate action alias")
   aliases.append(identity)
  actions.append(action.id)
 var copy: Dictionary=value.duplicate(true)
 copy.version=1
 for axis in copy.axes:
  if axis.kind=="joy_axis": axis.index=int(axis.index)
  elif axis.kind=="key_pair":
   for side in ["negative","positive"]:
    for i in axis[side].size(): axis[side][i]=int(axis[side][i])
 for action in copy.actions:
  for source in action.sources:
   if source.kind=="physical_keys":
    for i in source.keys.size(): source.keys[i]=int(source.keys[i])
   elif source.kind=="joy_button": source.index=int(source.index)
   else: source.button=int(source.button)
 if JSON.stringify(copy).to_utf8_buffer().size()>MAX_BYTES: return _bad("Preset exceeds64KiB")
 return _good(copy)
static func validate_raw(value: Variant) -> Dictionary:
 if not _closed(value,["keys","mouse_buttons","devices"]) or not _keys(value.keys,0,64) or not value.mouse_buttons is Array or value.mouse_buttons.size()>9 or not value.devices is Array or value.devices.size()>8: return _bad("Malformed raw input snapshot")
 for code in value.keys:
  if typeof(code)!=TYPE_INT: return _bad("Raw physical keys must be int")
 var buttons: Array=[]
 for code in value.mouse_buttons:
  if typeof(code)!=TYPE_INT or not _integer(code,1,9) or buttons.has(int(code)): return _bad("Invalid or duplicate mouse button")
  buttons.append(int(code))
 var slots: Array=[]
 for device in value.devices:
  if not _closed(device,["slot","generation","axes","buttons"]) or not _slot(device.slot) or slots.has(device.slot) or typeof(device.generation)!=TYPE_INT or device.generation<0 or not device.axes is Array or device.axes.size()>JOY_AXIS_MAX or not device.buttons is Array or device.buttons.size()>JOY_BUTTON_MAX: return _bad("Invalid raw device/generation/observed bounds")
  slots.append(device.slot)
  var indices: Array=[]
  for axis in device.axes:
   if not _closed(axis,["index","value"]) or typeof(axis.index)!=TYPE_INT or typeof(axis.value)!=TYPE_FLOAT or not _integer(axis.index,0,JOY_AXIS_MAX-1) or indices.has(int(axis.index)) or not _number(axis.value,-1.0,1.0): return _bad("Invalid sparse observed axis")
   indices.append(int(axis.index))
  indices.clear()
  for button in device.buttons:
   if not _closed(button,["index","pressed"]) or typeof(button.index)!=TYPE_INT or not _integer(button.index,0,JOY_BUTTON_MAX-1) or indices.has(int(button.index)) or typeof(button.pressed)!=TYPE_BOOL: return _bad("Invalid sparse observed button")
   indices.append(int(button.index))
 var copy: Dictionary=value.duplicate(true)
 for i in copy.keys.size(): copy.keys[i]=int(copy.keys[i])
 copy.mouse_buttons=buttons
 for device in copy.devices:
  for axis in device.axes: axis.index=int(axis.index); axis.value=float(axis.value)
  for button in device.buttons: button.index=int(button.index)
 return _good(copy)
static func _utf8(bytes: PackedByteArray) -> bool:
 var i: int=0
 while i<bytes.size():
  var first: int=bytes[i]; var count: int=0
  if first<=127: i+=1; continue
  elif first>=194 and first<=223: count=1
  elif first>=224 and first<=239: count=2
  elif first>=240 and first<=244: count=3
  else: return false
  if i+count>=bytes.size(): return false
  for j in range(1,count+1):
   if bytes[i+j]<128 or bytes[i+j]>191: return false
  if first==224 and bytes[i+1]<160 or first==237 and bytes[i+1]>159 or first==240 and bytes[i+1]<144 or first==244 and bytes[i+1]>143: return false
  i+=count+1
 return true
static func _json_structure(text: String) -> bool:
 var stack: Array=[]; var i: int=0
 while i<text.length():
  var token: String=text[i]
  if token=='"':
   var begin: int=i; i+=1
   while i<text.length() and text[i]!='"':
    if text[i]=='\\': i+=1
    i+=1
   if i>=text.length(): return false
   if not stack.is_empty() and stack.back().kind=='{' and stack.back().key:
    var parser:=JSON.new()
    if parser.parse(text.substr(begin,i-begin+1))!=OK or not parser.data is String or stack.back().names.has(parser.data): return false
    stack.back().names.append(parser.data); stack.back().key=false
  elif token in ['{','[']:
   stack.append({"kind":token,"key":token=='{',"names":[]})
   if stack.size()>8: return false
  elif token in ['}',']']:
   if stack.is_empty() or stack.back().kind!=('{' if token=='}' else '['): return false
   stack.pop_back()
  elif token==',' and not stack.is_empty() and stack.back().kind=='{': stack.back().key=true
  i+=1
 return stack.is_empty()
static func decode(bytes: PackedByteArray) -> Dictionary:
 if bytes.is_empty() or bytes.size()>MAX_BYTES or not _utf8(bytes): return _bad("Preset must be bounded valid UTF-8 JSON")
 var text: String=bytes.get_string_from_utf8()
 if not _json_structure(text): return _bad("Duplicate JSON key or excessive/invalid nesting")
 var parser:=JSON.new()
 if parser.parse(text)!=OK: return _bad("Invalid JSON: "+parser.get_error_message())
 return validate_preset(parser.data)
static func encode(preset: Dictionary) -> Dictionary:
 var checked: Dictionary=validate_preset(preset)
 if not checked.ok: return checked
 var bytes: PackedByteArray=JSON.stringify(checked.value,"  ").to_utf8_buffer()
 if bytes.size()>MAX_BYTES: return _bad("Encoded preset exceeds64KiB")
 return _good(bytes)
static func save(path: String, preset: Dictionary) -> Dictionary:
 if path.is_empty() or not path.is_absolute_path() or path.begins_with("res://") or path.begins_with("user://"): return {"ok":false,"error":"Choose an explicit absolute interchange path"}
 var encoded: Dictionary=encode(preset)
 if not encoded.ok: return {"ok":false,"error":encoded.error}
 var temporary: String=path+".tmp-"+str(OS.get_process_id())+"-"+str(Time.get_ticks_usec())
 var file=FileAccess.open(temporary,FileAccess.WRITE)
 if file==null: return {"ok":false,"error":"Cannot create temporary preset; target preserved"}
 file.store_buffer(encoded.value); file.flush()
 var write_error: int=file.get_error(); file.close()
 if write_error!=OK: return {"ok":false,"error":"Preset write failed; target preserved, temporary retained"}
 var bytes: PackedByteArray=FileAccess.get_file_as_bytes(temporary)
 if bytes!=encoded.value or not decode(bytes).ok: return {"ok":false,"error":"Preset reread failed; target preserved, temporary retained"}
 if OS.get_name()!="Windows":
  return {"ok":false,"error":"Atomic preset save is currently qualified only on Windows local NTFS; temporary retained"}
 var executable: String=OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
 if not FileAccess.file_exists(executable): return {"ok":false,"error":"Built-in atomic replacement helper unavailable; target preserved, temporary retained"}
 var source64: String=Marshalls.raw_to_base64(temporary.to_utf8_buffer())
 var target64: String=Marshalls.raw_to_base64(path.to_utf8_buffer())
 # Only base64 data enters the fixed helper script. No interpreted user path and
 # no delete/rename fallback: pinned Godot Windows rename deletes first.
 var command: String="$ErrorActionPreference='Stop';try{$source=[IO.Path]::GetFullPath([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"+source64+"')));$target=[IO.Path]::GetFullPath([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"+target64+"')));$drive=[IO.Path]::GetPathRoot($target);if($drive.StartsWith('\\') -or ([IO.DriveInfo]::new($drive)).DriveFormat -ne 'NTFS'){throw 'Only local NTFS is qualified'};if(-not [String]::Equals([IO.Path]::GetDirectoryName($source),[IO.Path]::GetDirectoryName($target),[StringComparison]::OrdinalIgnoreCase)){throw 'Temporary must share target directory'};if([IO.Directory]::Exists($target)){throw 'Target is a directory'};$parent=[IO.DirectoryInfo]::new([IO.Path]::GetDirectoryName($target));while($null -ne $parent){if(($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Reparse parents are unqualified'};$parent=$parent.Parent};if([IO.File]::Exists($target) -and (([IO.File]::GetAttributes($target) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){throw 'Reparse targets are unqualified'};if([IO.File]::Exists($target)){[IO.File]::Replace($source,$target,[NullString]::Value)}else{[IO.File]::Move($source,$target)};Write-Output 'ATOMIC_PRESET_SAVED';exit 0}catch{exit 2}"
 var output: Array=[]
 var result: int=OS.execute(executable,PackedStringArray(["-NoProfile","-NonInteractive","-Command",command]),output,true,false)
 if result!=0 or output.is_empty() or not str(output[0]).contains("ATOMIC_PRESET_SAVED"):
  return {"ok":false,"error":"Atomic local-NTFS replace failed or unsupported; target preserved, temporary retained"}
 return {"ok":true,"error":""}
# ADR010 is an explicit capability-qualified extension. Legacy entry points stay v1.
const PISTON_PROFILE={"id":"original-piston-prop-v1","version":"0.1.0-prototype","backend_model":"original-piston-prop"}
const SYSTEM_IDS=["engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed"]
static func valid_profile(value: Variant) -> bool:
 if not _closed(value,["id","version","backend_model"]): return false
 for key in PISTON_PROFILE:
  if typeof(value[key])!=TYPE_STRING or value[key]!=PISTON_PROFILE[key]: return false
 return true
static func valid_systems(value: Variant) -> bool:
 if not _closed(value,SYSTEM_IDS): return false
 for id in SYSTEM_IDS:
  if typeof(value[id])!=TYPE_BOOL: return false
 return true
static func valid_axes_v2(value: Variant) -> bool:
 if not _closed(value,["kind"]+TARGETS) or typeof(value.kind)!=TYPE_STRING or value.kind!="axes": return false
 for target in TARGETS:
  if not _number(value[target],-1.0 if target in ["roll","pitch","yaw","trim"] else 0.0,1.0): return false
 return true
static func _mixture_v2(axis: Variant, slots: Array) -> bool:
 if not axis is Dictionary or typeof(axis.get("target"))!=TYPE_STRING or axis.target!="mixture" or typeof(axis.get("kind"))!=TYPE_STRING: return false
 if axis.kind=="fixed": return _closed(axis,["target","kind","value"]) and _number(axis.value,0.0,1.0)
 var surrogate: Dictionary=axis.duplicate(true); surrogate.target="throttle"
 if not _axis(surrogate,slots): return false
 if axis.kind=="key_pair": return axis.return_to_start==false
 return axis.kind=="joy_axis" and typeof(axis.range)==TYPE_STRING and axis.range=="unsigned"
static func _control_ids(source: Dictionary) -> Array[String]:
 var result: Array[String]=[]
 match source.kind:
  "physical_keys":
   for code in source.keys: result.append("key:"+str(int(code)))
  "joy_button": result.append("button:"+source.slot+":"+str(int(source.index)))
  "mouse_button": result.append("mouse:"+str(int(source.button)))
 return result
static func _v2_conflict(preset: Dictionary) -> String:
 var owners: Dictionary={}
 for axis in preset.axes:
  var controls: Array[String]=[]
  if axis.kind=="key_pair":
   for code in axis.negative+axis.positive: controls.append("key:"+str(int(code)))
  elif axis.kind=="joy_axis": controls.append("axis:"+axis.slot+":"+str(int(axis.index)))
  for control in controls:
   if control=="key:"+str(KEY_ESCAPE): return "Escape remains reserved"
   if owners.has(control) and owners[control]!="axis:"+axis.target: return "Conflicting control: "+control
   owners[control]="axis:"+axis.target
 for group in ["actions","systems"]:
  for binding in preset[group]:
   for source in binding.sources:
    for control in _control_ids(source):
     if control=="key:"+str(KEY_ESCAPE): return "Escape remains reserved"
     var owner: String=group+":"+binding.id
     if owners.has(control) and owners[control]!=owner: return "Conflicting control: "+control
     owners[control]=owner
 return ""
static func validate_preset_v2(value: Variant) -> Dictionary:
 if not _closed(value,["type","version","name","devices","axes","actions","profile","capability_revision","systems"]): return _bad("Invalid v2 preset keys")
 if typeof(value.type)!=TYPE_STRING or value.type!="InputPreset" or not _integer(value.version,2,2) or not valid_profile(value.profile) or typeof(value.capability_revision)!=TYPE_STRING or value.capability_revision!="piston-controls-v1": return _bad("Unsupported v2 profile/capability")
 if not value.axes is Array or not value.devices is Array or not value.actions is Array: return _bad("Invalid v2 collections")
 var projected: Dictionary={}
 for key in ["type","name","devices","axes","actions"]: projected[key]=value[key].duplicate(true) if value[key] is Array else value[key]
 projected["version"]=1
 var slots: Array=[]
 for device in value.devices:
  if not device is Dictionary or typeof(device.get("slot"))!=TYPE_STRING: return _bad("Invalid v2 slot")
  slots.append(device.slot)
 var mixture: Dictionary={}
 for i in projected.axes.size():
  var axis: Variant=projected.axes[i]
  if not axis is Dictionary or typeof(axis.get("target"))!=TYPE_STRING or typeof(axis.get("kind"))!=TYPE_STRING: return _bad("Invalid v2 axis strings")
  if axis.kind=="joy_axis" and (typeof(axis.get("slot"))!=TYPE_STRING or typeof(axis.get("range"))!=TYPE_STRING): return _bad("Invalid v2 axis source strings")
  if axis.target=="mixture":
   if not mixture.is_empty() or not _mixture_v2(axis,slots): return _bad("Invalid mixture binding")
   mixture=axis.duplicate(true); projected.axes[i]={"target":"mixture","kind":"fixed","value":1.0}
 for action in value.actions:
  if not action is Dictionary or typeof(action.get("id"))!=TYPE_STRING or not action.get("sources") is Array: return _bad("Invalid v2 action strings")
  for source in action.sources:
   if not source is Dictionary or typeof(source.get("kind"))!=TYPE_STRING or source.kind=="joy_button" and typeof(source.get("slot"))!=TYPE_STRING: return _bad("Invalid v2 source strings")
 var checked: Dictionary=validate_preset(projected)
 if not checked.ok: return checked
 if mixture.is_empty() or not value.systems is Array or value.systems.size()!=4: return _bad("Four engine bindings are required")
 var systems: Array=[]; var seen: Array=[]
 for binding in value.systems:
  if not _closed(binding,["id","kind","sources"]) or typeof(binding.id)!=TYPE_STRING or not SYSTEM_IDS.has(binding.id) or seen.has(binding.id) or typeof(binding.kind)!=TYPE_STRING or binding.kind!=("momentary" if binding.id=="engine.starter" else "toggle") or not binding.sources is Array or binding.sources.size()<1 or binding.sources.size()>4: return _bad("Invalid, duplicate or unbound engine control")
  seen.append(binding.id); var aliases: Array=[]; var copy: Dictionary=binding.duplicate(true)
  for source in copy.sources:
   if not source is Dictionary or typeof(source.get("kind"))!=TYPE_STRING or not _source(source,slots) or source.kind=="joy_button" and typeof(source.get("slot"))!=TYPE_STRING: return _bad("Invalid engine source")
   if source.kind=="mouse_button" and int(source.button) in [4,5,6,7]: return _bad("Engine controls require persistent sources")
   var identity: String=_source_id(source)
   if aliases.has(identity): return _bad("Duplicate engine alias")
   aliases.append(identity)
   if source.kind=="physical_keys":
    for i in source.keys.size(): source.keys[i]=int(source.keys[i])
   elif source.kind=="joy_button": source.index=int(source.index)
   else: source.button=int(source.button)
  systems.append(copy)
 var result: Dictionary=checked.value
 result.version=2; result["profile"]=PISTON_PROFILE.duplicate(true); result["capability_revision"]="piston-controls-v1"; result["systems"]=systems
 if mixture.kind=="key_pair":
  for side in ["negative","positive"]:
   for i in mixture[side].size(): mixture[side][i]=int(mixture[side][i])
 elif mixture.kind=="joy_axis": mixture.index=int(mixture.index)
 for i in result.axes.size():
  if result.axes[i].target=="mixture": result.axes[i]=mixture
 var conflict: String=_v2_conflict(result)
 if not conflict.is_empty(): return _bad(conflict)
 if JSON.stringify(result).to_utf8_buffer().size()>MAX_BYTES: return _bad("Preset exceeds64KiB")
 return _good(result)
static func migrate_v1_draft(value: Variant) -> Dictionary:
 var checked: Dictionary=validate_preset(value)
 if not checked.ok: return checked
 var draft: Dictionary=checked.value
 draft.version=2; draft["profile"]=PISTON_PROFILE.duplicate(true); draft["capability_revision"]="piston-controls-v1"; draft["systems"]=[]
 for id in SYSTEM_IDS: draft.systems.append({"id":id,"kind":"momentary" if id=="engine.starter" else "toggle","sources":[]})
 return _good(draft) # Deliberately invalid as an active v2 preset until user binding/Apply.
static func decode_v2(bytes: PackedByteArray) -> Dictionary:
 if bytes.is_empty() or bytes.size()>MAX_BYTES or not _utf8(bytes): return _bad("Preset must be bounded valid UTF-8 JSON")
 var text: String=bytes.get_string_from_utf8()
 if not _json_structure(text): return _bad("Duplicate JSON key or excessive/invalid nesting")
 var parser:=JSON.new()
 if parser.parse(text)!=OK: return _bad("Invalid JSON: "+parser.get_error_message())
 return validate_preset_v2(parser.data)
static func encode_v2(preset: Dictionary) -> Dictionary:
 var checked: Dictionary=validate_preset_v2(preset)
 if not checked.ok: return checked
 var bytes: PackedByteArray=JSON.stringify(checked.value,"  ").to_utf8_buffer()
 if bytes.size()>MAX_BYTES: return _bad("Encoded preset exceeds64KiB")
 return _good(bytes)

static func save_v2(path: String, preset: Dictionary) -> Dictionary:
 if path.is_empty() or not path.is_absolute_path() or path.begins_with("res://") or path.begins_with("user://"): return {"ok":false,"error":"Choose an explicit absolute interchange path"}
 var encoded: Dictionary=encode_v2(preset)
 if not encoded.ok: return {"ok":false,"error":encoded.error}
 var temporary: String=path+".tmp-"+str(OS.get_process_id())+"-"+str(Time.get_ticks_usec())
 var file=FileAccess.open(temporary,FileAccess.WRITE)
 if file==null: return {"ok":false,"error":"Cannot create temporary preset; target preserved"}
 file.store_buffer(encoded.value); file.flush()
 var write_error: int=file.get_error(); file.close()
 if write_error!=OK: return {"ok":false,"error":"Preset write failed; target preserved, temporary retained"}
 var bytes: PackedByteArray=FileAccess.get_file_as_bytes(temporary)
 if bytes!=encoded.value or not decode_v2(bytes).ok: return {"ok":false,"error":"Preset reread failed; target preserved, temporary retained"}
 if OS.get_name()!="Windows":
  return {"ok":false,"error":"Atomic preset save is currently qualified only on Windows local NTFS; temporary retained"}
 var executable: String=OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
 if not FileAccess.file_exists(executable): return {"ok":false,"error":"Built-in atomic replacement helper unavailable; target preserved, temporary retained"}
 var source64: String=Marshalls.raw_to_base64(temporary.to_utf8_buffer())
 var target64: String=Marshalls.raw_to_base64(path.to_utf8_buffer())
 # Only base64 data enters the fixed helper script. No interpreted user path and
 # no delete/rename fallback: pinned Godot Windows rename deletes first.
 var command: String="$ErrorActionPreference='Stop';try{$source=[IO.Path]::GetFullPath([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"+source64+"')));$target=[IO.Path]::GetFullPath([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"+target64+"')));$drive=[IO.Path]::GetPathRoot($target);if($drive.StartsWith('\\') -or ([IO.DriveInfo]::new($drive)).DriveFormat -ne 'NTFS'){throw 'Only local NTFS is qualified'};if(-not [String]::Equals([IO.Path]::GetDirectoryName($source),[IO.Path]::GetDirectoryName($target),[StringComparison]::OrdinalIgnoreCase)){throw 'Temporary must share target directory'};if([IO.Directory]::Exists($target)){throw 'Target is a directory'};$parent=[IO.DirectoryInfo]::new([IO.Path]::GetDirectoryName($target));while($null -ne $parent){if(($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Reparse parents are unqualified'};$parent=$parent.Parent};if([IO.File]::Exists($target) -and (([IO.File]::GetAttributes($target) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){throw 'Reparse targets are unqualified'};if([IO.File]::Exists($target)){[IO.File]::Replace($source,$target,[NullString]::Value)}else{[IO.File]::Move($source,$target)};Write-Output 'ATOMIC_PRESET_SAVED';exit 0}catch{exit 2}"
 var output: Array=[]
 var result: int=OS.execute(executable,PackedStringArray(["-NoProfile","-NonInteractive","-Command",command]),output,true,false)
 if result!=0 or output.is_empty() or not str(output[0]).contains("ATOMIC_PRESET_SAVED"):
  return {"ok":false,"error":"Atomic local-NTFS replace failed or unsupported; target preserved, temporary retained"}
 return {"ok":true,"error":""}
