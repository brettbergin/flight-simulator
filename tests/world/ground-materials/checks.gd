extends RefCounted
# Original MIT. Actual ground builder plus immutable masks and filtering budgets.
# Headless checks do not certify shader compilation, pixels or temporal stability.
const World = preload("res://interactive/flight_world.gd")
const ACCEPTED_MASKS: Dictionary={"coverage_and_marks_helpers":"3f788f3ca35b162e8df863d93f46601788d5a97d2c2f5cd5c5013ff0c3470828","countryside_water_paving_masks":"e0e2856efd58ea57ddb2ccdc393b9920b7542999dcbc714c7d37e8b5b84af8ee","paint_and_outputs":"969a8a452dd66100bb25024523bb8bac2eab07173a3f22c12a7c707f973983a6"}
var checks: int=0
var failures: Array[String]=[]
static func run() -> Dictionary:
 return new()._run()
func _check(ok: bool,label: String) -> void:
 checks+=1
 if not ok: failures.append(label)
func _region(source: String,first: String,last: String) -> String:
 var begin: int=source.find(first)
 var end: int=source.find(last,begin)
 _check(begin>=0 and end>begin,"protected_region_present_"+first)
 return source.substr(begin,end-begin) if begin>=0 and end>begin else ""
func _visibility(cell: float,footprint: float) -> float:
 return 1.0-smoothstep(cell*0.125,cell*0.5,footprint)
func _run() -> Dictionary:
 var host:=Node3D.new()
 var node: MeshInstance3D=World.new().ground(host)
 _check(host.get_child_count()==1 and host.get_child(0)==node,"one_actual_ground_owner")
 _check(node.name=="PrototypeGroundSurface" and node.mesh is PlaneMesh,"actual_named_plane")
 _check(node.mesh.size==Vector2(80000,80000) and node.position==Vector3.ZERO,"unchanged_plane_extent_height")
 _check(node.mesh.get_surface_count()==1,"one_mesh_surface")
 var arrays: Array=node.mesh.surface_get_arrays(0)
 _check(arrays[Mesh.ARRAY_VERTEX].size()==4 and arrays[Mesh.ARRAY_INDEX].size()==6,"only_two_ground_triangles")
 _check(node.material_override is ShaderMaterial and node.material_override.shader.code==World.GROUND_SHADER,"actual_builder_uses_shader")
 _check(node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"unchanged_shadow_policy")
 var local_vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX].duplicate()
 for shift in [Vector3(8500,0,-12000),Vector3(-20000,0,20000),Vector3.ZERO]:
  host.position=shift
  _check(node.position==Vector3.ZERO and node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==local_vertices,"rebase_preserves_local_vertices_"+str(shift))
 var code: String=World.GROUND_SHADER.replace("\r\n","\n")
 _check(code.contains("anchor_xz = VERTEX.xz") and code.contains("vec2 p = anchor_xz;"),"local_anchor_sampling")
 for forbidden in ["TIME","CAMERA_POSITION_WORLD","MODEL_MATRIX","ALPHA","discard;","NORMAL =","VERTEX +=","texture("]:
  _check(not code.contains(forbidden),"no_camera_animation_depth_texture_"+forbidden)
 _check(code.contains("render_mode diffuse_burley, specular_disabled;"),"opaque_unchanged_lighting_mode")
 var metadata: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/aircraft/prototype/ground-presentation.json"))
 _check(metadata is Dictionary,"original_provenance_present")
 if metadata is Dictionary:
  _check(metadata.id=="original-ground-material-presentation" and metadata.license=="MIT","original_provenance_identity")
  var pinned: Dictionary=ACCEPTED_MASKS
  _check(metadata.unchanged.protected_shader_lf_sha256==ACCEPTED_MASKS,"accepted_baseline_mask_pins")
  _check(_region(code,"float rect_coverage(","// Conservative diagonal pixel footprint").sha256_text()==pinned.coverage_and_marks_helpers,"accepted_coverage_and_digits_unchanged")
  _check(_region(code,"    // Finite synthetic countryside:","    // Material-only asphalt").sha256_text()==pinned.countryside_water_paving_masks,"accepted_country_road_water_paving_masks_unchanged")
  _check(code.substr(code.find("    color = mix(color, asphalt, paving);")).sha256_text()==pinned.paint_and_outputs,"accepted_paint_dimensions_composition_unchanged")
  _check(code.contains("length(aa * 2.0)") and code.contains("cell_m * 0.125, cell_m * 0.5"),"conservative_derivative_fade")
  _check(metadata.material_terms.size()==5 and metadata.filter.noise_samples_per_fragment==8,"bounded_material_sample_budget")
  for term in metadata.material_terms:
   var cell: float=term.cell_m
   _check(cell>0 and term.footprint_multiplier>=maxf(term.coordinate_scale[0],term.coordinate_scale[1]),"anisotropic_footprint_bound_"+term.id)
   _check(code.contains(", "+str(cell)+", material_pixel_m"),"real_shader_band_declared_"+term.id)
   _check(_visibility(cell,0.0)==1.0 and _visibility(cell,cell*0.5)==0.0 and _visibility(cell,cell*100.0)==0.0,"resolved_and_subpixel_limits_"+term.id)
   var previous: float=1.0
   for index in range(65):
    var weight: float=_visibility(cell,cell*float(index)/64.0)
    _check(is_finite(weight) and weight>=0 and weight<=previous,"bounded_monotone_filter_"+term.id+"_"+str(index))
    previous=weight
 _check(code.count("material_noise(p")==5,"exact_five_new_material_samples")
 host.free()
 return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"scope":"Actual single-plane builder, immutable accepted masks, local anchors and conservative finite material filtering; GPU appearance/cost separate."}
