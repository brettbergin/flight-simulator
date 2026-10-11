extends RefCounted
# Original MIT. Closed, stateless presentation settings; no camera or flight state.

static func defaults() -> Dictionary:
	return {"preset": "cockpit", "fov_deg": 72.0, "external_response": "smooth"}

static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() != 3:
		return _rejected("Views settings require exactly three fields.")
	for key in value:
		if typeof(key) != TYPE_STRING or key not in ["preset", "fov_deg", "external_response"]:
			return _rejected("Unknown Views settings field.")
	for key in ["preset", "fov_deg", "external_response"]:
		if not value.has(key): return _rejected("Missing Views settings field.")
	if describe(value.preset) == null:
		return _rejected("Choose a supported view preset.")
	if typeof(value.fov_deg) != TYPE_FLOAT or not is_finite(value.fov_deg) or value.fov_deg < 35.0 or value.fov_deg > 90.0:
		return _rejected("Field of view must be a finite float from 35 to 90 degrees.")
	if typeof(value.external_response) != TYPE_STRING or value.external_response not in ["smooth", "immediate"]:
		return _rejected("External response must be smooth or immediate.")
	return {"ok": true, "error": "", "value": value.duplicate(true)}

static func describe(preset: Variant) -> Variant:
	if typeof(preset) != TYPE_STRING: return null
	match preset:
		"cockpit":
			# Preserve the existing traditional cockpit base, including its
			# Vector3 normalization. The host retains its current transform order.
			var direction := Vector3(0.0, -0.268, -1.0).normalized()
			return {"mode": 0, "base_direction": [float(direction.x), float(direction.y), float(direction.z)], "default_fov_deg": 72.0}
		"forward_horizon":
			return {"mode": 0, "base_direction": [0.0, 0.0, -1.0], "default_fov_deg": 72.0}
		"left_window":
			return {"mode": 0, "base_direction": [-1.0, 0.0, 0.0], "default_fov_deg": 72.0}
		"right_window":
			return {"mode": 0, "base_direction": [1.0, 0.0, 0.0], "default_fov_deg": 72.0}
		"panel":
			return {"mode": 3, "base_direction": null, "default_fov_deg": 58.0}
		"chase":
			return {"mode": 1, "base_direction": null, "default_fov_deg": 72.0}
		"orbit":
			return {"mode": 2, "base_direction": null, "default_fov_deg": 72.0}
	return null

static func _rejected(message: String) -> Dictionary:
	return {"ok": false, "error": message, "value": null}
