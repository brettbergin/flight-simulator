extends RefCounted
# Original MIT presentation buffer. Native snapshots and instrument truth remain
# untouched. Input poses already share the host's local rendering frame.

var _session: String = ""
var _tick: int = -1
var _position := Vector3.ZERO
var _rotation := Quaternion.IDENTITY
var _previous_position := Vector3.ZERO
var _previous_rotation := Quaternion.IDENTITY
var _paired: bool = false

func clear() -> void:
	_session = ""
	_tick = -1
	_position = Vector3.ZERO
	_rotation = Quaternion.IDENTITY
	_previous_position = Vector3.ZERO
	_previous_rotation = Quaternion.IDENTITY
	_paired = false

func has_pose() -> bool:
	return _tick >= 0

func _valid_pose(session: String, tick: int, position: Vector3, basis: Basis) -> bool:
	if session.is_empty() or tick < 0 or not position.is_finite() or not basis.x.is_finite() or not basis.y.is_finite() or not basis.z.is_finite():
		return false
	# Reject scale/shear/reflection rather than silently treating it as attitude.
	return absf(basis.x.length_squared()-1.0) <= 0.001 and absf(basis.y.length_squared()-1.0) <= 0.001 and absf(basis.z.length_squared()-1.0) <= 0.001 and absf(basis.x.dot(basis.y)) <= 0.001 and absf(basis.x.dot(basis.z)) <= 0.001 and absf(basis.y.dot(basis.z)) <= 0.001 and absf(basis.determinant()-1.0) <= 0.001

func reset(session: String, tick: int, position: Vector3, basis: Basis) -> void:
	clear()
	if not _valid_pose(session,tick,position,basis):
		return
	_session = session
	_tick = tick
	_position = position
	_rotation = basis.get_rotation_quaternion().normalized()
	_previous_position = _position
	_previous_rotation = _rotation

func push(session: String, tick: int, position: Vector3, basis: Basis) -> bool:
	if not _valid_pose(session,tick,position,basis):
		clear()
		return false
	if not has_pose() or session != _session or tick <= _tick or tick-_tick != 1:
		# A valid gap/session change is a new single endpoint, never a stale blend.
		reset(session,tick,position,basis)
		return true
	_previous_position = _position
	_previous_rotation = _rotation
	_position = position
	_rotation = basis.get_rotation_quaternion().normalized()
	if _previous_rotation.dot(_rotation) < 0.0:
		_rotation = Quaternion(-_rotation.x,-_rotation.y,-_rotation.z,-_rotation.w)
	_tick = tick
	_paired = true
	return true

func sample(alpha: float, interpolate: bool = true) -> Transform3D:
	# Empty/invalid has no live pose: the host must check has_pose() before use.
	if not is_finite(alpha):
		clear()
	if not has_pose():
		return Transform3D.IDENTITY
	if not interpolate or not _paired:
		return Transform3D(Basis(_rotation),_position)
	var weight := clampf(alpha,0.0,1.0)
	return Transform3D(Basis(_previous_rotation.slerp(_rotation,weight).normalized()),_previous_position.lerp(_position,weight))
