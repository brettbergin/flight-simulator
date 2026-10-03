extends SceneTree
# Actual module is staged byte-for-byte by run.py; no tracked duplicate.
const Frame = preload("res://frame.gd")
const WIDTH: int = 2560
const HEIGHT: int = 1440
const FOV_DEG: float = 70.0
const PIXEL_BUDGET: float = 0.5
const REBASE_M: float = 2000.0
const BASIS_BUDGET: float = 2.0e-12
const FLOAT_BASIS_BUDGET: float = 2.0e-6
var checks: int = 0
var failures: Array[String] = []
var max_reference_pixels: float = 0.0
var max_transaction_pixels: float = 0.0
var max_roundtrip_m: float = 0.0
var negative_mixed_pixels: float = 0.0
var max_pre_rebase_radius_m: float = 0.0
var transactions: int = 0
var canonical_checks: int = 0

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func difference(a: Array, b: Array) -> Array:
	return [a[0]-b[0], a[1]-b[1], a[2]-b[2]]

func add(a: Array, b: Array) -> Array:
	return [a[0]+b[0], a[1]+b[1], a[2]+b[2]]

func dot(a: Array, b: Array) -> float:
	return float(a[0])*float(b[0])+float(a[1])*float(b[1])+float(a[2])*float(b[2])

func cross(a: Array, b: Array) -> Array:
	return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]

func length64(a: Array) -> float:
	return sqrt(dot(a,a))

func reference_axes(latitude: float, longitude: float) -> Array:
	var up: Array = [cos(latitude)*cos(longitude), cos(latitude)*sin(longitude), sin(latitude)]
	var east: Array = [-sin(longitude), cos(longitude), 0.0]
	return [east, up, cross(east,up)]

func transform64(axes: Array, offset: Array) -> Array:
	var output: Array = [0.0,0.0,0.0]
	for i in 3:
		for j in 3:
			output[i] += float(axes[j][i])*float(offset[j])
	return output

func camera_axes64(yaw: float, pitch: float) -> Array:
	# Independent closed-form Ry(yaw)*Rx(pitch), active camera→field EUS.
	return [[cos(yaw),0.0,-sin(yaw)], [sin(yaw)*sin(pitch),cos(pitch),cos(yaw)*sin(pitch)], [sin(yaw)*cos(pitch),-sin(pitch),cos(yaw)*cos(pitch)]]

func reference_pixel(offset_camera: Array) -> Vector2:
	var focal: float = HEIGHT/(2.0*tan(deg_to_rad(FOV_DEG)/2.0))
	return Vector2(WIDTH/2.0+focal*float(offset_camera[0])/-float(offset_camera[2]), HEIGHT/2.0-focal*float(offset_camera[1])/-float(offset_camera[2]))

