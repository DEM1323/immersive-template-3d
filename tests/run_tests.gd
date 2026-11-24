extends SceneTree

const PLAYER_SCENE := "res://Player.tscn"
const WORLD_SCENE := "res://scenes/jeopardy/EphemeralJeopardyWorld.tscn"
const WALLS := ["Left", "Center", "Right", "Back", "Floor"]
const FORWARD := [Vector3.LEFT, Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.DOWN]
const EPSILON := 0.001
const NORMAL_TILE := Vector2i(0, 0)
const PHASE := JeopardyGameState.Phase
const PLAY_MODE := JeopardyGameState.PlayMode

var _state: JeopardyGameState
var _failures: Array[String] = []
var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _run_case("Physical five-camera projector rig", _test_projector_rig)
	await _run_case("Question pack discovery and schema", _test_packs)

	_state = JeopardyGameState.new()
	root.add_child(_state)
	_state.set_process(false)
	await _run_case("Setup, play modes, and board initialization", _test_setup)
	await _run_case("Correct and incorrect quiz scoring", _test_quiz_scoring)
	await _run_case("Daily Double wagering", _test_daily_double)
	await _run_case("Host reveal and pass", _test_host_mode)
	await _run_case("Urgent timer ticks and timeout", _test_timer)
	await _run_case("Final Jeopardy wagers, result, and standings", _test_final_jeopardy)
	_state.free()

	await _run_case("World visibility, collisions, and single-touch tap", _test_world_integration)
	await _run_case("Editor-visible baked scene nodes before _ready()", _test_editor_baked_scenes)
	await _run_case("Split display modes (all 7 surface roles)", _test_display_modes)
	await _run_case("Center host <-> Left/Right/Back/Floor sync & deduplication", _test_split_floor_sync)
	await _run_case("WebSocket relay URL resolution (local, LAN, static hosts)", _test_ws_url_resolution)
	print("RESULT  %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _run_case(test_name: String, test: Callable) -> void:
	_failures.clear()
	var completed: Variant = await test.call()
	if completed != true and _failures.is_empty():
		_failures.append("Test stopped before completing its checks")
	if _failures.is_empty():
		_passed += 1
		print("PASS  ", test_name)
	else:
		_failed += 1
		print("FAIL  ", test_name)
		for failure in _failures:
			print("      ", failure)


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failures.append(message)
	return condition


func _test_projector_rig() -> bool:
	var scene := load(PLAYER_SCENE) as PackedScene
	if not _expect(scene != null, "Player.tscn must load"):
		return false
	var player := scene.instantiate() as Node3D
	if not _expect(player != null, "Player.tscn must instantiate as a Node3D"):
		return false
	root.add_child(player)
	_expect(player.get("Viewports") == WALLS.size(), "Player.Viewports must be 5")

	var hbox := player.get_node_or_null("Transform/HBoxContainer")
	var containers: Array[SubViewportContainer] = []
	if _expect(hbox != null, "Player must have a projector HBoxContainer"):
		for child in hbox.get_children():
			if child is SubViewportContainer:
				containers.append(child)
	_expect(containers.size() == WALLS.size(), "The projector HBoxContainer must have five SubViewportContainers")

	for index in range(WALLS.size()):
		var wall: String = WALLS[index]
		var camera := player.get("Camera" + wall) as Camera3D
		var container := player.get("Viewport" + wall) as SubViewportContainer
		if _expect(container != null, "%s viewport export is missing" % wall):
			_expect(
				index < containers.size() and containers[index] == container,
				"%s viewport must occupy slot %d" % [wall, index],
			)
		if not _expect(camera != null, "%s camera export is missing" % wall):
			continue
		_expect(
			camera.global_position.distance_to(Vector3(0.0, 1.5, 0.0)) <= EPSILON,
			"%s camera position was %s" % [wall, camera.global_position],
		)
		_expect(absf(camera.fov - 90.0) <= EPSILON, "%s camera FOV was %s" % [wall, camera.fov])
		_expect(camera.keep_aspect == Camera3D.KEEP_WIDTH, "%s camera must keep horizontal FOV" % wall)
		var forward := -camera.transform.basis.z
		_expect(forward.distance_to(FORWARD[index]) <= EPSILON, "%s camera points toward %s" % [wall, forward])
		var viewport := camera.get_viewport() as SubViewport
		_expect(
			viewport != null and viewport.get_parent() == container and viewport.get_camera_3d() == camera,
			"%s camera must render its exported viewport" % wall,
		)
	player.free()
	return true


func _test_packs() -> bool:
	var packs := JeopardyPack.load_all_packs()
	_expect(not packs.is_empty(), "JeopardyPack.load_all_packs() discovered no valid JSON packs")
	var loaded_paths := {}
	for pack in packs:
		loaded_paths[pack.source_path] = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(pack.source_path))
		if _expect(parsed is Dictionary, "%s must have a JSON object at the root" % pack.source_path):
			var errors := JeopardyPack.validate_dictionary(parsed)
			_expect(errors.is_empty(), "%s validation errors: %s" % [pack.source_path, ", ".join(errors)])
		var filename := pack.source_path.get_file()
		if filename in JeopardyPack.BUILTIN_PACK_FILES:
			_expect(pack.get_category_count() == 5, "%s must contain five categories" % filename)
		for category in pack.categories:
			var clues: Array = category.get("clues", [])
			var context := "%s / %s" % [filename, category.get("name", "")]
			if filename in JeopardyPack.BUILTIN_PACK_FILES:
				_expect(clues.size() == 5, "%s must contain five clues" % context)
			for row in range(clues.size()):
				_check_pack_clue(clues[row], "%s / clue %d" % [context, row + 1])
		_check_pack_clue(pack.final_jeopardy, "%s / Final Jeopardy" % filename)

	for filename in JeopardyPack.BUILTIN_PACK_FILES:
		var path := JeopardyPack.PACKS_DIR.path_join(filename)
		if FileAccess.file_exists(path):
			_expect(loaded_paths.has(path), "Built-in pack %s exists and must load" % filename)
	print("      Loaded %d JSON pack(s)" % packs.size())
	return true


