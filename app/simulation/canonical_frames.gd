extends RefCounted
# Original MIT. Canonical calculations use binary64 scalar Arrays until final
# local float Vector3/Basis construction. EUS is east/up/south; native body is
# forward/right/down. The model's axes are right/up/aft.

static func finite_array(value: Variant, size: int) -> bool:
	if not value is Array or value.size() != size:
		return false
	for element in value:
		if not (element is float or element is int) or not is_finite(float(element)):
			return false
	return true

static func anchor(latitude: float, longitude: float, height: float) -> Dictionary:
	if not is_finite(latitude) or not is_finite(longitude) or not is_finite(height) or absf(latitude)>PI/2 or absf(longitude)>PI:
		return {}
	var s: float = sin(latitude)
	var c: float = cos(latitude)
	var sl: float = sin(longitude)
	var cl: float = cos(longitude)
	var f: float = 1.0/298.257223563
	var e2: float = f*(2.0-f)
	var n: float = 6378137.0/sqrt(1.0-e2*s*s)
	return {"ecef":[(n+height)*c*cl,(n+height)*c*sl,(n*(1.0-e2)+height)*s],
		"rotation":[-sl,cl,0.0,c*cl,c*sl,s,s*cl,s*sl,-c]}

static func multiply(a: Array, b: Array) -> Array:
	var result: Array = []
	for row in 3:
		for column in 3:
			result.append(float(a[row*3])*float(b[column])+float(a[row*3+1])*float(b[3+column])+float(a[row*3+2])*float(b[6+column]))
	return result

static func rotate(rotation: Array, position: Array) -> Array:
	var result: Array = []
	for row in 3:
		result.append(float(rotation[row*3])*float(position[0])+float(rotation[row*3+1])*float(position[1])+float(rotation[row*3+2])*float(position[2]))
	return result if finite_array(result,3) else []

static func project(ecef: Array, origin: Array, rotation: Array) -> Array:
	if not finite_array(ecef,3) or not finite_array(origin,3) or not finite_array(rotation,9):
		return []
	var delta: Array=[float(ecef[0])-float(origin[0]),float(ecef[1])-float(origin[1]),float(ecef[2])-float(origin[2])]
	return rotate(rotation,delta) if finite_array(delta,3) else []

static func quaternion_matrix(q: Array) -> Array:
	var w: float=q[0]
	var x: float=q[1]
	var y: float=q[2]
	var z: float=q[3]
	return [1.0-2.0*(y*y+z*z),2.0*(x*y-z*w),2.0*(x*z+y*w),
		2.0*(x*y+z*w),1.0-2.0*(x*x+z*z),2.0*(y*z-x*w),
		2.0*(x*z-y*w),2.0*(y*z+x*w),1.0-2.0*(x*x+y*y)]

static func rigid(matrix: Variant) -> bool:
	if not finite_array(matrix,9):
		return false
	for row in 3:
		for other in 3:
			var dot: float=0.0
			for col in 3:
				dot+=float(matrix[row*3+col])*float(matrix[other*3+col])
			if absf(dot-(1.0 if row==other else 0.0))>0.00001:
				return false
	var determinant: float=matrix[0]*(matrix[4]*matrix[8]-matrix[5]*matrix[7])-matrix[1]*(matrix[3]*matrix[8]-matrix[5]*matrix[6])+matrix[2]*(matrix[3]*matrix[7]-matrix[4]*matrix[6])
	return absf(determinant-1.0)<0.00001

