extends RefCounted
# Original MIT renderer-only transaction registry; ADR007. No native calls.
const UInt64 = preload("res://simulation/uint64.gd")
const CATEGORIES = ["ownship", "cockpit", "camera", "world", "light", "spatial_audio", "local_particles"]
const CANDIDATE_KEYS = ["session_id", "origin_ecef_m", "ecef_to_eus", "version"]
const PLAN_KEYS = ["ok", "error", "session_id", "version", "data"]
const COMMIT_KEYS = ["ok", "error"]
var _session: String
var _anchor: Array
var _rotation: Array
var _version: String = "0"
var _entries: Dictionary = {}
var _committed: Variant = null
var _valid: bool = false
var _needs_adoption: bool = true
var _terminal: bool = false
var _transaction: bool = false
var _violation: String = ""
var _error: String = "Origin not adopted"

func _init(session_id: String, anchor_ecef: Array, ecef_to_eus: Array) -> void:
	_session = session_id
	if not Thread.is_main_thread() or _session.is_empty() or not _finite_array(anchor_ecef, 3) or not _rigid_rotation(ecef_to_eus):
		_anchor = []
		_rotation = []
		_terminal = true
		_error = "Invalid session/anchor/rotation or non-main-thread construction"
		return
	_anchor = anchor_ecef.duplicate(true)
	_rotation = ecef_to_eus.duplicate(true)