func _check_pack_clue(clue: Dictionary, context: String) -> void:
	var choices: Array = clue.get("choices", [])
	_expect(choices.size() == 4, "%s must have four choices" % context)
	var correct: Variant = clue.get("correct_index", -1)
	_expect(
		(correct is int or correct is float) and float(correct) == floorf(float(correct))
			and float(correct) >= 0.0 and float(correct) < 4.0,
		"%s correct_index must be an integer from 0 through 3" % context,
	)
	for choice in choices:
		_expect(choice is String and not str(choice).strip_edges().is_empty(), "%s has an invalid choice" % context)


func _test_setup() -> bool:
	_expect(_state.phase == PHASE.SETUP, "A fresh game must open in SETUP")
	_expect(_state.play_mode == PLAY_MODE.QUIZ, "A fresh game must default to QUIZ")
	for count in range(1, 5):
		_state.set_team_count(count)
		_expect(_state.team_count == count and _state.teams.size() == count, "Expected %d teams" % count)
		_expect(_state.phase == PHASE.SETUP, "Setting team count must preserve SETUP")

	_state.toggle_play_mode()
	_expect(_state.play_mode == PLAY_MODE.HOST, "Mode must toggle from QUIZ to HOST")
	_state.toggle_play_mode()
	_expect(_state.play_mode == PLAY_MODE.QUIZ, "Mode must toggle from HOST to QUIZ")

	_start_board(4)
	_expect(_state.phase == PHASE.BOARD, "Starting a game must enter BOARD")
	_expect(_state.total_tiles == 25 and _state.remaining_tiles == 25, "Fresh board must have 25 available tiles")
	_expect(_state.daily_double_keys.size() == 2, "Fresh board must have two Daily Doubles")
	var first_placement := _state.daily_double_keys.duplicate()
	_start_board(4)
	_expect(_state.daily_double_keys == first_placement, "Seed 42 must repeat the Daily Double placement")
	return true


