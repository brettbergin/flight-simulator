extends RefCounted
# Original MIT. Root-owned visible observer using the actual integrated Scene and
# already-authorized LocalPlayersTest. Ordinary key events exercise GUI routing;
# direct calls below are explicitly fresh-flight fixture setup, not key evidence.
const Options=preload("res://ui/profiles/player_options.gd")
const Facade=preload("res://simulation/session_facade.gd")
var _scene: Node
var _checks: int=0
var _failures: Array[String]=[]
var _captures: Array[Dictionary]=[]

func run(scene: Node, output_absolute_directory: String) -> Dictionary:
	_scene=scene
	if DisplayServer.get_name()=="headless":
		_expect(false,"visible_window_required")
		return _result()
	var controller: RefCounted=scene.player_controller
	var service: RefCounted=null if controller==null else controller.get("_service")
	if service==null or service.get_script()!=null or service.get_class()!="LocalPlayersTest":
		_expect(false,"qualified_isolated_service_required_no_product_fallback")
		return _result()
	if not output_absolute_directory.is_absolute_path() or not DirAccess.dir_exists_absolute(output_absolute_directory):
		_expect(false,"existing_root_owned_capture_directory_required")
		return _result()
	if controller.selected_pair()!=null:
		_expect(false,"guest_fixture_required_no_named_writes")
		return _result()
	var dimensions: Array[Vector2i]=[Vector2i(960,540),Vector2i(1920,1080),Vector2i(2560,1440)]
	for dimensions_index in dimensions.size():
		if not scene._player_ui.is_empty():
			_expect(false,"previous_modal_not_retired_before_next_resolution")
			break
		var size: Vector2i=dimensions[dimensions_index]
		scene.get_window().size=size
		await _settle(5)
		# Actual fresh flight setup. No native state/mapper lifecycle is mocked.
		if scene.facade==null:
			_expect(scene.restart(true,"calm",Facade.LEGACY_PROFILE.id,"ground-ready"),"actual_fresh_setup_"+str(size))
			if scene.facade==null: break
		scene.open_menu("Players UI keyboard check")
		await _settle(4)
		var baseline: Dictionary=_authority()
		await _capture(output_absolute_directory,"flight-menu",size)
		var controls: Control=_button(scene.menu,"Controls (F7)")
		_expect(await _focus_by_tabs(controls),"menu_tab_to_controls_"+str(size))
		await _key(KEY_ENTER)
		_expect(scene.controls_panel.visible,"enter_opens_controls_"+str(size))
		if scene.controls_panel.visible:
			await _capture(output_absolute_directory,"controls-save",size)
			_expect(_inside(scene.controls_panel.get("_player_save_button")),"controls_save_visible_"+str(size))
			await _key(KEY_ESCAPE)
		await _settle(3)
		_expect(await _focus_by_tabs(scene.audio_button),"menu_tab_to_audio_"+str(size))
		await _key(KEY_SPACE)
		_expect(scene.audio_open,"space_opens_audio_"+str(size))
		if scene.audio_open:
			await _capture(output_absolute_directory,"audio-save",size)
			_expect(_inside(scene.audio_panel.get("_player_save_button")),"audio_save_visible_"+str(size))
			await _key(KEY_ESCAPE)
		await _settle(3)
		_expect(await _focus_by_tabs(scene.players_button),"menu_tab_to_players_"+str(size))
		await _key(KEY_ENTER)
		_expect(not scene._player_exit.is_empty(),"keyboard_opens_end_confirmation_"+str(size))
		if scene._player_exit.is_empty(): break
		var dialog: ConfirmationDialog=scene._player_exit.dialog
		_expect(dialog.get_cancel_button().has_focus(),"default_cancel_focus_"+str(size))
		await _capture(output_absolute_directory,"player-end-confirmation",size)
		await _key(KEY_SPACE)
		_expect(scene._player_exit.is_empty(),"space_default_cancel_keeps_flight_"+str(size))
		# Controls opening deliberately retires a real pointer capture before this
		# comparison; native/recording/camera/options must remain untouched.
		_expect(Options.exact_equal(baseline,_authority()),"navigation_cancel_authority_"+str(size))
		_expect(await _focus_by_tabs(scene.players_button),"reopen_players_focus_"+str(size))
		await _key(KEY_ENTER)
		if scene._player_exit.is_empty(): break
		dialog=scene._player_exit.dialog
		_expect(await _focus_by_tabs(dialog.get_ok_button()),"tab_to_explicit_end_"+str(size))
		await _key(KEY_ENTER)
		if not await _until_player_page("players"): break
		_expect(scene.facade==null and scene.review_joined,"chooser_actual_joined_boundary_"+str(size))
		if scene._player_ui.is_empty() or scene._player_ui.kind!="players": break
		if not await _until_players_idle(): break
		await _capture(output_absolute_directory,"players",size)
		var players: Control=scene._player_ui.widget
		_expect(players.get("_cancel").has_focus(),"chooser_default_cancel_focus_"+str(size))
		_expect(await _focus_by_tabs(players.get("_create")),"tab_to_create_"+str(size))
		await _key(KEY_SPACE)
		_expect(not scene._player_ui.is_empty() and scene._player_ui.kind=="create","space_opens_name_"+str(size))
		if scene._player_ui.is_empty() or scene._player_ui.kind!="create": break
		var name_page: Control=scene._player_ui.widget
		_expect(name_page.get("_cancel").has_focus(),"name_default_cancel_focus_"+str(size))
		var edit: LineEdit=name_page.get("_name")
		_expect(await _focus_by_tabs(edit),"tab_to_name_field_"+str(size))
		for character: String in "Keyboard check":
			await _text_character(character)
		_expect(edit.text=="Keyboard check","ordinary_unicode_name_entry_"+str(size))
		await _capture(output_absolute_directory,"player-name",size)
		await _key(KEY_ESCAPE)
		if not await _until_player_page("players"): break
		_expect(controller.selected_pair()==null,"cancel_name_keeps_guest_"+str(size))
		await _key(KEY_ESCAPE)
		var returned_to_menu: bool=scene._player_ui.is_empty() and scene.facade==null
		_expect(returned_to_menu,"escape_returns_to_no_flight_menu_"+str(size))
		if not returned_to_menu: break
		await _settle(3)
		await _capture(output_absolute_directory,"no-flight-menu",size)
		_expect(scene.resume_button.disabled,"no_flight_resume_disabled_"+str(size))
	return _result()

