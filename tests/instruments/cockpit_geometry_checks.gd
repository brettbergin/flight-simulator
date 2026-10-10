extends RefCounted
# Original MIT. Inspect actual procedural builder output, not a parallel mesh fixture.
const Cockpit = preload("res://interactive/flight_cockpit.gd")
const CENTERS: Array[Vector3] = [
 Vector3(-0.41540283203125,0.375221826171875,-1.534),
 Vector3(-0.17476318359375,0.375221826171875,-1.534),
 Vector3(0.06587646484375,0.375221826171875,-1.534),
 Vector3(-0.41540283203125,0.136759912109375,-1.534),
 Vector3(-0.17476318359375,0.136759912109375,-1.534),
 Vector3(0.06587646484375,0.136759912109375,-1.534)]
var checks: int = 0
var failures: Array = []
var _host: Node
func _check(ok: bool,label: String) -> void:
 checks+=1
 if not ok: failures.append(label)
 _host.check(ok,label)
func _meshes(node: Node,result: Array[MeshInstance3D]) -> void:
 if node is MeshInstance3D: result.append(node)
 for child in node.get_children(): _meshes(child,result)
func _view_only(node: Node) -> bool:
 if not node is Node3D or node is CollisionObject3D: return false
 for child in node.get_children():
  if not _view_only(child): return false
 return true
