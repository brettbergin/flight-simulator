extends RefCounted
# Original MIT synthetic presentation checks. No solver or input mutation.
const Pose = preload("res://interactive/flight_render_pose.gd")
const HZ: int = 120
const DENOMINATOR: int = 1000000
const VELOCITY := Vector3(40.0,-1.5,-8.0)
const CAMERA_OFFSET := Vector3(0.0,2.0,10.0)

func _position(tick: int) -> Vector3:
	return VELOCITY * (float(tick)/HZ)

func _basis(tick: int) -> Basis:
	return Basis(Vector3.UP,0.2*float(tick)/HZ)

func _cadence(hz: int) -> Array[int]:
	var result: Array[int] = []
	for index in range(hz):
		var first: int=index*1000000/hz
		var last: int=(index+1)*1000000/hz
		result.append(last-first)
	return result

func _profile(host: Node, name: String, cadence: Array[int]) -> Dictionary:
	var buffer=Pose.new()
	buffer.reset("linear-fixture",0,_position(0),_basis(0))
	var wall: int=0
	var tick: int=0
	var debt: int=0
	var frames: int=0
	var position_error: float=0.0
	var camera_error: float=0.0
	var orientation_error: float=0.0
	var admissions: bool=true
	while wall<1000000:
		var elapsed: int=mini(cadence[frames%cadence.size()],1000000-wall)
		wall+=elapsed
		debt+=elapsed*HZ
		var count: int=debt/DENOMINATOR
		if count>1:
			admissions=buffer.push("linear-fixture",tick+count-1,_position(tick+count-1),_basis(tick+count-1)) and admissions
		if count>0:
			tick+=count
			admissions=buffer.push("linear-fixture",tick,_position(tick),_basis(tick)) and admissions
			debt-=count*DENOMINATOR
		var pose: Transform3D=buffer.sample(float(debt)/DENOMINATOR)
		var expected_time: float=maxf(0.0,float(wall)/1000000.0-1.0/HZ)
		var expected := Transform3D(Basis(Vector3.UP,0.2*expected_time),VELOCITY*expected_time)
		position_error=maxf(position_error,pose.origin.distance_to(expected.origin))
		camera_error=maxf(camera_error,(pose*CAMERA_OFFSET).distance_to(expected*CAMERA_OFFSET))
		orientation_error=maxf(orientation_error,maxf(pose.basis.x.distance_to(expected.basis.x),maxf(pose.basis.y.distance_to(expected.basis.y),pose.basis.z.distance_to(expected.basis.z))))
		frames+=1
	host.check(admissions and tick==120 and debt==0,"render_pose_"+name+"_actual_adjacent_tick_pairing")
	host.check(position_error<0.0001 and camera_error<0.0001 and orientation_error<0.00001,"render_pose_"+name+"_linear_motion_and_camera_same_phase")
	host.check(buffer.sample(0.0,false).is_equal_approx(Transform3D(_basis(120),_position(120))),"render_pose_"+name+"_latest_endpoint_unchanged")
	return {"frames":frames,"tick":tick,"position_error_m":position_error,"camera_error_m":camera_error,"basis_axis_error":orientation_error}