func _key(code: int, shift: bool=false) -> void:
	var down:=InputEventKey.new()
	down.keycode=code
	down.physical_keycode=code
	down.shift_pressed=shift
	down.pressed=true
	Input.parse_input_event(down)
	await _settle(1)
	var up:=InputEventKey.new()
	up.keycode=code
	up.physical_keycode=code
	up.shift_pressed=shift
	up.pressed=false
	Input.parse_input_event(up)
	await _settle(2)

func _text_character(character: String) -> void:
	var down:=InputEventKey.new()
	down.unicode=character.unicode_at(0)
	down.pressed=true
	Input.parse_input_event(down)
	await _settle(1)
	var up:=InputEventKey.new()
	up.unicode=character.unicode_at(0)
	up.pressed=false
	Input.parse_input_event(up)
	await _settle(1)

func _focus_by_tabs(target: Control) -> bool:
	if target==null or not target.is_visible_in_tree() or target.focus_mode==Control.FOCUS_NONE: return false
	for index in 64:
		if target.has_focus(): return true
		await _key(KEY_TAB)
	return target.has_focus()

func _button(root: Node, caption: String) -> Control:
	for child: Node in root.get_children():
		if child is Button and child.text==caption: return child
		var found: Control=_button(child,caption)
		if found!=null: return found
	return null

func _until_player_page(kind: String) -> bool:
	for frame in 180:
		if not _scene._player_ui.is_empty() and _scene._player_ui.kind==kind:
			_expect(true,"player_page_reached_"+kind)
			return true
		await _settle(1)
	_expect(false,"player_page_timeout_"+kind)
	return false

func _until_players_idle() -> bool:
	for frame in 180:
		if not _scene._player_ui.is_empty() and _scene._player_ui.kind=="players" and not _scene._player_ui.widget.get("_busy"):
			_expect(true,"players_query_settled")
			return true
		await _settle(1)
	_expect(false,"players_query_timeout")
	return false

func _settle(frames: int) -> void:
	for frame in frames: await _scene.get_tree().process_frame

func _authority() -> Dictionary:
	return {"native":{} if _scene.facade==null else _scene.facade.readback().duplicate(true),
		"recording":_scene.observed_recorder.recording(),"camera":_scene.view_settings.duplicate(true),
		"camera_mode":_scene.camera_mode,"look_angles":[_scene.look_angles.x,_scene.look_angles.y],
		"distance":_scene.camera_distance,"player":_scene._player_pair(),"seed":_scene.capture_current_player_seed()}

func _inside(control: Control) -> bool:
	if control==null or not control.is_visible_in_tree(): return false
	var rectangle: Rect2=control.get_global_rect()
	var viewport: Rect2=_scene.get_viewport().get_visible_rect()
	return rectangle.size.x>0 and rectangle.size.y>0 and viewport.encloses(rectangle)

func _capture(directory: String, label: String, dimensions: Vector2i) -> void:
	await _settle(3)
	await RenderingServer.frame_post_draw
	var capture: Image=_scene.get_viewport().get_texture().get_image()
	var path: String=directory.path_join("players-"+label+"-"+str(dimensions.x)+"x"+str(dimensions.y)+".png")
	var result: Error=capture.save_png(path)
	_expect(result==OK,"capture_"+label+"_"+str(dimensions))
	_captures.append({"path":path,"label":label,"width":capture.get_width(),"height":capture.get_height()})

func _expect(value: bool, label: String) -> void:
	_checks+=1
	if not value: _failures.append(label)

func _result() -> Dictionary:
	return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),
		"captures":_captures.duplicate(true),"scope":"visible ordinary keyboard/GUI navigation and original viewport captures; no independent pixel acceptance or full mapper ledger claim"}