func _finite_array(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for item in value:
		if typeof(item) != TYPE_FLOAT or not is_finite(item):
			return false
	return true

func _rigid_rotation(value: Variant) -> bool:
	if not _finite_array(value, 9):
		return false
	for row in range(3):
		for other in range(3):
			var dot: float = 0.0
			for axis in range(3):
				dot += value[row*3+axis]*value[other*3+axis]
			if absf(dot-(1.0 if row == other else 0.0)) > 1e-9:
				return false
	var det: float = value[0]*(value[4]*value[8]-value[5]*value[7])-value[1]*(value[3]*value[8]-value[5]*value[6])+value[2]*(value[3]*value[7]-value[4]*value[6])
	return absf(det-1.0) <= 1e-9

func _keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true

# Opaque owned data cannot contain objects, callables, signals or cyclic graphs.
func _owned(value: Variant, depth: int = 0) -> bool:
	if depth > 32:
		return false
	match typeof(value):
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return false
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_QUATERNION, TYPE_BASIS, TYPE_TRANSFORM2D, TYPE_TRANSFORM3D:
			return value.is_finite()
		TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			for item in value:
				if not _owned(item, depth+1):
					return false
		TYPE_PROJECTION:
			return value[0].is_finite() and value[1].is_finite() and value[2].is_finite() and value[3].is_finite()
		TYPE_COLOR:
			return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
		TYPE_AABB, TYPE_RECT2:
			return value.position.is_finite() and value.size.is_finite()
		TYPE_PLANE:
			return value.normal.is_finite() and is_finite(value.d)
		TYPE_DICTIONARY:
			for key in value:
				if not _owned(key, depth+1) or not _owned(value[key], depth+1):
					return false
	return true

func _guard() -> String:
	if not Thread.is_main_thread():
		return "Origin calls require the main thread"
	if _transaction:
		_violation = "Reentrant origin call during transaction"
		return _violation
	if _terminal:
		return _error
	return ""

# Internal facade coordination, not an additional public/wire value.
# Facade coordinates the same main-thread transaction; these are internal,
# not additional app/wire APIs. Wrong-thread callers never read registry state.
func _is_transaction_active() -> bool:
	return true if not Thread.is_main_thread() else _transaction

func _note_facade_reentry() -> void:
	if Thread.is_main_thread() and _transaction:
		_violation = "Reentrant facade call during origin prepare/commit"

func _has_terminal_failure() -> bool:
	return true if not Thread.is_main_thread() else _terminal

func _read_owned() -> Dictionary:
	var active: Array[String] = []
	var absent: Array[String] = []
	for id in _entries:
		if _entries[id].absent:
			for category in _entries[id].categories:
				absent.append(category)
		else:
			active.append(id)
	active.sort()
	absent.sort()
	return {"valid": _valid, "error": _error, "committed": _committed.duplicate(true) if _committed != null else null, "active_ids": active, "absent_categories": absent}

func read_origin() -> Dictionary:
	if not Thread.is_main_thread() or _transaction:
		var guard: String = _guard()
		return {"valid": false, "error": guard, "committed": null, "active_ids": [], "absent_categories": []}
	if _valid and (not _ancestry_error().is_empty() or not _scene_state().ok):
		_valid = false
		_terminal = true
		_error = "Origin participant scene retired/nonfinite/overlapping; reset required"
	return _read_owned()

func _result(ok: bool, error: String = "") -> Dictionary:
	return {"ok": ok, "error": error, "origin": _read_owned()}

func _reject(error: String) -> Dictionary:
	if not Thread.is_main_thread():
		return {"ok": false, "error": error, "origin": {"valid": false, "error": error, "committed": null, "active_ids": [], "absent_categories": []}}
	if _transaction:
		var value: Dictionary = _read_owned()
		value.valid = false
		value.error = error
		return {"ok": false, "error": error, "origin": value}
	return _result(false, error)

func _node(entry: Dictionary) -> Node3D:
	if entry.absent:
		return null
	var value: Variant = entry.reference.get_ref()
	return value if is_instance_valid(value) and value is Node3D and not value.is_queued_for_deletion() else null

func _ancestry_error() -> String:
	var roots: Array[Node3D] = []
	for entry in _entries.values():
		if entry.absent:
			continue
		var root: Node3D = _node(entry)
		if root == null:
			return "Origin participant retired"
		for other in roots:
			if root == other or root.is_ancestor_of(other) or other.is_ancestor_of(root):
				return "Overlapping transform-owning participant roots"
		roots.append(root)
	return ""

func register_participant(id: String, participant: Object, categories: Array) -> Dictionary:
	var guard: String = _guard()
	if not guard.is_empty():
		return _reject(guard)
	if id.is_empty() or _entries.has(id) or _entries.size() >= 64:
		return _reject("Invalid/duplicate participant ID or registry capacity")
	var seen: Dictionary = {}
	for category in categories:
		if not category is String or not CATEGORIES.has(category) or seen.has(category):
			return _reject("Invalid/duplicate participant category")
		seen[category] = true
		for entry in _entries.values():
			if entry.categories.has(category):
				return _reject("Category already declared")
	if participant != null:
		if not is_instance_valid(participant) or not participant is Node3D or participant.is_queued_for_deletion() or not participant.has_method("prepare_origin") or not participant.has_method("commit_origin"):
			return _reject("Participant must be a live Node3D root with origin methods")
		for entry in _entries.values():
			if not entry.absent:
				var other: Node3D = _node(entry)
				if other == null or participant == other or participant.is_ancestor_of(other) or other.is_ancestor_of(participant):
					return _reject("Retired/overlapping participant root")
	_entries[id] = {"absent": participant == null, "reference": weakref(participant) if participant != null else null, "categories": categories.duplicate(true)}
	_valid = false
	_needs_adoption = true
	_error = "Origin registry changed; complete adoption required"
	return _result(true)

func unregister_participant(id: String) -> Dictionary:
	var guard: String = _guard()
	if not guard.is_empty():
		return _reject(guard)
	if not _entries.has(id):
		return _reject("Unknown participant ID")
	_entries.erase(id)
	_valid = false
	_needs_adoption = true
	_error = "Origin registry changed; complete adoption required"
	return _result(true)

func _candidate(origin: Array, version: String) -> Dictionary:
	return {"session_id": _session, "origin_ecef_m": origin.duplicate(true), "ecef_to_eus": _rotation.duplicate(true), "version": version}

func _scene_state() -> Dictionary:
	var result: Dictionary = {}
	var pending: Array[Node] = []
	for entry in _entries.values():
		if not entry.absent:
			var root: Node3D = _node(entry)
			if root == null:
				return {"ok": false, "nodes": {}}
			pending.append(root)
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			return {"ok": false, "nodes": {}}
		if node is Node3D:
			if not node.transform.is_finite():
				return {"ok": false, "nodes": {}}
			result[node.get_instance_id()] = node.transform
		for child in node.get_children():
			pending.append(child)
	return {"ok": true, "nodes": result}

func _sorted_ids(nodes: Dictionary) -> Array:
	var ids: Array = nodes.keys()
	ids.sort()
	return ids

func _plan_valid(plan: Variant, candidate: Dictionary) -> bool:
	if not _keys(plan, PLAN_KEYS) or typeof(plan.ok) != TYPE_BOOL or not plan.error is String or not plan.session_id is String or not plan.version is String:
		return false
	if plan.session_id != candidate.session_id or plan.version != candidate.version:
		return false
	if plan.ok:
		return plan.error.is_empty() and plan.data is Dictionary and _owned(plan.data)
	return not plan.error.is_empty() and plan.data == null

func _finish_failure(error: String, terminal: bool) -> Dictionary:
	_transaction = false
	if terminal:
		_terminal = true
		_valid = false
	_error = error
	return _result(false, error)

func rebase(origin_ecef: Array) -> Dictionary:
	var guard: String = _guard()
	if not guard.is_empty():
		return _reject(guard)
	if not _finite_array(origin_ecef, 3):
		return _reject("Origin must be three finite binary64 ECEF scalars")
	var current_origin: Array = _anchor if _committed == null else _committed.origin_ecef_m
	if _needs_adoption and origin_ecef != current_origin:
		return _reject("Initial/changed registry must adopt the current anchor first")
	var declared: Dictionary = {}
	for entry in _entries.values():
		for category in entry.categories:
			declared[category] = true
	if declared.size() != CATEGORIES.size():
		return _reject("All origin categories must be explicitly declared")
	var ancestry: String = _ancestry_error()
	if not ancestry.is_empty():
		return _finish_failure(ancestry, true)
	var next: Dictionary = UInt64.increment(_version)
	if not next.ok:
		return _reject("Origin version exhausted")
	var candidate: Dictionary = _candidate(origin_ecef, next.value)
	var baseline: Dictionary = _scene_state()
	if not baseline.ok:
		return _reject("Nonfinite/retired participant scene")
	_transaction = true
	_violation = ""
	var plans: Dictionary = {}
	var ids: Array = _entries.keys()
	ids.sort()
	for id in ids:
		var entry: Dictionary = _entries[id]
		if entry.absent:
			continue
		var root: Node3D = _node(entry)
		if root == null:
			return _finish_failure("Participant retired during prepare", true)
		var argument: Dictionary = candidate.duplicate(true)
		var plan: Variant = root.call("prepare_origin", argument)
		var after: Dictionary = _scene_state()
		if not after.ok or after.nodes != baseline.nodes or not _ancestry_error().is_empty():
			return _finish_failure("Prepare mutated/retired participant scene", true)
		if not _violation.is_empty():
			return _finish_failure(_violation, false)
		if argument != candidate or not _plan_valid(plan, candidate):
			return _finish_failure("Malformed/stale/mutated origin plan", false)
		if not plan.ok:
			return _finish_failure(plan.error, false)
		plans[id] = plan.duplicate(true)
	for id in ids:
		var entry: Dictionary = _entries[id]
		if entry.absent:
			continue
		var root: Node3D = _node(entry)
		if root == null:
			return _finish_failure("Participant retired during commit", true)
		var argument: Dictionary = plans[id].duplicate(true)
		var result: Variant = root.call("commit_origin", argument)
		if not _violation.is_empty() or argument != plans[id] or not _keys(result, COMMIT_KEYS) or typeof(result.ok) != TYPE_BOOL or not result.error is String or not result.ok or not result.error.is_empty():
			return _finish_failure("Origin commit failed; scene coherence invalid, reset required", true)
		var after: Dictionary = _scene_state()
		if not after.ok or not _ancestry_error().is_empty() or _sorted_ids(after.nodes) != _sorted_ids(baseline.nodes):
			return _finish_failure("Participant scene retired/changed during commit", true)
	_committed = candidate.duplicate(true)
	_version = next.value
	_valid = true
	_needs_adoption = false
	_transaction = false
	_error = ""
	return _result(true)