func matrix_checks(axes: Array, label: String) -> void:
	for i in 3:
		expect(abs(dot(axes[i],axes[i])-1.0)<=BASIS_BUDGET,label+" unit"+str(i))
		for j in i:
			expect(abs(dot(axes[i],axes[j]))<=BASIS_BUDGET,label+" perpendicular")
	expect(length64(difference(cross(axes[0],axes[1]),axes[2]))<=BASIS_BUDGET,label+" EUS handedness")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size=Vector2i(WIDTH,HEIGHT)
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var camera: Camera3D = Camera3D.new()
	camera.fov=FOV_DEG
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	camera.near=0.05
	camera.far=100000.0
	viewport.add_child(camera)
	camera.make_current()
	await process_frame

	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://reference.json"))
	for point_case in fixture.points:
		var actual: Array = Frame.geographic(point_case.latitude_rad,point_case.longitude_rad,point_case.height_m)
		expect(length64(difference(actual,point_case.ecef_m))<=0.00000001,"WGS84 "+point_case.name)
		var axes: Array = Frame.axes_at(actual)
		matrix_checks(axes,point_case.name)
		var expected_axes: Array = reference_axes(point_case.latitude_rad,point_case.longitude_rad)
		for i in 3:
			expect(length64(difference(axes[i],expected_axes[i]))<=BASIS_BUDGET,"geodetic normal/basis "+point_case.name)
	var zero_frame: Array = Frame.axes(0.0,0.0)
	var zero_origin: Array = [6378137.0,0.0,0.0]
	expect(Frame.local_position([6378138.0,0.0,0.0],zero_origin,zero_frame).distance_to(Vector3.UP)<0.000001,"ECEF X→up")
	expect(Frame.local_position([6378137.0,1.0,0.0],zero_origin,zero_frame).distance_to(Vector3.RIGHT)<0.000001,"ECEF Y→east")
	expect(Frame.local_position([6378137.0,0.0,1.0],zero_origin,zero_frame).distance_to(Vector3.FORWARD)<0.000001,"ECEF Z→north=-render Z")
	# atan2(0,0) selects longitude zero here; no physically unique pole yaw exists.
	var exact_pole: Array = Frame.axes_at([0.0,0.0,6356752.314245179])
	matrix_checks(exact_pole,"exact pole convention")
	expect(length64(difference(exact_pole[0],Frame.axes(PI/2.0,0.0)[0]))<BASIS_BUDGET,"declared exact-pole atan2 convention")
	expect(length64(difference(exact_pole[0],Frame.axes(PI/2.0,1.0)[0]))>0.5,"exact-pole longitude ambiguity remains visible")

	for seam_case in fixture.seams:
		var a: Array = Frame.geographic(seam_case.a[0],seam_case.a[1],seam_case.a[2])
		var b: Array = Frame.geographic(seam_case.b[0],seam_case.b[1],seam_case.b[2])
		var fa: Array = Frame.axes_at(a)
		var fb: Array = Frame.axes_at(b)
		var local: Vector3 = Frame.local_position(b,a,fa)
		var roundtrip: Array = Frame.canonical(a,fa,[float(local.x),float(local.y),float(local.z)])
		var error_m: float = length64(difference(roundtrip,b))
		max_roundtrip_m=max(max_roundtrip_m,error_m)
		expect(error_m<=0.0001,"near-pole/dateline local roundtrip "+seam_case.name)
		var object_rotation: Basis = Frame.object_basis(fa,fb)
		expect(abs(object_rotation.determinant()-1.0)<=FLOAT_BASIS_BUDGET,"seam object basis determinant")
		expect((object_rotation.transposed()*object_rotation).is_equal_approx(Basis.IDENTITY),"seam object basis orthogonal")
		var seam_attitude: Basis = Basis(Vector3.UP,0.6)*Basis(Vector3.RIGHT,-0.2)
		var seam_offsets: Array = [[0.2,0.1,-0.8],[-0.15,-0.12,-1.0],[0.55,-0.22,-2.0]]
		var seam_points: Array = []
		for offset in seam_offsets:
			seam_points.append(add(b,transform64(fb,transform64(camera_axes64(0.6,-0.2),offset))))
		var seam_state: Array = [a,b,fa,fb,seam_points]
		var seam_bytes: PackedByteArray = var_to_bytes(seam_state)
		camera.transform=Transform3D(Frame.object_basis(fb,fa)*seam_attitude,Frame.local_position(b,a,fa))
		var seam_pixels: Array[Vector2] = []
		for i in seam_offsets.size():
			var pixel: Vector2 = camera.unproject_position(Frame.local_position(seam_points[i],a,fa))
			seam_pixels.append(pixel)
			var error_px: float = pixel.distance_to(reference_pixel(seam_offsets[i]))
			max_reference_pixels=max(max_reference_pixels,error_px)
			expect(error_px<=PIXEL_BUDGET,"near-pole/dateline Camera projection before")
		camera.transform=Transform3D(Frame.object_basis(fb,fb)*seam_attitude,Frame.local_position(b,b,fb))
		for i in seam_offsets.size():
			var pixel: Vector2 = camera.unproject_position(Frame.local_position(seam_points[i],b,fb))
			var reference_error: float = pixel.distance_to(reference_pixel(seam_offsets[i]))
			var transaction_error: float = pixel.distance_to(seam_pixels[i])
			max_reference_pixels=max(max_reference_pixels,reference_error)
			max_transaction_pixels=max(max_transaction_pixels,transaction_error)
			expect(reference_error<=PIXEL_BUDGET,"near-pole/dateline Camera projection after")
			expect(transaction_error<=PIXEL_BUDGET,"near-pole/dateline rebase continuity")
		expect(seam_bytes==var_to_bytes(seam_state),"near-pole/dateline canonical arrays byte-identical")

	var initial: Array = Frame.geographic(0.8,3.13,1000.0)
	var track_axes: Array = reference_axes(0.8,3.13)
	var anchor: Array = initial.duplicate(true)
	var render_axes: Array = Frame.axes_at(anchor)
	var offsets: Array = [[0.0,0.0,-0.8],[0.2,0.1,-0.8],[-0.15,-0.12,-1.0],[0.55,-0.22,-2.0],[-0.75,0.3,-4.0]]
	# 20×50km legs; 25×2km transactions each. Source points/camera stay binary64.
	for leg in 20:
		for segment in 25:
			var distance_m: float = float(leg*25+segment+1)*REBASE_M
			var camera_ecef: Array = add(initial,transform64(track_axes,[distance_m,1200.0*sin(float(leg)*0.17),50.0*cos(float(leg)*0.21)]))
			var field_axes: Array = Frame.axes_at(camera_ecef)
			var yaw: float = -1.2+0.12*float(leg)
			var pitch: float = 0.3*sin(float(leg)*0.31)
			var attitude64: Array = camera_axes64(yaw,pitch)
			var attitude: Basis = Basis(Vector3.UP,yaw)*Basis(Vector3.RIGHT,pitch)
			var points: Array = []
			for offset in offsets:
				points.append(add(camera_ecef,transform64(field_axes,transform64(attitude64,offset))))
			var source_state: Array = [camera_ecef,points,field_axes,anchor,render_axes]
			var before_bytes: PackedByteArray = var_to_bytes(source_state)
			var old_camera: Vector3 = Frame.local_position(camera_ecef,anchor,render_axes)
			max_pre_rebase_radius_m=max(max_pre_rebase_radius_m,length64(difference(camera_ecef,anchor)))
			var old_basis: Basis = Frame.object_basis(field_axes,render_axes)*attitude
			camera.transform=Transform3D(old_basis,old_camera)
			var before_pixels: Array[Vector2] = []
			for i in offsets.size():
				var pixel: Vector2 = camera.unproject_position(Frame.local_position(points[i],anchor,render_axes))
				before_pixels.append(pixel)
				var error_px: float = pixel.distance_to(reference_pixel(offsets[i]))
				max_reference_pixels=max(max_reference_pixels,error_px)
				expect(error_px<=PIXEL_BUDGET,"binary64→actual Camera projection before rebase")
			var new_anchor: Array = camera_ecef.duplicate(true)
			var new_axes: Array = Frame.axes_at(new_anchor)
			camera.transform=Transform3D(Frame.object_basis(field_axes,new_axes)*attitude,Frame.local_position(camera_ecef,new_anchor,new_axes))
			expect(camera.position.length()==0.0,"candidate camera recentered before presentation")
			for i in offsets.size():
				var pixel: Vector2 = camera.unproject_position(Frame.local_position(points[i],new_anchor,new_axes))
				var transaction_error: float = pixel.distance_to(before_pixels[i])
				var reference_error: float = pixel.distance_to(reference_pixel(offsets[i]))
				max_transaction_pixels=max(max_transaction_pixels,transaction_error)
				max_reference_pixels=max(max_reference_pixels,reference_error)
				expect(transaction_error<=PIXEL_BUDGET,"atomic rebase half-pixel continuity")
				expect(reference_error<=PIXEL_BUDGET,"binary64→actual Camera projection after rebase")
			# Deliberate partial transaction: old camera transform with newly rebased
			# point. Detection is asserted, not a disabled comparison/export claim.
			if leg==0 and segment==0:
				camera.transform=Transform3D(old_basis,old_camera)
				var bad: Vector2 = camera.unproject_position(Frame.local_position(points[1],new_anchor,new_axes))
				negative_mixed_pixels=bad.distance_to(reference_pixel(offsets[1]))
				expect(negative_mixed_pixels>PIXEL_BUDGET,"mixed-origin transaction detected")
			expect(before_bytes==var_to_bytes(source_state),"canonical arrays remain byte-identical")
			canonical_checks += 1
			transactions += 1
			anchor=new_anchor
			render_axes=new_axes
	var result: Dictionary = {"schema_version":1,"scope":"Private CPU geometry/Camera projection proof; no GPU, physics, world-runtime or disabled-export assertion","checks":checks,"failures":failures,"leg_count":20,"leg_length_m":50000,"transactions":transactions,"east_progression_per_transaction_m":REBASE_M,"max_pre_rebase_radius_m":max_pre_rebase_radius_m,"pre_rebase_point_presented":false,"canonical_byte_checks":canonical_checks,"seam_projection_cases":fixture.seams.size(),"viewport_px":[WIDTH,HEIGHT],"vertical_fov_deg":FOV_DEG,"pixel_budget":PIXEL_BUDGET,"max_reference_error_px":max_reference_pixels,"max_transaction_error_px":max_transaction_pixels,"max_seam_roundtrip_m":max_roundtrip_m,"negative_mixed_transform_error_px":negative_mixed_pixels,"exact_pole_policy":"atan2(y,x) longitude; exact-pole yaw is ambiguous and unsupported as unique orientation"}
	var output: FileAccess = FileAccess.open("res://result.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"\t")+"\n")
	output.close()
	viewport.queue_free()
	print("RENDER_GEODESY_RESULT ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
