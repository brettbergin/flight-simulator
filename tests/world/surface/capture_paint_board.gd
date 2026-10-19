extends SceneTree
# Private original-pigment observation board. No native/flight/profile resource
# or CPU paint classifier. Process success means images were retained only.
const World = preload("res://world/terrain/kawo_world.gd")
const CONTROLS = "res://paint_controls_v1.json"
const CONTROLS_SHA = "150f64031548bbbe38930c842315dacb89513dd857184ae79e8cad6467c78a18"
const WORLD_SHA = "cc1f884582264e265e7a943b0b6b6ebd7ed626340cc0344e291f716def48bc84"
const BOARD_SIZE = Vector2i(1280,800)
const TILE_SIZE = Vector2i(160,160)
const SOURCES = ["res://paint_board.gd",CONTROLS,"res://world/terrain/kawo_world.gd","res://world/terrain/resident_grid_reader.gd","res://simulation/canonical_frames.gd","res://simulation/uint64.gd"]
const GROUPS = [
	["first-dash-gap-next-dash",3], ["center-strip-width-interiors",2],
	["both-center-end-exclusions",2], ["last-dash-clipped-and-no-opposite-end-phase-union",3],
	["both-edge-insets-and-clear-neighbors",4], ["edge-pigment-cannot-escape-physical-footprint-ends",2],
	["rotated-paint-interiors",3], ["higher-vertical-gap-masks-lower-horizontal-edge",1],
	["higher-horizontal-edge-wins",1], ["higher-vertical-edge-wins",1],
	["higher-horizontal-gap-masks-lower-vertical-edge",1],
	["priority-tie-keeps-existing-ascii-id-winner",1],
	["polygon-array-order-does-not-reassign-runway-layout",2]]

var _output: String=""
var _controls: Dictionary={}
var _tiles: Array=[]
var _before: Dictionary={}
var _errors: Array=[]
var _receipt: Dictionary={"schema":"PrivateRunwayPaintGpuObservation/v1","observed":false,"manual_review_required":true,"shader_verdict":"not evaluated","scope":"Actual lit production shader on synthetic flat crops; no native flight, operational paint, glyph or terrain acceptance"}

func _initialize() -> void:
	call_deferred("_run")

func _check(good: bool,message: String) -> bool:
	if not good: _errors.append(message)
	return good

func _sources() -> Dictionary:
	var result: Dictionary={}
	for source in SOURCES:
		var raw: PackedByteArray=FileAccess.get_file_as_bytes(source)
		result[source]={"bytes":raw.size(),"sha256":FileAccess.get_sha256(source)}
	return result

func _fixture_pair(spec: Dictionary) -> Dictionary:
	var polygons: Array=[]
	var frames: Array=[]
	var fixtures: Array=[]
	if spec.fixture=="crossing":
		for name in spec.polygon_order:
			fixtures.append({"geometry":_controls.fixtures.crossing[name],"priority":spec.priorities[name]})
	else:
		fixtures.append({"geometry":_controls.fixtures[spec.fixture],"priority":0})
		# A real second material slot, outside every crop. Not a zero/disabled
		# uniform or test shader branch. All positions remain within8192m.
		fixtures.append({"geometry":{"id":"kawo.runway.16-34","physical_ends_xz_m":[[-4000.0,-4000.0],[-4000.0,-3000.0]],"designators":["16","34"],"width_m":24.0,"footprint_mm":[[-4012000,-4000000],[-4012000,-3000000],[-3988000,-3000000],[-3988000,-4000000]]},"priority":0})
	for item in fixtures:
		var geometry: Dictionary=item.geometry
		var a: Array=geometry.physical_ends_xz_m[0]
		var b: Array=geometry.physical_ends_xz_m[1]
		var frame: Dictionary=World._paint_frame([float(a[0]),0.0,float(a[1])],[float(b[0]),0.0,float(b[1])],float(geometry.width_m),geometry.designators,geometry.id)
		if frame.is_empty(): return {}
		frames.append(frame)
		polygons.append({"id":geometry.id,"vertices_mm":geometry.footprint_mm.duplicate(true),"material_index":1,"priority":item.priority})
	return {"polygons":polygons,"frames":frames}