func _test_quiz_scoring() -> bool:
	_start_board()
	if not _select_tile(NORMAL_TILE, PHASE.CLUE_ACTIVE):
		return false
	var team := _state.active_team_index
	var clue := _state.current_pack.get_clue(NORMAL_TILE.x, NORMAL_TILE.y)
	var value := int(clue.get("value", 0))
	_expect(_state.submit_choice(int(clue.get("correct_index", -1))), "Correct choice must return true")
	_expect(_state.phase == PHASE.CLUE_RESULT, "A correct answer must enter CLUE_RESULT")
	_expect(_score(team) == value and value > 0, "Correct choice must add its exact clue value")
	_expect(int(_state.teams[team]["streak"]) == 1, "Correct choice must increment streak")
	_expect(_state.is_tile_cleared(NORMAL_TILE.x, NORMAL_TILE.y), "Answered tile must be cleared")
	_expect(_state.remaining_tiles == 24, "Resolving a tile must decrement remaining tiles once")
	if _expect(_state.history.size() == 1, "The Chronicle must receive one entry"):
		var entry := _state.history[0]
		_expect(
			entry["value"] == value and entry["outcome"] == "CORRECT" and entry["answer"] == clue["answer"],
			"The Chronicle must record the clue value, outcome, and answer",
		)
	_state.continue_after_result()
	_expect(_state.phase == PHASE.BOARD, "Continuing after a correct answer must return to BOARD")
	_expect(not _state.select_tile(NORMAL_TILE.x, NORMAL_TILE.y), "A cleared tile must reject reselection")
	_expect(_state.active_team_index == team, "A correct answer must keep the same active team")

	if not _select_tile(Vector2i(1, 0), PHASE.CLUE_ACTIVE):
		return false
	var wrong_value := int(_state.active_clue["value"])
	var wrong_index := (int(_state.active_clue["correct_index"]) + 1) % 4
	var score_before := _score(team)
	_expect(not _state.submit_choice(wrong_index), "Wrong choice must return false")
	_expect(_state.phase == PHASE.CLUE_RESULT, "A wrong answer must enter CLUE_RESULT")
	_expect(_score(team) == score_before - wrong_value, "Wrong choice must deduct its exact clue value")
	_expect(int(_state.teams[team]["streak"]) == 0, "Wrong choice must reset the answering team's streak")
	_expect(_state.active_team_index == (team + 1) % _state.teams.size(), "Wrong choice must rotate the turn")
	_state.continue_after_result()
	_expect(_state.phase == PHASE.BOARD, "Continuing after a wrong answer must return to BOARD")
	return true


func _test_daily_double() -> bool:
	_start_board()
	var double_tile := Vector2i(-1, -1)
	for column in range(5):
		for row in range(5):
			if _state.is_tile_daily_double(column, row):
				double_tile = Vector2i(column, row)
				break
		if double_tile.x >= 0:
			break
	if not _expect(double_tile.x >= 0, "At least one Daily Double must be selectable"):
		return false
	if not _select_tile(double_tile, PHASE.DAILY_DOUBLE_WAGER):
		return false

	_expect(_state.max_wager > _state.min_wager, "Daily Double must have a valid wager range")
	var original := _state.current_wager
	_state.adjust_wager(100)
	_expect(_state.current_wager == mini(original + 100, _state.max_wager), "Adjusting must change the wager")
	_state.adjust_wager(-1000000)
	_expect(_state.current_wager == _state.min_wager, "Adjusting below minimum must clamp to minimum")
	_state.set_wager_fraction(1.0)
	_expect(_state.current_wager == _state.max_wager, "A 100% wager must exactly equal the maximum")
	var wager := _state.current_wager
	_state.lock_wager()
	_expect(_state.phase == PHASE.CLUE_ACTIVE, "Locking a Daily Double must enter CLUE_ACTIVE")
	_expect(_state.active_is_daily_double and _state.active_value == wager, "The clue must use the locked wager")
	return true


func _test_host_mode() -> bool:
	_start_board()
	_state.set_play_mode(PLAY_MODE.HOST)
	if not _select_tile(NORMAL_TILE, PHASE.CLUE_ACTIVE):
		return false

	var revealed_answers: Array[String] = []
	_state.host_answer_revealed.connect(
		func(answer: String) -> void: revealed_answers.append(answer),
		CONNECT_ONE_SHOT,
	)
	_state.reveal_host_answer()
	_expect(_state.host_revealed, "Host reveal must mark the answer revealed")
	var expected_answer := str(_state.active_clue.get("answer", ""))
	_expect(revealed_answers == [expected_answer], "Host reveal must emit the clue's answer exactly once")

	var team := _state.active_team_index
	var score_before := _score(team)
	_state.submit_host_judgment(false, true)
	_expect(_state.phase == PHASE.CLUE_RESULT, "A Host pass must enter CLUE_RESULT")
	_expect(_state.last_result.get("outcome") == "PASSED", "A Host pass must report PASSED, not TIME UP")
	_expect(_score(team) == score_before and _state.last_result.get("score_delta") == 0, "A Host pass must score zero")
	return true