func run(host: Node) -> void:
	var buffer=Pose.new()
	host.check(not buffer.has_pose() and buffer.sample(0.5)==Transform3D.IDENTITY,"render_pose_empty_has_no_stale_transform")
	buffer.reset("first",10,Vector3(1,2,3),Basis.IDENTITY)
	host.check(buffer.has_pose() and buffer.sample(0.25).origin==Vector3(1,2,3),"render_pose_reset_collapses_history")
	var end:=Vector3(3,4,5)
	host.check(buffer.push("first",11,end,Basis(Vector3.UP,PI/2)),"render_pose_consecutive_push_accepted")
	host.check(buffer.sample(0).origin==Vector3(1,2,3) and buffer.sample(1).origin==end and buffer.sample(-4).origin==Vector3(1,2,3) and buffer.sample(4).origin==end,"render_pose_endpoints_and_no_extrapolation")
	host.check(buffer.sample(0.5).origin==Vector3(2,3,4) and absf(buffer.sample(0.5).basis.get_euler().y-PI/4)<0.00001,"render_pose_position_lerp_and_rigid_rotation")
	buffer.reset("wrap",0,Vector3.ZERO,Basis(Vector3.UP,deg_to_rad(179)))
	buffer.push("wrap",1,Vector3.ZERO,Basis(Vector3.UP,deg_to_rad(-179)))
	host.check((buffer.sample(0.5).basis*Vector3.FORWARD).distance_to(Vector3.BACK)<0.00001,"render_pose_heading_wrap_uses_shortest_arc")
	buffer.push("wrap",4,Vector3(40,0,0),Basis.IDENTITY)
	host.check(buffer.sample(0.5).origin==Vector3(40,0,0),"render_pose_gap_cannot_blend_old_endpoint")
	buffer.push("next",0,Vector3(100,0,0),Basis.IDENTITY)
	host.check(buffer.sample(0.5).origin==Vector3(100,0,0),"render_pose_new_session_cannot_blend_old_endpoint")
	buffer.push("next",0,Vector3(200,0,0),Basis.IDENTITY)
	host.check(buffer.sample(0.5).origin==Vector3(200,0,0),"render_pose_duplicate_tick_collapses_history")
	host.check(not buffer.push("next",1,Vector3(NAN,0,0),Basis.IDENTITY) and not buffer.has_pose(),"render_pose_nonfinite_position_rejects_and_clears")
	buffer.reset("finite",0,Vector3.ZERO,Basis.IDENTITY)
	host.check(not buffer.push("finite",1,Vector3.ZERO,Basis(Vector3.INF,Vector3.UP,Vector3.BACK)) and not buffer.has_pose(),"render_pose_nonfinite_basis_rejects_and_clears")
	buffer.reset("finite",0,Vector3.ZERO,Basis.IDENTITY)
	host.check(not buffer.push("finite",1,Vector3.ZERO,Basis.IDENTITY.scaled(Vector3(2,1,1))) and not buffer.has_pose(),"render_pose_scale_not_silently_rotation")
	buffer.reset("finite",0,Vector3.ZERO,Basis.IDENTITY)
	buffer.sample(INF)
	host.check(not buffer.has_pose(),"render_pose_nonfinite_alpha_has_no_extrapolation")
	buffer.reset("fault",0,Vector3(9,8,7),Basis.IDENTITY)
	buffer.push("fault",1,Vector3(10,8,7),Basis.IDENTITY)
	buffer.clear()
	host.check(not buffer.has_pose() and buffer.sample(0.5)==Transform3D.IDENTITY,"render_pose_explicit_fault_clear_discards_history")
	var input_position:=Vector3(4,5,6)
	var input_basis:=Basis.IDENTITY
	buffer.reset("owned",0,input_position,input_basis)
	input_position.x=100
	input_basis.x=Vector3(2,0,0)
	var copied: Transform3D=buffer.sample(0.5)
	copied.origin.x=900
	host.check(buffer.sample(0.5).origin==Vector3(4,5,6) and buffer.sample(0.5).basis==Basis.IDENTITY,"render_pose_input_and_output_are_value_owned")
	var profiles: Dictionary={}
	for hz in [30,60,144,240]:
		profiles[str(hz)]=_profile(host,str(hz)+"Hz",_cadence(hz))
	profiles["irregular"]=_profile(host,"irregular",[1000,5000,17000,33000,50000,0])
	host.evidence["render_pose_synthetic"]=profiles
	host.evidence["render_pose_scope"]="Private render-only local-frame lerp/slerp; fixed one-tick presentation delay, no solver/input/state mutation or extrapolation. Host validates actual native pairs separately."
