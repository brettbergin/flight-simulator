extends RefCounted
## Original MIT. Pure copied InputPreset display; no Input/device/native access.
const Preset = preload("res://input/input_preset.gd")
const ACTIONS = ["pause_menu","controls_panel","look_hold","view_cycle","view_cockpit","view_panel","recenter","map_toggle","runway_toggle","map_zoom_in","map_zoom_out","brake_hold","both_brakes","idle"]
const AXES = ["roll","pitch","yaw","throttle","mixture","trim"]
const SYSTEMS = ["engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed"]
const AVAILABILITY = "Current device availability and observation are unverified here; open paused Controls to inspect observed status."

static func _keys(keys: Array) -> String:
	var names: PackedStringArray = []
	for key in keys: names.append(OS.get_keycode_string(int(key)))
	return "/".join(names)

static func pointer_source_hint(source: Dictionary) -> String:
	# Same physical-key/mouse conventions as Scene.pointer_source_hint.
	match source.get("kind"):
		"physical_keys": return _keys(source.keys)
		"mouse_button": return "Mouse " + str(source.button)
		"joy_button": return "CONFIGURED %s button %s" % [source.slot,source.index]
	return "Unavailable binding"

static func _sources(binding: Dictionary) -> String:
	var hints: PackedStringArray = []
	for source in binding.sources: hints.append(pointer_source_hint(source))
	return " OR ".join(hints)

static func _axis(binding: Dictionary) -> String:
	match binding.kind:
		"fixed": return "Fixed %s (configured assignment, not measured state)" % str(binding.value)
		"key_pair": return "Negative: %s   |   Positive: %s (configured key pair)" % [_keys(binding.negative),_keys(binding.positive)]
		"joy_axis": return "CONFIGURED %s axis %s | %s | %s" % [binding.slot,binding.index,binding.range,"Reversed" if binding.invert else "Not reversed"]
	return "Unavailable binding"

static func view(preset: Variant) -> Dictionary:
	var checked: Dictionary = {"ok":false,"error":"Unavailable: unsupported or missing preset version"}
	if preset is Dictionary:
		var version: Variant = preset.get("version")
		if typeof(version) in [TYPE_INT,TYPE_FLOAT]:
			if version == 1: checked = Preset.validate_preset(preset)
			elif version == 2: checked = Preset.validate_preset_v2(preset)
	var result: Dictionary = {"available":checked.ok,"error":checked.error,"actions":[],"axes":[],"systems":[],"availability":AVAILABILITY,"reserved":"Escape retains its reserved pause/menu role."}
	var value: Dictionary = checked.value if checked.ok else {}
	for id in ACTIONS:
		var row: Dictionary = {"id":id,"available":false,"text":"Unavailable: no validated binding"}
		for binding in value.get("actions",[]):
			if binding.id == id: row.available=true; row.text=_sources(binding)
		result.actions.append(row)
	for target in AXES:
		var row: Dictionary = {"id":target,"available":false,"text":"Unavailable: no validated binding"}
		for binding in value.get("axes",[]):
			if binding.target == target: row.available=true; row.text=_axis(binding)
		result.axes.append(row)
	for id in SYSTEMS:
		var row: Dictionary = {"id":id,"available":false,"text":"Unavailable: actual v2 systems required"}
		for binding in value.get("systems",[]):
			if binding.id == id: row.available=true; row.text="%s | %s" % [_sources(binding),binding.kind]
		result.systems.append(row)
	return result