func _test_timer() -> bool:
	_start_board()
	if not _select_tile(NORMAL_TILE, PHASE.CLUE_ACTIVE):
		return false

	var urgent_seconds: Array[int] = []
	var listener := func(seconds: int) -> void: urgent_seconds.append(seconds)
	_state.timer_urgent_tick.connect(listener)
	_state.tick_timer(_state.timer_remaining - 6.0)
	_expect(urgent_seconds.is_empty(), "Urgent ticks must wait until five seconds remain")
	_state.tick_timer(1.0)
	for second in range(5, 0, -1):
		_state.tick_timer(0.25)
		_expect(urgent_seconds.size() == 6 - second, "Urgent tick %d must fire once" % second)
		_state.tick_timer(0.75)
	_state.timer_urgent_tick.disconnect(listener)

	_expect(urgent_seconds == [5, 4, 3, 2, 1], "Urgent ticks must be [5, 4, 3, 2, 1], got %s" % [urgent_seconds])
	_expect(is_zero_approx(_state.timer_remaining), "Expired timer must stop at 0.0")
	_expect(_state.phase == PHASE.CLUE_RESULT, "An expired timer must enter CLUE_RESULT")
	_expect(_state.last_result.get("timed_out") == true, "The result must mark the clue as timed out")
	return true


func _test_final_jeopardy() -> bool:
	_start_board(3)
	_state.set_active_team(2)
	if not _select_tile(NORMAL_TILE, PHASE.CLUE_ACTIVE):
		return false
	_state.submit_choice(int(_state.active_clue["correct_index"]))
	_state.continue_after_result()

	var final_clue := _state.current_pack.final_jeopardy
	var finished_standings: Array[Dictionary] = []
	_state.game_finished.connect(
		func(standings: Array[Dictionary]) -> void: finished_standings.assign(standings),
		CONNECT_ONE_SHOT,
	)
	_state.begin_final_jeopardy()
	var wagers: Array[int] = [100, 500, 1000]
	for team in range(wagers.size()):
		if not _expect(_state.phase == PHASE.FINAL_WAGER, "Expected Final wager phase for team %d" % team):
			return false
		_expect(_state.active_team_index == team, "Final wagers must be collected in team order")
		_state.set_wager_fraction(float(wagers[team]) / 1000.0)
		_state.lock_wager()
		_expect(_state.final_wagers[team] == wagers[team], "Team %d must retain its locked wager" % team)

	var correct_idx := int(final_clue.get("correct_index", -1))
	for team in range(wagers.size()):
		if not _expect(_state.phase == PHASE.FINAL_CLUE, "Expected Final clue for team %d" % team):
			return false
		_expect(_state.active_team_index == team, "Final clue must advance through every team")
		_expect(_state.active_is_final and _state.active_clue == final_clue, "Active clue must be Final Jeopardy")
		var pick := correct_idx if team != 1 else (correct_idx + 1) % 4
		_state.submit_choice(pick)
		_expect(_state.phase == PHASE.CLUE_RESULT and _state.last_result.get("is_final"), "Expected a Final result")
		var expected_delta := wagers[team] if team != 1 else -wagers[team]
		_expect(_state.last_result.get("score_delta") == expected_delta, "Final answer must use team's locked wager")
		_state.continue_after_result()
	_expect(_state.phase == PHASE.GAME_OVER, "Continuing after the last team's Final result must end the game")
	if _expect(finished_standings.size() == wagers.size(), "game_finished must include every team"):
		_expect(finished_standings == _state.get_standings(), "The final signal must match current standings")
		_expect(finished_standings[0]["index"] == 2, "The team with the highest score must be ranked first")
		for index in range(1, finished_standings.size()):
			var previous := int(finished_standings[index - 1]["score"])
			var score := int(finished_standings[index]["score"])
			_expect(previous >= score, "Final standings must be sorted by descending score")
	return true


func _start_board(team_count: int = 2) -> void:
	_state.set_team_count(team_count)
	_state.set_play_mode(PLAY_MODE.QUIZ)
	_state.set_random_seed(42)
	_state.start_new_game()


