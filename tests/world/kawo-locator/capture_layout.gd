extends SceneTree
# Private isolated UI observation. Synthetic map states are NOT native flights.
const Map=preload("res://interactive/flight_map.gd")
var failures: Array=[]
var checks: int=0
var observations: Array=[]
var images: Array=[]
var output: String=""
var map
var canvas: Control

func check(ok: bool,name: String) -> void:
	checks+=1
	if not ok: failures.append(name)

func tag(value: float) -> Dictionary:
	var bytes:=PackedByteArray(); bytes.resize(8); bytes.encode_double(0,value)
	return {"$binary64_le":bytes.hex_encode()}

func end(label: String,x: float,z: float) -> Dictionary:
	return {"designator":label,"eus_m":[tag(x),tag(0.0),tag(z)]}

func geometry() -> Dictionary:
	return {"schema":"CompiledAirportGeometry/v1","runways":[
		{"ends":[end("11",-1000.0,500.0),end("29",1000.0,500.0)],"footprint_mm":[[-1000000,480000],[1000000,480000],[1000000,520000],[-1000000,520000]]},
		{"ends":[end("16",0.0,-2000.0),end("34",0.0,0.0)],"footprint_mm":[[-20000,-2000000],[20000,-2000000],[20000,0],[-20000,0]]}]}

func _initialize() -> void: call_deferred("run")

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var original: Image=root.get_texture().get_image()
	var path: String=output.path_join(name+".png")
	check(not FileAccess.file_exists(path) and original!=null and original.save_png(path)==OK,"fresh_image_"+name)
	if FileAccess.file_exists(path): images.append({"file":name+".png","sha256":FileAccess.get_sha256(path),"bytes":FileAccess.get_file_as_bytes(path).size()})

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1 or not args[0].is_absolute_path() or DirAccess.dir_exists_absolute(args[0]) or FileAccess.file_exists(args[0]): quit(1); return
	output=args[0]
	if DirAccess.make_dir_recursive_absolute(output)!=OK: quit(1); return
	root.size=Vector2i(800,520)
	canvas=Control.new(); root.add_child(canvas)
	var caption:=Label.new(); caption.text="ISOLATED MAP LAYOUT FIXTURES / NOT A FLIGHT"; caption.position=Vector2(16,8); canvas.add_child(caption)
	map=Map.new(); map.position=Vector2(20,48); canvas.add_child(map)
	check(map.set_compiled_airport(geometry()),"synthetic_ui_geometry_admitted")
	# Independently hand-derived cardinal endpoint and relative-position controls.
	# Four selected ends, both signs, exact endpoint, and retained/unavailable UI.
	var cases: Array=[
		{"end":34,"before":Vector3(-25,0,500),"after":Vector3(25,0,-500),"at":Vector3(0,0,0),"before_bearing":"003°","after_bearing":"183°"},
		{"end":16,"before":Vector3(25,0,-2500),"after":Vector3(-25,0,-1500),"at":Vector3(0,0,-2000),"before_bearing":"183°","after_bearing":"003°"},
		{"end":11,"before":Vector3(-1500,0,475),"after":Vector3(-500,0,525),"at":Vector3(-1000,0,500),"before_bearing":"093°","after_bearing":"273°"},
		{"end":29,"before":Vector3(1500,0,525),"after":Vector3(500,0,475),"at":Vector3(1000,0,500),"before_bearing":"273°","after_bearing":"093°"}]
	for dimensions in [Vector2(250,220),Vector2(320,220),Vector2(430,320)]:
		map.size=dimensions; map.compact_aid_layout=true
		for row in cases:
			map.select_runway(row.end)
			for phase in ["before","after","at","retained","unavailable"]:
				var state: Dictionary={"session_id":"isolated-ui-fixture","tick":"0","validity":"valid"} if phase!="unavailable" else {}
				var position: Vector3=row.before if phase in ["before","retained","unavailable"] else row.after if phase=="after" else row.at
				map.set_state(state,position,Basis.IDENTITY,{"paused":true,"historical":phase=="retained"})
				await process_frame
				var view: Dictionary=map.get("_presentation").duplicate(true)
				var shown: Dictionary={}
				for widget in view.rows:
					check(map._row_fits(widget),"row_fits_"+str(dimensions)+"_"+str(row.end)+"_"+phase+"_"+widget.id)
					shown[widget.id]=widget.text
				check(shown.has("runway") and shown.has("along") and shown.has("footer") and shown.has("bindings"),"all_reference_and_caveat_rows_present")
				if phase in ["before","after"]:
					check(shown.runway=="RWY %02d · 0.50 km · anchor %s"%[row.end,row[phase+"_bearing"]],"hand_derived_range_bearing")
					check(shown.along==("BEFORE 500m · LEFT 25m" if phase=="before" else "PAST 500m · RIGHT 25m"),"hand_derived_along_cross_labels")
				elif phase=="at":
					check(shown.runway=="RWY %02d · 0.00 km · anchor —"%row.end,"coincident_bearing_suppressed")
				elif phase=="retained":
					check(not view.current and shown.status.contains("RETAINED") and shown.runway.contains("no current reference") and shown.along=="RETAINED / NO CURRENT GUIDANCE","retained_never_claims_current_paused_reference")
				else:
					check(not view.current and shown.status.contains("UNAVAILABLE") and shown.runway.contains("no current reference") and shown.along=="CURRENT REFERENCE UNAVAILABLE","invalid_state_never_claims_current_reference")
				observations.append({"size":[dimensions.x,dimensions.y],"selected_end":row.end,"phase":phase,"rows":shown,"current":view.current,"chart":str(view.chart)})
				if dimensions==Vector2(250,220) and phase=="before": await capture("minimum-end-%02d"%row.end)
				if row.end==34 and dimensions==Vector2(250,220) and phase in ["retained","unavailable"]: await capture("minimum-"+phase)
				if row.end==34 and dimensions==Vector2(430,320) and phase=="after": await capture("large-after-right")
	map.compact_aid_layout=false; map.size=Vector2(430,320); map.select_runway(34)
	map.set_state({"session_id":"isolated-ui-fixture","tick":"0","validity":"valid"},Vector3(-25,0,500),Basis.IDENTITY,{"paused":true})
	await capture("ordinary-map")
	var receipt: Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"map_source_sha256":FileAccess.get_sha256("res://interactive/flight_map.gd"),"scope":"Synthetic UI map positions and exact hand-derived display controls; actual font/layout/GPU images only, no native flight/operational/pilot claim","observations":observations,"images":images}
	var file:=FileAccess.open(output.path_join("receipt.json"),FileAccess.WRITE); file.store_string(JSON.stringify(receipt,"  ")); file.close()
	canvas.free(); await process_frame
	print("KAWO_LOCATOR_LAYOUT_RESULT="+JSON.stringify({"passed":receipt.passed,"checks":checks,"failures":failures,"images":images.size()}))
	quit(0 if failures.is_empty() else 1)
