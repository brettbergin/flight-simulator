extends RefCounted
# Original MIT. Actual ground builder plus immutable masks and filtering budgets.
# Headless checks do not certify shader compilation, pixels or temporal stability.
const World = preload("res://interactive/flight_world.gd")
const TaxiLayout = preload("res://world/taxi/taxi_layout.gd")

# ADR027 permits exactly these two paint-source substitutions. Reversing ONLY
# these reviewed blocks must recover the original protected paint hash below.
# This preserves the historical four-continuous-bars proof, while the separate
# source/actual-parameter checks require the accepted east-solid/west-dashed fix.
const TAXI_HOLD_SOURCE := """        for (int i = 0; i < 3; i++) {
            float z = taxi_link_z[i];
            yellow = max(yellow, rect_coverage(p, vec2(53.0, z), vec2(29.0, 0.11), aa));
            for (int j = 0; j < 4; j++) {
                float x = taxi_bar_x + taxi_bar_offsets[j];
                if (j < 2) {
                    // West pair: seven filtered one-metre dashes. East is solid.
                    for (int dash = 0; dash < 7; dash++) {
                        float dz = taxi_dash.z + taxi_dash.x * 0.5 + float(dash) * (taxi_dash.x + taxi_dash.y);
                        yellow = max(yellow, rect_coverage(p, vec2(x, z + dz), vec2(taxi_bar_half.x, taxi_dash.x * 0.5), aa));
                    }
                } else {
                    yellow = max(yellow, rect_coverage(p, vec2(x, z), taxi_bar_half, aa));
                }
            }
        }
"""
const LEGACY_HOLD_SOURCE := """        for (int i = 0; i < 3; i++) {
            float z = i == 0 ? 30.0 : (i == 1 ? -800.0 : -1630.0);
            yellow = max(yellow, rect_coverage(p, vec2(53.0, z), vec2(29.0, 0.11), aa));
            for (int j = 0; j < 4; j++) {
                float dx = j < 2 ? -1.3 + float(j) * 0.6 : 0.7 + float(j - 2) * 0.6;
                yellow = max(yellow, rect_coverage(p, vec2(30.0 + dx, z), vec2(0.10, 7.0), aa));
            }
        }
"""
const TAXI_PARKING_SOURCE := """        for (int i = 0; i < 5; i++) {
            float x = i < 4 ? taxi_parking_x[i] : taxi_parking_x5;
            yellow = max(yellow, rect_coverage(p, vec2(x, taxi_parking_paint.x), vec2(0.10, taxi_parking_paint.y), aa));
            yellow = max(yellow, rect_coverage(p, vec2(x, taxi_parking_paint.z), vec2(taxi_parking_paint.w, 0.10), aa));
        }
"""
const LEGACY_PARKING_SOURCE := """        for (int i = 0; i < 5; i++) {
            float x = 108.0 + float(i) * 19.0;
            yellow = max(yellow, rect_coverage(p, vec2(x, 34.0), vec2(0.10, 18.0), aa));
            yellow = max(yellow, rect_coverage(p, vec2(x, 16.0), vec2(5.0, 0.10), aa));
        }
"""
const TAXI_DECLARATIONS: Array[String] = [
 "uniform vec3 taxi_link_z = vec3(30.0, -800.0, -1630.0);",
 "uniform float taxi_bar_x = 30.0;",
 "uniform vec4 taxi_bar_offsets = vec4(-1.3, -0.7, 0.7, 1.3);",
 "uniform vec2 taxi_bar_half = vec2(0.10, 7.0);",
 "uniform vec3 taxi_dash = vec3(1.0, 1.0, -7.0);",
 "uniform vec4 taxi_parking_x = vec4(108.0, 127.0, 146.0, 165.0);",
 "uniform float taxi_parking_x5 = 184.0;",
 "uniform vec4 taxi_parking_paint = vec4(34.0, 18.0, 16.0, 5.0);"
]
const TAXI_PARAMETERS: Dictionary = {
 "taxi_link_z":Vector3(30.0,-800.0,-1630.0),
 "taxi_bar_x":30.0,
 "taxi_bar_offsets":Vector4(-1.3,-0.7,0.7,1.3),
 "taxi_bar_half":Vector2(0.10,7.0),
 "taxi_dash":Vector3(1.0,1.0,-7.0),
 "taxi_parking_x":Vector4(108.0,127.0,146.0,165.0),
 "taxi_parking_x5":184.0,
 "taxi_parking_paint":Vector4(34.0,18.0,16.0,5.0)
}
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
func _legacy_paint(code: String) -> String:
 if code.count(TAXI_HOLD_SOURCE)!=1 or code.count(TAXI_PARKING_SOURCE)!=1:
  return ""
 return code.replace(TAXI_HOLD_SOURCE,LEGACY_HOLD_SOURCE).replace(TAXI_PARKING_SOURCE,LEGACY_PARKING_SOURCE)