func _select_tile(coords: Vector2i, expected_phase: int) -> bool:
	return (
		_expect(_state.select_tile(coords.x, coords.y), "Expected tile %s to be selectable" % coords)
		and _expect(_state.phase == expected_phase, "Tile %s must lead to phase %d" % [coords, expected_phase])
	)


func _score(team: int) -> int:
	return int(_state.teams[team]["score"])


func _test_world_integration() -> bool:
	var scene := load(WORLD_SCENE) as PackedScene
	if not _expect(scene != null, "EphemeralJeopardyWorld.tscn must load"):
		return false
	var world := scene.instantiate()
	if not _expect(world != null, "EphemeralJeopardyWorld.tscn must instantiate"):
		return false
	root.add_child(world)
	var ready: bool = await _check_world(world)
	world.free()
	return ready


func _check_world(world: Node) -> bool:
	await process_frame
	await process_frame
	var state := world.get_node_or_null("JeopardyGameState") as JeopardyGameState
	var setup := world.get_node_or_null("CenterWallStage/SetupGroup")
	var board := world.get_node_or_null("CenterWallStage/BoardGroup")
	var bus := root.get_node_or_null("InteractionBus")
	if not _expect(state != null and setup != null and board != null and bus != null, "World must wire its stages"):
		return false

	var mouse := world.get_node_or_null("Player/Transform/HBoxContainer/Control")
	_expect(mouse != null and mouse.get("single_touch_only") == true, "MultitouchMouse must default to single touch")
	_expect(state.phase == PHASE.SETUP, "Instantiated world must begin in SETUP")
	var setup_buttons := _check_collision_layers(setup, &"tapped", 1)
	var hidden_tiles := _check_collision_layers(board, &"tile_tapped", 0)
	_expect(setup_buttons.size() == 7, "SETUP must have seven active configuration buttons")
	if _expect(hidden_tiles.size() == 25, "SETUP must have 25 hidden board tiles"):
		_emit_center_tap(bus, hidden_tiles[0])
		_expect(state.phase == PHASE.SETUP, "A hidden tile must ignore a bus tap")

	state.set_random_seed(42)
	state.start_new_game()
	await process_frame
	await process_frame
	_expect(state.phase == PHASE.BOARD, "World must enter BOARD after starting")
	_check_collision_layers(setup, &"tapped", 0)
	var active_tiles := _check_collision_layers(board, &"tile_tapped", 1)
	_expect(active_tiles.size() == 25, "BOARD must have 25 active board tiles")
	for tile in active_tiles:
		if tile.get("cat_idx") != NORMAL_TILE.x or tile.get("row_idx") != NORMAL_TILE.y:
			continue
		_emit_center_tap(bus, tile)
		_expect(state.phase == PHASE.CLUE_ACTIVE, "A center-wall bus tap must enter CLUE_ACTIVE")
		_expect(
			state.active_cat_idx == NORMAL_TILE.x and state.active_row_idx == NORMAL_TILE.y,
			"The bus tap must open the exact clue associated with the tile",
		)
		_expect(tile.collision_layer == 0, "The selected tile must stop intercepting input while the clue is open")
		return true
	return _expect(false, "Could not find the normal tile for a center-wall tap")


func _check_collision_layers(group: Node, signal_name: StringName, layer: int) -> Array[StaticBody3D]:
	var bodies: Array[StaticBody3D] = []
	for child in group.get_children():
		if child is StaticBody3D and child.has_signal(signal_name):
			bodies.append(child)
			_expect(child.collision_layer == layer, "%s/%s collision layer was %d, expected %d" % [
				group.name, child.name, child.collision_layer, layer,
			])
	return bodies


func _emit_center_tap(bus: Node, tile: StaticBody3D) -> void:
	bus.emit_signal(&"single_touch_tap", tile, tile.global_position, Vector3.BACK, 1)