static func derive(snapshot: Dictionary, prepared: Dictionary) -> Dictionary:
	if not snapshot.get("position") is Dictionary or not snapshot.get("ecef_position_m") is Dictionary or not snapshot.get("orientation_body_to_ned") is Dictionary:
		return {}
	var p: Dictionary=snapshot.position
	var e: Dictionary=snapshot.ecef_position_m
	var q: Dictionary=snapshot.orientation_body_to_ned
	var position: Array=[e.get("x"),e.get("y"),e.get("z")]
	var quaternion: Array=[q.get("w"),q.get("x"),q.get("y"),q.get("z")]
	var latitude: Variant=p.get("latitude_rad")
	var longitude: Variant=p.get("longitude_rad")
	if not finite_array(position,3) or not finite_array(quaternion,4) or not (latitude is float or latitude is int) or not (longitude is float or longitude is int):
		return {}
	if not is_finite(float(latitude)) or not is_finite(float(longitude)) or absf(float(latitude))>PI/2 or absf(float(longitude))>PI or not finite_array(prepared.get("ecef"),3) or not rigid(prepared.get("rotation")):
		return {}
	var norm: float=0.0
	for component in quaternion:
		norm+=float(component)*float(component)
	if absf(norm-1.0)>0.00001:
		return {}
	var s: float=sin(float(latitude))
	var c: float=cos(float(latitude))
	var sl: float=sin(float(longitude))
	var cl: float=cos(float(longitude))
	# Columns of NED-to-ECEF: north, east, down at this snapshot's position.
	var ned_to_ecef: Array=[-s*cl,-sl,-c*cl,-s*sl,cl,-c*sl,c,0.0,-s]
	var common: Array=multiply(prepared.rotation,multiply(ned_to_ecef,quaternion_matrix(quaternion)))
	if not rigid(common):
		return {}
	return {"ecef_position_m":position.duplicate(true),"anchor_eus_position_m":project(position,prepared.ecef,prepared.rotation),"body_to_anchor_eus":common}

static func matrix_quaternion(m: Array) -> Array:
	var q: Array=[]
	var t: float=m[0]+m[4]+m[8]
	if t>0.0:
		var s: float=sqrt(t+1.0)*2.0
		q=[0.25*s,(m[7]-m[5])/s,(m[2]-m[6])/s,(m[3]-m[1])/s]
	elif m[0]>m[4] and m[0]>m[8]:
		var s: float=sqrt(1.0+m[0]-m[4]-m[8])*2.0
		q=[(m[7]-m[5])/s,0.25*s,(m[1]+m[3])/s,(m[2]+m[6])/s]
	elif m[4]>m[8]:
		var s: float=sqrt(1.0+m[4]-m[0]-m[8])*2.0
		q=[(m[2]-m[6])/s,(m[1]+m[3])/s,0.25*s,(m[5]+m[7])/s]
	else:
		var s: float=sqrt(1.0+m[8]-m[0]-m[4])*2.0
		q=[(m[3]-m[1])/s,(m[2]+m[6])/s,(m[5]+m[7])/s,0.25*s]
	return q

static func interpolate_rotation(a: Array, b: Array, alpha: float) -> Array:
	var qa: Array=matrix_quaternion(a)
	var qb: Array=matrix_quaternion(b)
	var dot: float=0.0
	for index in 4:
		dot+=float(qa[index])*float(qb[index])
	if dot<0.0:
		dot=-dot
		for index in 4:
			qb[index]=-float(qb[index])
	var left: float=1.0-alpha
	var right: float=alpha
	if dot<0.9995:
		var angle: float=acos(clampf(dot,-1.0,1.0))
		left=sin((1.0-alpha)*angle)/sin(angle)
		right=sin(alpha*angle)/sin(angle)
	var mixed: Array=[]
	var norm: float=0.0
	for index in 4:
		var value: float=float(qa[index])*left+float(qb[index])*right
		mixed.append(value)
		norm+=value*value
	for index in 4:
		mixed[index]=float(mixed[index])/sqrt(norm)
	return quaternion_matrix(mixed)

static func transform(position: Array, body_rotation: Array) -> Transform3D:
	var model: Array=multiply(body_rotation,[0.0,0.0,-1.0,1.0,0.0,0.0,0.0,-1.0,0.0])
	return Transform3D(Basis(Vector3(model[0],model[3],model[6]),Vector3(model[1],model[4],model[7]),Vector3(model[2],model[5],model[8])),Vector3(position[0],position[1],position[2]))