func _taxi_uniform_source(code: String) -> bool:
 if code.count("uniform ")!=TAXI_DECLARATIONS.size():
  return false
 for declaration: String in TAXI_DECLARATIONS:
  if code.count(declaration)!=1:
   return false
 return true
# Material getters expose assigned overrides, not shader-language defaults.
# The compiled-default query is meaningful only with a real rendering backend.
func _taxi_parameter(paint: ShaderMaterial,key: String,compiled_defaults: bool) -> Variant:
 if compiled_defaults:
  return RenderingServer.shader_get_parameter_default(paint.shader.get_rid(),key)
 return paint.get_shader_parameter(key)
func _taxi_default_unset(paint: ShaderMaterial) -> bool:
 for key: String in TAXI_PARAMETERS:
  if paint.get_shader_parameter(key)!=null:
   return false
 return true
func _taxi_parameters_valid(paint: ShaderMaterial,compiled_defaults: bool=false) -> bool:
 for key: String in TAXI_PARAMETERS:
  var actual: Variant=_taxi_parameter(paint,key,compiled_defaults)
  var expected: Variant=TAXI_PARAMETERS[key]
  if typeof(actual)!=typeof(expected) or actual!=expected:
   return false
 return true
func _taxi_geometry(paint: ShaderMaterial,label: String,compiled_defaults: bool=false) -> void:
 var admitted: bool=_taxi_parameters_valid(paint,compiled_defaults)
 _check(admitted,label+"_actual_eight_uniform_values_and_types")
 if not admitted:
  return
 var links: Vector3= _taxi_parameter(paint,"taxi_link_z",compiled_defaults)
 var bar_x: float= _taxi_parameter(paint,"taxi_bar_x",compiled_defaults)
 var offsets: Vector4= _taxi_parameter(paint,"taxi_bar_offsets",compiled_defaults)
 var half: Vector2= _taxi_parameter(paint,"taxi_bar_half",compiled_defaults)
 var dash: Vector3= _taxi_parameter(paint,"taxi_dash",compiled_defaults)
 for i in range(3):
  _check(links[i]==[30.0,-800.0,-1630.0][i],label+"_link_center_"+str(i))
  for j in range(4):
   # Source block fixes j<2 west dashed; all remaining lines are east solid.
   _check(bar_x+offsets[j]==30.0+Vector4(-1.3,-0.7,0.7,1.3)[j] and half==Vector2(0.10,7.0),label+"_hold_position_extent_"+str(i)+"_"+str(j))
  for index in range(7):
   var center: float=dash.z+dash.x*0.5+float(index)*(dash.x+dash.y)
   _check(center==-6.5+float(index)*2.0 and dash.x==1.0 and dash.y==1.0,label+"_one_metre_filtered_dash_"+str(i)+"_"+str(index))
   _check(center-0.5>=-7.0 and center+0.5<=7.0,label+"_dash_inside_old_hold_envelope_"+str(i)+"_"+str(index))
 var parking: Vector4= _taxi_parameter(paint,"taxi_parking_x",compiled_defaults)
 var fifth: float= _taxi_parameter(paint,"taxi_parking_x5",compiled_defaults)
 var stripe: Vector4= _taxi_parameter(paint,"taxi_parking_paint",compiled_defaults)
 for i in range(5):
  var x: float=parking[i] if i<4 else fifth
  _check(x==108.0+float(i)*19.0 and stripe==Vector4(34.0,18.0,16.0,5.0),label+"_original_parking_dimensions_"+str(i))
  _check(stripe.x-stripe.y==16.0 and stripe.x+stripe.y==52.0 and stripe.z==16.0,label+"_stripe_bounds_cap_distinct_from_CG18_"+str(i))
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
 var legacy_code: String=_legacy_paint(code)
 _check(not legacy_code.is_empty(),"only_exact_ADR027_hold_and_parking_substitutions")
 _check(_taxi_uniform_source(code),"closed_eight_ADR027_uniform_declarations_defaults")
 _check(_taxi_default_unset(node.material_override as ShaderMaterial),"default_builder_no_material_parameter_overrides")
 if DisplayServer.get_name()=="headless":
  # Dummy exposes no compiled defaults. The exact declaration/default source
  # and absent overrides above are the headless proof, never GPU execution.
  _check(_taxi_uniform_source(code),"headless_default_source_only_compiled_defaults_unavailable")
 else:
  _taxi_geometry(node.material_override as ShaderMaterial,"default_builder_compiled_defaults",true)
 var checked: Dictionary=TaxiLayout.load()
 _check(checked.ok and checked.value is Dictionary,"source_bound_accepted_taxi_layout")
 var configured_host:=Node3D.new()
 var configured_world:=World.new()
 if checked.ok and checked.value is Dictionary:
  var configured: bool=configured_world.configure_taxi_layout(checked.value)
  _check(configured,"actual_world_accepts_reviewed_layout")
  if configured:
   var configured_node: MeshInstance3D=configured_world.ground(configured_host)
   _taxi_geometry(configured_node.material_override as ShaderMaterial,"configured_builder")
   _check(configured_node.material_override.shader.code==World.GROUND_SHADER,"configured_builder_same_protected_shader")
   var configured_paint: ShaderMaterial=configured_node.material_override
   configured_paint.set_shader_parameter("taxi_parking_x5",185.0)
   _check(not _taxi_parameters_valid(configured_paint),"changed_actual_uniform_geometry_rejects")
   configured_paint.set_shader_parameter("taxi_parking_x5",184.0)
   _check(_taxi_parameters_valid(configured_paint),"test_owned_uniform_restored_exactly")
 configured_host.free()
 _check(_legacy_paint(code.replace("if (j < 2)","if (j < 3)")).is_empty(),"unexpected_hold_style_source_rejects")
 _check(_legacy_paint(code.replace("taxi_parking_paint.y","taxi_parking_paint.z")).is_empty(),"unexpected_parking_source_rejects")
 _check(not _taxi_uniform_source(code.replace("uniform float taxi_bar_x = 30.0;","uniform float taxi_bar_x = 31.0;")),"changed_default_geometry_source_rejects")
 var changed_white: String=_legacy_paint(code.replace("vec2(0.175, 895.0)","vec2(0.2, 895.0)"))
 _check(changed_white.substr(changed_white.find("    color = mix(color, asphalt, paving);")).sha256_text()!=ACCEPTED_MASKS.paint_and_outputs,"unrelated_old_paint_drift_rejects")
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
  _check(legacy_code.substr(legacy_code.find("    color = mix(color, asphalt, paving);")).sha256_text()==pinned.paint_and_outputs,"accepted_paint_dimensions_composition_unchanged")
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
 return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"scope":"Actual single-plane builder, immutable accepted masks, source defaults/no overrides and configured material geometry. Compiled default values/geometry required on real renderer, unavailable under headless. Local anchors and finite filtering; GPU appearance/cost separate."}
