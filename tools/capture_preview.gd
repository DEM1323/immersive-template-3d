extends SceneTree

const WORLD_SCENE := "res://scenes/jeopardy/EphemeralJeopardyWorld.tscn"
const SCREENSHOTS := "res://tools/screenshots"
const STRIP_SIZE := Vector2i(2400, 270)
const WALL_SIZE := Vector2i(960, 540)
const WALL_NAMES := ["left", "center", "right", "back", "floor"]
const CENTER := 1
const PHASE := JeopardyGameState.Phase

var _player: Node
var _center_stage: Node
var _state: JeopardyGameState
var _saved_images := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		_fail("Preview capture requires a rendered Godot window")
		quit(1)
		return

	var scene := load(WORLD_SCENE) as PackedScene
	if scene == null:
		_fail("Could not load %s" % WORLD_SCENE)
		quit(1)
		return
	var world := scene.instantiate()
	if world == null:
		_fail("Could not instantiate the Jeopardy world")
		quit(1)
		return
	root.add_child(world)
	_player = world.get_node_or_null("Player")
	_center_stage = world.get_node_or_null("CenterWallStage")
	_state = world.get_node_or_null("JeopardyGameState") as JeopardyGameState
	if _state == null or _player == null or not _player.has_method("set_preview_wall"):
		_fail("The world must provide a Jeopardy game state and five-wall Player")
		quit(1)
		return

	if _center_stage == null or not _center_stage.has_node("SetupGroup"):
		_fail("The center-wall stage did not initialize")
		quit(1)
		return

	var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCREENSHOTS))
	if mkdir_error != OK:
		_fail("Could not create %s (%s)" % [SCREENSHOTS, error_string(mkdir_error)])
		quit(1)
		return

	# The timer is stepped explicitly so every angle shows the same live clue and countdown.
	_state.set_process(false)
	_state.set_random_seed(42)
	var completed: Variant = await _capture_journey()
	if completed == true:
		print("Saved %d PNGs to %s" % [_saved_images, ProjectSettings.globalize_path(SCREENSHOTS)])
		quit(0)
	else:
		_fail("Preview sequence stopped after saving %d PNGs" % _saved_images)
		quit(1)


func _capture_journey() -> bool:
	if not await _capture_state("01_setup", PHASE.SETUP):
		return false

	_state.start_new_game()
	if not await _capture_state("02_board", PHASE.BOARD, true):
		return false
	if not _clear_demo_tiles():
		return false
	await create_timer(0.65).timeout
	if not await _capture_state("02_board_ghosts", PHASE.BOARD, true):
		return false

	var daily_double := _find_daily_double()
	if daily_double.x < 0 or not _state.select_tile(daily_double.x, daily_double.y):
		return _fail("Could not select a Daily Double")
	_state.set_wager_fraction(0.75)
	if not await _capture_state("03_daily_double", PHASE.DAILY_DOUBLE_WAGER):
		return false

	_state.lock_wager()
	_state.tick_timer(maxf(0.0, _state.timer_remaining - 12.0))
	if not await _capture_active_clue():
		return false
	if not _play_finale():
		return false
	return await _capture_state("05_finale", PHASE.GAME_OVER)


func _capture_active_clue() -> bool:
	var quiz_choices := _center_stage.get_node_or_null("ClueGroup/QuizChoices") as Node3D
	if quiz_choices == null or not quiz_choices.is_visible_in_tree() or quiz_choices.get_child_count() != 4:
		return _fail("Expected four visible answer cards in the active clue")
	if _state.timer_remaining <= 0.0:
		return _fail("The preview clue must have an active countdown")
	return await _capture_state("04_clue_active", PHASE.CLUE_ACTIVE, true)


