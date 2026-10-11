extends RefCounted
# Original MIT. ADR020 pure, closed application-session presentation options.

static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size()!=4:
		return _reject("Audio options require exactly four keys")
	for key in value:
		if typeof(key)!=TYPE_STRING or key not in ["enabled","engine_gain","airflow_gain","show_panel_captions"]:
			return _reject("Unknown audio option")
	for key in ["enabled","show_panel_captions"]:
		if typeof(value[key])!=TYPE_BOOL:
			return _reject("Audio %s must be bool" % key)
	for key in ["engine_gain","airflow_gain"]:
		if typeof(value[key])!=TYPE_FLOAT or not is_finite(value[key]) or value[key]<0.0 or value[key]>1.0:
			return _reject("Audio %s must be a finite float in 0..1" % key)
	return {"ok":true,"error":"","value":value.duplicate(true)}

static func _reject(reason: String) -> Dictionary:
	return {"ok":false,"error":reason,"value":null}