func _specifications() -> Array:
	var result: Array=[]
	for group in GROUPS:
		var matches: Array=[]
		for item in _controls.cases:
			if item.id==group[0]: matches.append(item)
		if not _check(matches.size()==1,"one frozen control case: "+group[0]): return []
		var control: Dictionary=matches[0]
		var rows: Array=[]
		if control.has("samples"):
			for i in control.samples.size():
				var sample: Dictionary=control.samples[i]
				rows.append({"sample_index":i,"point":sample.xz_m,"expected":sample,"polygon_order":[]})
		elif control.has("polygon_orders"):
			for i in control.polygon_orders.size():
				rows.append({"sample_index":i,"point":control.xz_m,"expected":control.expected_each,"polygon_order":control.polygon_orders[i]})
		else:
			rows.append({"sample_index":0,"point":control.xz_m,"expected":control.expected,"polygon_order":["horizontal","vertical"]})
		if not _check(rows.size()==group[1],"fixed observation count: "+group[0]): return []
		for row in rows:
			row.case_id=control.id
			row.fixture=control.fixture
			row.priorities=control.get("priorities",{})
			result.append(row)
	return result

func _quad(point: Array,material: ShaderMaterial) -> ArrayMesh:
	# One flat original four-vertex fixture per crop, retaining absolute
	# canonical X/Z as production VERTEX inputs. No alternate paint math.
	var x: float=float(point[0])
	var z: float=float(point[1])
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(x-4.0,0,z-4.0),Vector3(x+4.0,0,z-4.0),Vector3(x-4.0,0,z+4.0),Vector3(x+4.0,0,z+4.0)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,2,3,0,3,1])
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,material)
	return mesh

func _vector(value: Variant) -> Variant:
	if typeof(value)==TYPE_VECTOR2: return [value.x,value.y]
	if typeof(value) in [TYPE_VECTOR4,TYPE_VECTOR4I]: return [value.x,value.y,value.z,value.w]
	return value

func _material_observation(material: ShaderMaterial) -> Dictionary:
	var uniforms: Dictionary={"second_wins":material.get_shader_parameter("second_wins")}
	for slot in 2:
		for prefix in ["paint_ends","paint_axes","paint_size","paint_numbers","paint_digits"]:
			var key: String=prefix+str(slot)
			uniforms[key]=_vector(material.get_shader_parameter(key))
	return {"shader_source_sha256":material.shader.code.sha256_text(),"unmodified_production_shader":material.shader.code==World.SHADER_SOURCE,"uniforms":uniforms}

func _tile(spec: Dictionary,index: int) -> bool:
	var pair: Dictionary=_fixture_pair(spec)
	if not _check(not pair.is_empty(),"production frame preparation: "+spec.case_id): return false
	var material: ShaderMaterial=World._material(pair.polygons,[{"id":"original.grass"},{"id":"original.asphalt"}],0,pair.frames)
	if not _check(material!=null and material.shader!=null and material.shader.code==World.SHADER_SOURCE,"unchanged production material: "+spec.case_id): return false
	var holder:=SubViewportContainer.new()
	holder.position=Vector2(10+(index%7)*180,36+floori(float(index)/7.0)*190)
	holder.size=Vector2(TILE_SIZE)
	holder.stretch=false
	root.add_child(holder)
	var viewport:=SubViewport.new()
	viewport.size=TILE_SIZE
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg=false
	viewport.use_hdr_2d=false
	viewport.mesh_lod_threshold=0.0
	viewport.msaa_3d=Viewport.MSAA_DISABLED
	viewport.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa=false
	viewport.scaling_3d_scale=1.0
	holder.add_child(viewport)
	var space:=Node3D.new()
	viewport.add_child(space)
	var environment:=Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color(0.04,0.04,0.04)
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color.WHITE
	environment.ambient_light_energy=0.5
	environment.ambient_light_sky_contribution=0.0
	environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure=1.0
	environment.fog_enabled=false
	environment.volumetric_fog_enabled=false
	environment.ssao_enabled=false
	environment.ssr_enabled=false
	environment.ssil_enabled=false
	environment.adjustment_enabled=false
	var world_environment:=WorldEnvironment.new()
	world_environment.environment=environment
	space.add_child(world_environment)
	var light:=DirectionalLight3D.new()
	light.light_color=Color.WHITE
	light.light_energy=1.0
	light.rotation_degrees=Vector3(-45,-30,0)
	light.shadow_enabled=false
	space.add_child(light)
	var mesh:=MeshInstance3D.new()
	mesh.mesh=_quad(spec.point,material)
	space.add_child(mesh)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	camera.size=4.0
	camera.near=0.1
	camera.far=100.0
	var attributes:=CameraAttributesPractical.new()
	attributes.auto_exposure_enabled=false
	attributes.exposure_multiplier=1.0
	camera.attributes=attributes
	space.add_child(camera)
	var target:=Vector3(float(spec.point[0]),0.0,float(spec.point[1]))
	camera.position=target+Vector3(0,20,0)
	camera.look_at(target,Vector3.FORWARD)
	camera.make_current()
	var caption:=Label.new()
	caption.position=holder.position+Vector2(0,162)
	caption.size=Vector2(178,28)
	caption.add_theme_font_size_override("font_size",10)
	caption.text="%02d EXPECT %s (%s,%s)\n%s"%[index+1,"WHITE" if spec.expected.white else "GAP",str(float(spec.point[0])),str(float(spec.point[1])),spec.case_id.left(29)]
	root.add_child(caption)
	_tiles.append({"viewport":viewport,"camera":camera,"material":material,"environment":environment,"light":light,"spec":spec.duplicate(true),"target":target,"polygons":pair.polygons.duplicate(true),"frames":pair.frames.duplicate(true)})
	return true