func _clear_demo_tiles() -> bool:
	var tiles := [Vector2i(0, 0), Vector2i(2, 0), Vector2i(4, 0)]
	for index in range(tiles.size()):
		var coords: Vector2i = tiles[index]
		_state.set_active_team(index % _state.teams.size())
		if not _state.select_tile(coords.x, coords.y) or _state.phase != PHASE.CLUE_ACTIVE:
			return _fail("Could not open a normal preview clue at %s" % coords)
		var correct := int(_state.active_clue["correct_index"])
		_state.submit_choice((correct + 1) % 4 if index == 1 else correct)
		_state.continue_after_result()
	if _state.remaining_tiles != _state.total_tiles - tiles.size():
		return _fail("Expected exactly three cleared tiles")
	return true


func _find_daily_double() -> Vector2i:
	for column in range(_state.current_pack.get_category_count()):
		for row in range(_state.current_pack.get_row_count()):
			if _state.is_tile_daily_double(column, row):
				return Vector2i(column, row)
	return Vector2i(-1, -1)


func _play_finale() -> bool:
	_state.submit_choice(int(_state.active_clue["correct_index"]))
	_state.continue_after_result()
	_state.begin_final_jeopardy()
	for team in range(_state.teams.size()):
		if _state.phase != PHASE.FINAL_WAGER or _state.active_team_index != team:
			return _fail("Expected Final Jeopardy wager for team %d" % (team + 1))
		_state.set_wager_fraction(0.5)
		_state.lock_wager()
	for team in range(_state.teams.size()):
		if _state.phase != PHASE.FINAL_CLUE:
			return _fail("Final Jeopardy clue did not open for team %d" % (team + 1))
		var correct := int(_state.active_clue["correct_index"])
		_state.submit_choice(correct if team == 0 else (correct + 1) % 4)
		_state.continue_after_result()
	return true


func _capture_state(name: String, expected_phase: int, all_walls: bool = false) -> bool:
	if _state.phase != expected_phase:
		return _fail("%s expected phase %d, got %d" % [name, expected_phase, _state.phase])

	await _set_view(-1, STRIP_SIZE)
	var containers: Array = _player.call("get_subviewport_containers")
	var strip_wall_size := Vector2i(480, 270)
	for index in range(WALL_NAMES.size()):
		var viewport := _get_wall_viewport(containers, index)
		if viewport == null or viewport.size != strip_wall_size:
			return _fail("%s projector must occupy a 480x270 slice of the strip" % WALL_NAMES[index])
	var strip := root.get_viewport().get_texture().get_image()
	if not _save_image(name + "_strip", strip, STRIP_SIZE):
		return false

	var walls: Array = range(WALL_NAMES.size()) if all_walls else [CENTER]
	for index in walls:
		if not await _capture_wall(name, index):
			return false
	await _set_view(-1, STRIP_SIZE)
	return true


func _capture_wall(name: String, index: int) -> bool:
	await _set_view(index, WALL_SIZE)
	var containers: Array = _player.call("get_subviewport_containers")
	var viewport := _get_wall_viewport(containers, index)
	if viewport == null:
		return _fail("%s projector is missing its SubViewport" % WALL_NAMES[index])
	return _save_image(name + "_" + WALL_NAMES[index], viewport.get_texture().get_image(), WALL_SIZE)


func _get_wall_viewport(containers: Array, index: int) -> SubViewport:
	if index >= containers.size() or containers[index] == null:
		return null
	return containers[index].get_node_or_null("SubViewport") as SubViewport


func _set_view(wall: int, target_size: Vector2i) -> void:
	if DisplayServer.window_get_size() != target_size:
		DisplayServer.window_set_size(target_size)
	_player.call("set_preview_wall", wall)
	for _frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw


func _save_image(name: String, image: Image, expected_size: Vector2i) -> bool:
	if image == null or image.is_empty():
		return _fail("%s has no image data" % name)
	if image.get_size() != expected_size:
		return _fail("%s rendered at %s, expected %s" % [name, image.get_size(), expected_size])
	var path := SCREENSHOTS.path_join(name + ".png")
	var save_error := image.save_png(path)
	if save_error != OK:
		return _fail("Could not save %s (%s)" % [path, error_string(save_error)])
	_saved_images += 1
	print("SAVED  %s  %dx%d" % [path, expected_size.x, expected_size.y])
	return true


func _fail(message: String) -> bool:
	push_error("Preview capture: " + message)
	return false
