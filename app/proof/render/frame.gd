extends RefCounted
# Private presentation experiment, not a public world/physics contract.
# GDScript float scalars are binary64; Vector3 remains binary32 in this pin.
const SEMI_MAJOR: float = 6378137.0
const FLATTENING: float = 1.0 / 298.257223563

static func dot64(a: Array, b: Array) -> float:
	return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]

static func axes(latitude: float, longitude: float) -> Array:
	return [[-sin(longitude),cos(longitude),0.0],[cos(latitude)*cos(longitude),cos(latitude)*sin(longitude),sin(latitude)],[sin(latitude)*cos(longitude),sin(latitude)*sin(longitude),-cos(latitude)]]

static func geographic(latitude: float, longitude: float, height: float) -> Array:
	var e2: float = FLATTENING*(2.0-FLATTENING)
	var n: float = SEMI_MAJOR/sqrt(1.0-e2*sin(latitude)*sin(latitude))
	return [(n+height)*cos(latitude)*cos(longitude),(n+height)*cos(latitude)*sin(longitude),(n*(1.0-e2)+height)*sin(latitude)]

static func axes_at(point: Array) -> Array:
	var e2: float = FLATTENING*(2.0-FLATTENING)
	var radial: float = sqrt(point[0]*point[0]+point[1]*point[1])
	var latitude: float = atan2(point[2],radial*(1.0-e2))
	for iteration in 10:
		var n: float = SEMI_MAJOR/sqrt(1.0-e2*sin(latitude)*sin(latitude))
		latitude=atan2(point[2]+e2*n*sin(latitude),radial)
	return axes(latitude,atan2(point[1],point[0]))

static func canonical(origin: Array, frame: Array, offset: Array) -> Array:
	return [origin[0]+frame[0][0]*offset[0]+frame[1][0]*offset[1]+frame[2][0]*offset[2],origin[1]+frame[0][1]*offset[0]+frame[1][1]*offset[1]+frame[2][1]*offset[2],origin[2]+frame[0][2]*offset[0]+frame[1][2]*offset[1]+frame[2][2]*offset[2]]

static func direction(point: Array, frame: Array) -> Vector3:
	return Vector3(dot64(point,frame[0]),dot64(point,frame[1]),dot64(point,frame[2]))

static func local_position(point: Array, anchor: Array, frame: Array) -> Vector3:
	return direction([point[0]-anchor[0],point[1]-anchor[1],point[2]-anchor[2]],frame)

static func object_basis(original_frame: Array, render_frame: Array) -> Basis:
	return Basis(direction(original_frame[0],render_frame),direction(original_frame[1],render_frame),direction(original_frame[2],render_frame))