func _write_receipt() -> void:
	_receipt.sources_after=_sources()
	_receipt.sources_unchanged=_receipt.sources_after==_before
	if not _receipt.sources_unchanged:
		_errors.append("source changed during observation")
		_receipt.observed=false
	_receipt.errors=_errors.duplicate()
	var path: String=_output.path_join("receipt.json")
	if FileAccess.file_exists(path): quit(1); return
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null: quit(1); return
	file.store_string(JSON.stringify(_receipt,"\t",true,true)+"\n")
	file.close()
	print("RUNWAY_PAINT_BOARD_OBSERVATION="+JSON.stringify({"observed":_receipt.observed,"manual_review_required":true,"shader_verdict":"not evaluated","tiles":_tiles.size(),"errors":_errors}))
	quit(0 if _receipt.observed else 1)

func _run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1: quit(1); return
	_output=args[0]
	if not _output.is_absolute_path() or _output.begins_with("res://") or _output.begins_with("user://") or DirAccess.dir_exists_absolute(_output) or FileAccess.file_exists(_output): quit(1); return
	if DirAccess.make_dir_recursive_absolute(_output)!=OK: quit(1); return
	_before=_sources()
	_receipt.sources_before=_before.duplicate(true)
	_receipt.engine=Engine.get_version_info()
	_receipt.display=DisplayServer.get_name()
	_receipt.renderer=RenderingServer.get_current_rendering_method()
	_receipt.driver=RenderingServer.call("get_current_rendering_driver_name") if RenderingServer.has_method("get_current_rendering_driver_name") else "unavailable"
	_receipt.adapter=RenderingServer.get_video_adapter_name()
	_receipt.argv=OS.get_cmdline_args()
	_receipt.settings={"board_pixels":[1280,800],"tile_pixels":[160,160],"columns":7,"rows":4,"orthographic_vertical_m":4.0,"camera_above_m":20.0,"near_m":0.1,"far_m":100.0,"screen_up":"canonical minus south","quad_side_m":8.0,"ambient_white_energy":0.5,"directional_white_energy":1.0,"directional_euler_deg":[-45,-30,0],"shadows":false,"tone_map":"linear","exposure":1.0,"autoexposure":false,"msaa":"disabled","screen_space_aa":"disabled","taa":false,"render_scale":1.0,"warmup_draw_frames":12,"pixel_policy":"four unaveraged central pixels; no threshold, color conversion or classification"}
	if not _check(_receipt.display!="headless" and _receipt.renderer=="forward_plus" and _receipt.driver=="vulkan","actual Forward+/Vulkan graphical observation required"):
		_write_receipt();return
	var adapter: String=str(_receipt.adapter).to_lower()
	if not _check(not adapter.is_empty(),"named actual GPU adapter"):
		_write_receipt();return
	for word in ["llvmpipe","softpipe","software","warp","microsoft basic render"]:
		if not _check(not adapter.contains(word),"software adapter refused: "+word):
			_write_receipt();return
	for source in SOURCES:
		if not _check(_before[source].bytes>0,"readable source: "+source):
			_write_receipt();return
	if not _check(_before[CONTROLS].bytes==8308 and _before[CONTROLS].sha256==CONTROLS_SHA,"exact pre-output controls"):
		_write_receipt();return
	if not _check(_before["res://world/terrain/kawo_world.gd"].bytes==28151 and _before["res://world/terrain/kawo_world.gd"].sha256==WORLD_SHA,"exact reviewed production shader owner"):
		_write_receipt();return
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(CONTROLS))
	if not _check(typeof(parsed)==TYPE_DICTIONARY,"frozen control document"):
		_write_receipt();return
	_controls=parsed
	var specs: Array=_specifications()
	if not _check(specs.size()==26,"exact26 observation tiles"):
		_write_receipt();return
	Engine.max_fps=60
	DisplayServer.window_set_size(BOARD_SIZE)
	root.size=BOARD_SIZE
	root.use_hdr_2d=false
	var background:=ColorRect.new()
	background.size=Vector2(BOARD_SIZE)
	background.color=Color(0.025,0.025,0.025)
	root.add_child(background)
	var heading:=Label.new()
	heading.position=Vector2(10,5)
	heading.add_theme_font_size_override("font_size",14)
	heading.text="ORIGINAL PIGMENT / SYNTHETIC LIT GPU CROPS — EXPECTED LABELS ONLY — MANUAL REVIEW REQUIRED"
	root.add_child(heading)
	for i in specs.size():
		if not _tile(specs[i],i):
			_write_receipt();return
	for i in 12: await RenderingServer.frame_post_draw
	var observations: Array=[]
	for i in _tiles.size():
		var tile: Dictionary=_tiles[i]
		var image: Image=tile.viewport.get_texture().get_image()
		if not _check(image!=null and image.get_size()==TILE_SIZE,"original tile dimensions: "+str(i)):
			_write_receipt();return
		var name: String="tile-%02d.png"%[i+1]
		var path: String=_output.path_join(name)
		if not _check(not FileAccess.file_exists(path) and image.save_png(path)==OK,"retained original tile: "+name):
			_write_receipt();return
		var pixels: Array=[]
		for coordinate in [Vector2i(79,79),Vector2i(80,79),Vector2i(79,80),Vector2i(80,80)]:
			var color: Color=image.get_pixel(coordinate.x,coordinate.y)
			pixels.append({"pixel":[coordinate.x,coordinate.y],"rgba_readback":[color.r,color.g,color.b,color.a]})
		var projection: Projection=tile.camera.get_camera_projection()
		var projected: Vector2=tile.camera.unproject_position(tile.target)
		observations.append({"tile":i+1,"control":tile.spec,"original_png":{"file":name,"bytes":FileAccess.get_file_as_bytes(path).size(),"sha256":FileAccess.get_sha256(path),"image_format":image.get_format()},"center_pixels":pixels,"projected_sample_pixel":[projected.x,projected.y],"camera":{"position":[tile.camera.position.x,tile.camera.position.y,tile.camera.position.z],"orthographic_size_m":tile.camera.size,"projection":tile.camera.projection,"keep_aspect":tile.camera.keep_aspect,"near_m":tile.camera.near,"far_m":tile.camera.far,"projection_columns":[_vector(projection.x),_vector(projection.y),_vector(projection.z),_vector(projection.w)]},"actual_light":{"ambient_energy":tile.environment.ambient_light_energy,"directional_energy":tile.light.light_energy,"directional_euler_deg":[tile.light.rotation_degrees.x,tile.light.rotation_degrees.y,tile.light.rotation_degrees.z],"shadows":tile.light.shadow_enabled,"exposure":tile.environment.tonemap_exposure},"actual_material":_material_observation(tile.material),"prepared_frames":tile.frames,"polygons":tile.polygons})
	await RenderingServer.frame_post_draw
	var board: Image=root.get_texture().get_image()
	if not _check(board!=null and board.get_size()==BOARD_SIZE,"actual board dimensions"):
		_write_receipt();return
	var board_path: String=_output.path_join("board.png")
	if not _check(not FileAccess.file_exists(board_path) and board.save_png(board_path)==OK,"retained original board"):
		_write_receipt();return
	_receipt.tiles=observations
	_receipt.board={"file":"board.png","bytes":FileAccess.get_file_as_bytes(board_path).size(),"sha256":FileAccess.get_sha256(board_path),"width":board.get_width(),"height":board.get_height()}
	_receipt.observed=true
	_write_receipt()