func _test_editor_baked_scenes() -> bool:
	var scene := load(WORLD_SCENE) as PackedScene
	if not _expect(scene != null, "EphemeralJeopardyWorld.tscn must load"):
		return false
	# Instantiate WITHOUT adding to SceneTree (so _ready() has NOT run!) to verify editor visibility
	var world := scene.instantiate()
	if not _expect(world != null, "EphemeralJeopardyWorld.tscn must instantiate"):
		return false
	var required_paths := [
		"SanctuaryEnvironment/SanctuaryWorldEnvironment",
		"SanctuaryEnvironment/CornerPillar_0",
		"SanctuaryEnvironment/AuroraRibbon_0",
		"CenterWallStage/SetupGroup/BeginGameButton",
		"CenterWallStage/BoardGroup/CategoryHeader_0",
		"CenterWallStage/BoardGroup/Tile_0_0",
		"CenterWallStage/BoardGroup/Tile_4_4",
		"CenterWallStage/ClueGroup/QuizChoices",
		"LeftWallStage/TeamPodium_0",
		"RightWallStage/ChronicleGroup",
		"BackWallStage/PrimaryActionBtn",
		"FloorStage/MandalaPlane",
		"FloorStage/FloorTeamPad_0",
	]
	for p in required_paths:
		_expect(world.get_node_or_null(p) != null, "Baked editor node missing before _ready(): %s" % p)
	world.free()
	return true


func _test_display_modes() -> bool:
	var scene := load(PLAYER_SCENE) as PackedScene
	if not _expect(scene != null, "Player.tscn must load for display mode test"):
		return false
	var player := scene.instantiate() as Node3D
	root.add_child(player)
	var containers: Array = player.call("get_subviewport_containers")

	var mode_matrix := [
		[0, [0, 1, 2, 3, 4], "ALL_5"],
		[1, [0, 1, 2, 3], "WALLS_4"],
		[2, [4], "FLOOR_ONLY"],
		[3, [0], "LEFT_ONLY"],
		[4, [1], "CENTER_ONLY"],
		[5, [2], "RIGHT_ONLY"],
		[6, [3], "BACK_ONLY"],
	]
	for entry in mode_matrix:
		var mode_id: int = entry[0]
		var expected_slots: Array = entry[1]
		var mode_name: String = entry[2]
		player.call("set_display_mode", mode_id)
		_expect(player.get("Viewports") == 5, "Viewports invariant must remain 5 in %s" % mode_name)
		for i in range(5):
			var should_show := i in expected_slots
			_expect(
				containers[i].visible == should_show,
				"%s slot %d visibility was %s, expected %s" % [mode_name, i, containers[i].visible, should_show],
			)

	player.free()
	return true


