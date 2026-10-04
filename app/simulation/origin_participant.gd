extends Node3D
# Original MIT. Attach to an existing visual root; no native/physics calls.
const Frames = preload("res://simulation/canonical_frames.gd")
const UInt64 = preload("res://simulation/uint64.gd")
const CANDIDATE_KEYS = ["session_id","origin_ecef_m","ecef_to_eus","version"]
var _configured: bool = false
var _session: String = ""
var _anchor: Array = []
var _rotation: Array = []
var _canonical_ecef: Array = []
var _artist_basis: Basis = Basis.IDENTITY
var _last_version: String = "0"
var _prepared: Variant = null
var _prepared_scene: Dictionary = {}
var _parent_pose: Transform3D = Transform3D.IDENTITY
var _parent_id: int = 0

func _scalars(value: Variant, count: int) -> bool:
	if not value is Array or value.size()!=count:
		return false
	for component in value:
		if typeof(component)!=TYPE_FLOAT or not is_finite(component):
			return false
	return true

func _basis_rigid(value: Basis) -> bool:
	if not value.is_finite():
		return false
	return Frames.rigid([value.x.x,value.y.x,value.z.x,value.x.y,value.y.y,value.z.y,value.x.z,value.y.z,value.z.z])

# local_basis is the desired root basis in the fixed-anchor render EUS frame.
# Configure stores canonical values only; it neither reparents nor moves nodes.
func configure(session_id: String, anchor_ecef: Array, ecef_to_eus: Array, canonical_root_eus: Array, local_basis: Basis = Basis.IDENTITY) -> bool:
	if not Thread.is_main_thread() or _configured or session_id.is_empty() or not _scalars(anchor_ecef,3) or not _scalars(ecef_to_eus,9) or not Frames.rigid(ecef_to_eus) or not _scalars(canonical_root_eus,3) or not _basis_rigid(local_basis):
		return false
	var ecef: Array=[]
	for axis in range(3):
		var delta: float=0.0
		for row in range(3):
			delta+=ecef_to_eus[row*3+axis]*canonical_root_eus[row]
		ecef.append(anchor_ecef[axis]+delta)
	if not _scalars(ecef,3):
		return false
	_session=session_id
	_anchor=anchor_ecef.duplicate(true)
	_rotation=ecef_to_eus.duplicate(true)
	_canonical_ecef=ecef
	_artist_basis=local_basis
	_configured=true
	return true

func set_canonical_pose(ecef_position: Array, local_basis: Basis) -> bool:
	if not Thread.is_main_thread() or not _configured or not _scalars(ecef_position,3) or not _basis_rigid(local_basis):
		return false
	_canonical_ecef=ecef_position.duplicate(true)
	_artist_basis=local_basis
	_prepared=null
	_prepared_scene={}
	return true

func _keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size()!=expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true

func _scene() -> Dictionary:
	var pending: Array[Node]=[self]
	var nodes: Dictionary={}
	while not pending.is_empty():
		var node: Node=pending.pop_back()
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			return {"ok":false,"nodes":{}}
		if node is Node3D:
			if not node.transform.is_finite():
				return {"ok":false,"nodes":{}}
			nodes[node.get_instance_id()]=node.transform
		for child in node.get_children():
			pending.append(child)
	return {"ok":true,"nodes":nodes}

func _parent_state() -> Dictionary:
	if not is_inside_tree():
		return {"ok":false,"pose":Transform3D.IDENTITY,"id":0}
	var parent: Node3D=get_parent_node_3d() if not top_level else null
	if parent==null:
		return {"ok":true,"pose":Transform3D.IDENTITY,"id":0}
	if not is_instance_valid(parent) or parent.is_queued_for_deletion() or not parent.global_transform.is_finite() or absf(parent.global_basis.determinant())<1e-12:
		return {"ok":false,"pose":Transform3D.IDENTITY,"id":0}
	return {"ok":true,"pose":parent.global_transform,"id":parent.get_instance_id()}

func _failure(candidate: Dictionary, error: String) -> Dictionary:
	var session: String=candidate.session_id if candidate.get("session_id") is String else _session
	var version: String=candidate.version if candidate.get("version") is String else "0"
	return {"ok":false,"error":error,"session_id":session,"version":version,"data":null}

func prepare_origin(candidate: Dictionary) -> Dictionary:
	if not Thread.is_main_thread():
		return {"ok":false,"error":"Visual participant requires main thread","session_id":"","version":"0","data":null}
	_prepared=null
	_prepared_scene={}
	if not _configured:
		return _failure(candidate,"Unconfigured visual participant")
	if not _keys(candidate,CANDIDATE_KEYS) or not candidate.get("session_id") is String or candidate.get("session_id")!=_session or not _scalars(candidate.get("origin_ecef_m"),3) or not _scalars(candidate.get("ecef_to_eus"),9) or candidate.get("ecef_to_eus")!=_rotation or not UInt64.valid(candidate.get("version")) or UInt64.compare(candidate.version,_last_version)<=0:
		return _failure(candidate,"Malformed/stale/incompatible origin candidate")
	var scene: Dictionary=_scene()
	var parent: Dictionary=_parent_state()
	if not scene.ok or not parent.ok:
		return _failure(candidate,"Nonfinite/retired visual root, parent or descendants")
	var local: Array=Frames.project(_canonical_ecef,candidate.origin_ecef_m,_rotation)
	if not _scalars(local,3):
		return _failure(candidate,"Unrepresentable canonical projection")
	var desired:=Transform3D(_artist_basis,Vector3(local[0],local[1],local[2]))
	var relative: Transform3D=parent.pose.affine_inverse()*desired
	if not desired.is_finite() or not relative.is_finite():
		return _failure(candidate,"Projection exceeds finite renderer transform domain")
	_parent_pose=parent.pose
	_parent_id=parent.id
	_prepared_scene=scene.nodes.duplicate(true)
	_prepared={"ok":true,"error":"","session_id":_session,"version":candidate.version,"data":{"transform":relative}}
	return _prepared.duplicate(true)

func commit_origin(plan: Dictionary) -> Dictionary:
	if not Thread.is_main_thread() or _prepared==null or plan!=_prepared:
		return {"ok":false,"error":"Stale/reused/mutated visual origin plan"}
	var scene: Dictionary=_scene()
	var parent: Dictionary=_parent_state()
	if not scene.ok or scene.nodes!=_prepared_scene or not parent.ok or parent.id!=_parent_id or parent.pose!=_parent_pose:
		_prepared=null
		_prepared_scene={}
		return {"ok":false,"error":"Visual hierarchy/pose changed after prepare"}
	var prepared_transform: Transform3D=_prepared.data.transform
	var version: String=_prepared.version
	_prepared=null
	_prepared_scene={}
	transform=prepared_transform
	_last_version=version
	return {"ok":true,"error":""}