func run(host: Node) -> Dictionary:
 _host=host
 var parent := Node3D.new()
 host.add_child(parent)
 var builder = Cockpit.new()
 var result: Dictionary = builder.build(parent,null)
 var root: Node3D = result.root
 _check(result.eye==Vector3(-0.27,0.67,-0.92) and result.panel_focus==Vector3(-0.08,0.255,-1.535),"geometry_frozen_eye_focus")
 _check(_view_only(root),"geometry_only_spatial_mesh_nodes_no_input_colliders")
 var panel: MeshInstance3D = root.get_node("LiveReadonlyPanelSurface")
 _check(panel.position==Vector3(0,0.255,-1.535) and panel.mesh is QuadMesh and panel.mesh.size==Vector2(1.115,0.5575),"geometry_frozen_live_surface")
 _check(panel.material_override.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED and panel.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"geometry_live_texture_unlit_no_shadow")
 var all: Array[MeshInstance3D] = []
 _meshes(root,all)
 _check(all.size()==81,"geometry_exact_75_original_plus_six_mesh_instances")
 var materials: Dictionary = {}
 var rings: Array[MeshInstance3D] = []
 var layer_found: Dictionary = {}
 for node in all:
  materials[node.material_override.get_instance_id()]=true
  if str(node.name).begins_with("OriginalDialBezel"): rings.append(node)
  if node.position.is_equal_approx(Vector3(0,0.55,-1.755)):
   _check(node.material_override.roughness>=0.85 and node.material_override.metallic==0.0,"geometry_matte_glare_shield")
  if node.mesh is BoxMesh:
   for z in [-1.552,-1.569,-1.605]:
    if absf(node.position.z-z)<0.000001:
     layer_found[z]=node.position.z+node.mesh.size.z*0.5
 _check(materials.size()==9 and rings.size()==6,"geometry_closed_material_and_bezel_counts")
 _check(layer_found.size()==3,"geometry_three_original_backing_layers_present")
 if layer_found.size()==3:
  _check(layer_found[-1.605]<layer_found[-1.569] and layer_found[-1.569]<layer_found[-1.552] and layer_found[-1.552]<-1.535,"geometry_backing_order_behind_live_surface")
 var first_mesh: Mesh = rings[0].mesh if rings.size()==6 else null
 var first_material: Material = rings[0].material_override if rings.size()==6 else null
 for index in range(6):
  var ring: MeshInstance3D = root.get_node_or_null("OriginalDialBezel"+str(index))
  _check(ring!=null,"geometry_ring_present_"+str(index))
  if ring==null: continue
  _check(ring.position.distance_to(CENTERS[index])<0.0000001 and ring.transform.basis==Basis.IDENTITY,"geometry_ring_aligned_"+str(index))
  _check(ring.mesh==first_mesh and ring.material_override==first_material,"geometry_ring_shared_resources_"+str(index))
  _check(ring.material_override.roughness>=0.85 and ring.material_override.metallic<=0.12 and ring.material_override.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED and ring.material_override.cull_mode==BaseMaterial3D.CULL_BACK,"geometry_opaque_matte_culled_"+str(index))
  _check(ring.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"geometry_no_panel_shadow_"+str(index))
  if not ring.mesh is ArrayMesh or ring.mesh.get_surface_count()!=1:
   _check(false,"geometry_one_triangle_surface_"+str(index));continue
  _check(ring.mesh.surface_get_primitive_type(0)==Mesh.PRIMITIVE_TRIANGLES,"geometry_triangle_primitive_"+str(index))
  var arrays: Array = ring.mesh.surface_get_arrays(0)
  var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
  var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
  _check(vertices.size()==1152 and normals.size()==1152 and arrays[Mesh.ARRAY_INDEX]==null,"geometry_48_segments_384_triangles_"+str(index))
  if vertices.size()!=1152 or normals.size()!=1152: continue
  var finite: bool = true
  var winding: bool = true
  var opening: bool = true
  var normal_faces: bool = true
  var depth: bool = true
  var min_radius: float = INF
  var max_radius: float = 0.0
  for i in range(vertices.size()):
   var v: Vector3 = vertices[i]
   finite=finite and v.is_finite() and normals[i].is_finite()
   var radius: float = Vector2(v.x,v.y).length()
   min_radius=minf(min_radius,radius);max_radius=maxf(max_radius,radius)
   depth=depth and (absf(v.z)<0.0000001 or absf(v.z-0.004)<0.0000001)
   normal_faces=normal_faces and absf(normals[i].length()-1.0)<0.00001
  for i in range(0,vertices.size(),3):
   var a: Vector3 = vertices[i]
   var b: Vector3 = vertices[i+1]
   var c: Vector3 = vertices[i+2]
   var cross: Vector3 = (b-a).cross(c-a)
   var average: Vector3 = (normals[i]+normals[i+1]+normals[i+2]).normalized()
   winding=winding and cross.length()>0.00000001 and cross.normalized().dot(average)<-0.99
   # Every triangle's projected edges stay outside the dial/needle footprint.
   for edge in [[a,b],[b,c],[c,a]]:
    var start := Vector2(edge[0].x,edge[0].y)
    var finish := Vector2(edge[1].x,edge[1].y)
    var delta: Vector2 = finish-start
    var t: float = clampf(-start.dot(delta)/delta.length_squared(),0.0,1.0) if delta.length_squared()>0.0 else 0.0
    opening=opening and (start+delta*t).length()>(91.59+3.0)*1.115/1024.0
   var side: int = int(i/6)%4
   if side==0: normal_faces=normal_faces and average.dot(Vector3.BACK)>0.9999
   elif side==1: normal_faces=normal_faces and average.dot(Vector3.FORWARD)>0.9999
   else:
    var radial := Vector3(a.x+b.x+c.x,a.y+b.y+c.y,0).normalized()
    normal_faces=normal_faces and average.dot(radial)*(1.0 if side==2 else -1.0)>0.99
  _check(finite and depth and absf(min_radius-0.104084814453125)<0.0000001 and absf(max_radius-0.109529150390625)<0.0000001,"geometry_finite_four_mm_radial_bounds_"+str(index))
  _check(winding and normal_faces,"geometry_nondegenerate_clockwise_outward_normals_"+str(index))
  _check(opening,"geometry_all_triangle_edges_clear_dial_"+str(index))
  _check(ring.position.z>-1.535 and ring.position.z+0.004<-0.92,"geometry_trim_in_front_not_coplanar_"+str(index))
 var held: Dictionary = {"roll":0.5,"pitch":-0.25,"yaw":0.2,"throttle":0.8,"left_brake":0.3,"right_brake":0.6,"trim":-0.4}
 var before: Dictionary = held.duplicate(true)
 builder.update_controls(held)
 _check(held==before,"geometry_copied_controls_input_unmodified")
 _check(builder.yoke.name=="CopiedPilotYoke" and builder.yoke.position.is_equal_approx(Vector3(-0.27,0.075,-1.2825)) and absf(builder.yoke.rotation.z+0.24)<0.000001,"geometry_original_yoke_home_animation")
 _check(builder.throttle_handle.name=="CopiedThrottleHandle" and builder.throttle_handle.position.is_equal_approx(Vector3(0.22,-0.07,-1.441)),"geometry_original_throttle_home_animation")
 _check(builder.pedals.size()==2 and builder.pedals[0].name=="CopiedLeftPedal" and builder.pedals[1].name=="CopiedRightPedal" and absf(builder.pedals[0].rotation.x+0.084)<0.000001 and absf(builder.pedals[1].position.z+1.499)<0.000001,"geometry_original_pedal_animation")
 _check(builder.trim_wheel.name=="CopiedTrimWheel" and absf(builder.trim_wheel.rotation.x+0.4*PI)<0.000001,"geometry_original_trim_animation")
 parent.free()
 return {"passed":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Actual original procedural geometry and copied control output. No native run, input commands, manufacturer sight-picture, pixels or phase acceptance."}