func _test_split_floor_sync() -> bool:
	var host_state := JeopardyGameState.new()
	var replica_state := JeopardyGameState.new()
	replica_state.is_replica = true
	root.add_child(host_state)
	root.add_child(replica_state)
	host_state.set_process(false)
	replica_state.set_process(false)

	var host_tx := RoomSyncTransport.new()
	var replica_tx := RoomSyncTransport.new()
	root.add_child(host_tx)
	root.add_child(replica_tx)
	host_tx.configure("center", "test_room", "", false)
	replica_tx.configure("left", "test_room", "", false)

	var delivered_to_replica: Array[int] = [0]
	replica_tx.message_received.connect(func(_m: Dictionary) -> void: delivered_to_replica[0] += 1)

	# Simulate dual-transport delivery (BroadcastChannel + WebSocket delivering same frame twice)
	host_tx.message_sent_json.connect(func(raw: String) -> void:
		replica_tx.inject_raw_for_test(raw)
		replica_tx.inject_raw_for_test(raw)
	)
	replica_tx.message_sent_json.connect(func(raw: String) -> void:
		host_tx.inject_raw_for_test(raw)
		host_tx.inject_raw_for_test(raw)
	)

	var host_sync := GameStateSync.new()
	var replica_sync := GameStateSync.new()
	root.add_child(host_sync)
	root.add_child(replica_sync)
	host_sync.initialize(host_state, null, null, host_tx, true)
	replica_sync.initialize(replica_state, null, null, replica_tx, false)
	host_sync.set_process(false)
	replica_sync.set_process(false)

	# 1. Host advances mid-game, replica sends hello & hydrates full state including clue text
	host_state.set_team_count(3)
	host_state.set_random_seed(42)
	host_state.start_new_game()
	host_state.select_tile(0, 0)
	var before_hello: int = delivered_to_replica[0]
	replica_sync.send_hello()
	_expect(delivered_to_replica[0] == before_hello + 1, "Duplicate dual-transport delivery must deduplicate to 1")
	_expect(replica_state.phase == PHASE.CLUE_ACTIVE, "Replica must hydrate CLUE_ACTIVE phase from host snapshot")
	_expect(replica_state.teams.size() == 3, "Replica must hydrate all 3 teams from host snapshot")
	_expect(replica_state.active_value == host_state.active_value, "Replica must hydrate active clue value")
	_expect(
		str(replica_state.active_clue.get("clue", "")) == str(host_state.active_clue.get("clue", "")),
		"Replica (Back wall) must reconstruct exact active clue text from shared pack",
	)

	# 2. Replica commands from Left/Right/Back/Floor route cleanly to Center host and replicate back
	replica_state.set_active_team(2)
	_expect(host_state.active_team_index == 2, "Floor/Left buzz_team command must update authoritative host team")
	_expect(replica_state.active_team_index == 2, "Updated host team must replicate back")

	replica_state.toggle_play_mode()
	_expect(
		host_state.play_mode == PLAY_MODE.HOST and replica_state.play_mode == PLAY_MODE.HOST,
		"Left mode toggle must sync",
	)

	replica_state.toggle_audio_mute()
	_expect(host_state.audio_muted and replica_state.audio_muted, "Left mute toggle must sync to Center host and back")

	var prev_timer := host_state.timer_remaining
	replica_state.extend_timer(10.0)
	_expect(host_state.timer_remaining > prev_timer, "Right +10s extend_timer must update host timer")

	replica_state.cycle_active_team()
	_expect(
		host_state.active_team_index == 0 and replica_state.active_team_index == 0,
		"Back cycle_active_team must sync",
	)

	# 3. Host resolves clue -> replica receives updated score, history chronicle & phase
	var correct_idx := int(host_state.active_clue["correct_index"])
	host_state.submit_choice(correct_idx)
	_expect(replica_state.phase == PHASE.CLUE_RESULT, "Replica must mirror CLUE_RESULT phase")
	_expect(int(replica_state.teams[0]["score"]) == host_state.active_value, "Replica must mirror updated team score")
	_expect(replica_state.history.size() == 1, "Right wall Echoes Chronicle must sync history entries")

	replica_state.continue_after_result()
	_expect(
		host_state.phase == PHASE.BOARD and replica_state.phase == PHASE.BOARD,
		"Back continue must advance host & replica",
	)

	host_sync.free()
	replica_sync.free()
	host_tx.free()
	replica_tx.free()
	host_state.free()
	replica_state.free()
	return true


func _test_ws_url_resolution() -> bool:
	var cases := [
		["", "http:", "localhost:8080", "ws://localhost:8080/ws", "localhost auto-connects"],
		["", "http:", "127.0.0.1:8080", "ws://127.0.0.1:8080/ws", "127.0.0.1 auto-connects"],
		["", "http:", "[::1]:8080", "ws://[::1]:8080/ws", "IPv6 loopback auto-connects"],
		["", "http:", "192.168.1.50:8080", "ws://192.168.1.50:8080/ws", "192.168.* LAN auto-connects"],
		["", "http:", "10.0.0.7", "ws://10.0.0.7/ws", "10.* LAN auto-connects"],
		["", "https:", "172.20.4.2:8443", "wss://172.20.4.2:8443/ws", "172.16-31.* LAN uses wss on https"],
		["", "http:", "172.32.0.1", "", "172.32.* is not private"],
		["", "https:", "projector-pc.local", "wss://projector-pc.local/ws", ".local mDNS host auto-connects"],
		["", "https:", "dem1323.github.io", "", "GitHub Pages must not auto-connect to /ws"],
		["none", "http:", "localhost:8080", "", "?ws=none disables WebSocket"],
		["OFF", "http:", "localhost:8080", "", "?ws=OFF disables WebSocket (case-insensitive)"],
		["false", "https:", "dem1323.github.io", "", "?ws=false disables WebSocket"],
		[
			"wss://relay.example.dev/ws",
			"https:",
			"dem1323.github.io",
			"wss://relay.example.dev/ws",
			"Explicit ?ws= relay is used verbatim",
		],
	]
	for c in cases:
		var got := RoomRole.resolve_ws_url(c[0], c[1], c[2])
		_expect(got == c[3], "%s: expected '%s', got '%s'" % [c[4], c[3], got])
	return true
