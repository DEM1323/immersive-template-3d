extends SceneTree

## Bakes every Ephemeral Jeopardy stage into an editable .tscn so the whole room is visible and
## editable in the Godot Editor.
##
##   godot --headless --path . --script res://tools/bake_editor_scenes.gd
##       Safe default: keeps existing scenes and only adds default nodes that are missing.
##   godot --headless --path . --script res://tools/bake_editor_scenes.gd -- --reset
##       Rebuilds every scene from code defaults. DISCARDS all manual Godot Editor edits.

const SCENE_DIR := "res://scenes/jeopardy"
const SCRIPT_DIR := "res://scripts/jeopardy"
const WORLD_PATH := SCENE_DIR + "/EphemeralJeopardyWorld.tscn"
const PLAYER_PATH := "res://Player.tscn"
const STAGES := [
	{"name": "SanctuaryEnvironment", "script": "sanctuary_environment.gd", "pos": Vector3.ZERO, "yaw": 0.0},
	{"name": "CenterWallStage", "script": "center_wall_stage.gd", "pos": Vector3(0.0, 1.5, -4.0), "yaw": 0.0},
	{"name": "LeftWallStage", "script": "left_wall_stage.gd", "pos": Vector3(-4.0, 1.5, 0.0), "yaw": 90.0},
	{"name": "RightWallStage", "script": "right_wall_stage.gd", "pos": Vector3(4.0, 1.5, 0.0), "yaw": -90.0},
	{"name": "BackWallStage", "script": "back_wall_stage.gd", "pos": Vector3(0.0, 1.5, 4.0), "yaw": 180.0},
	{"name": "FloorStage", "script": "floor_stage.gd", "pos": Vector3.ZERO, "yaw": 0.0},
]

var _errors := 0


func _initialize() -> void:
	# Deferred so autoloads exist before any stage script is compiled.
	_run.call_deferred()


func _run() -> void:
	var reset := OS.get_cmdline_user_args().has("--reset")
	for stage: Dictionary in STAGES:
		_bake_stage(stage, reset)
	if _errors == 0:
		_bake_world(reset)
	print("BAKE  %s" % ("OK" if _errors == 0 else "FAILED with %d error(s)" % _errors))
	quit(0 if _errors == 0 else 1)


func _bake_stage(stage: Dictionary, reset: bool) -> void:
	var path := _stage_path(stage)
	var root_node: Node3D = null
	if not reset and ResourceLoader.exists(path):
		root_node = (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_MAIN) as Node3D
	var is_new := root_node == null
	if is_new:
		root_node = Node3D.new()
		root_node.name = stage["name"]
		root_node.set_script(load("%s/%s" % [SCRIPT_DIR, stage["script"]]))

	var before := _count_owned(root_node, root_node)
	root_node.call("build_default_nodes", root_node)
	var after := _count_owned(root_node, root_node)
	if not is_new and after == before:
		print("KEEP  %s (%d nodes, nothing missing)" % [path, after])
	else:
		print("SAVE  %s (%d nodes, %d added)" % [path, after, after - before])
		_save(root_node, path)
	root_node.free()


func _bake_world(reset: bool) -> void:
	if not reset and _world_is_baked():
		print("KEEP  %s (already instances every baked stage)" % WORLD_PATH)
		return

	var world := Node3D.new()
	world.name = "EphemeralJeopardyWorld"
	world.set_script(load("%s/ephemeral_jeopardy_controller.gd" % SCRIPT_DIR))
	_adopt(world, (load(PLAYER_PATH) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE), "Player")
	_adopt(world, _script_node("jeopardy_game_state.gd"), "JeopardyGameState")
	_adopt(world, _script_node("audio_manager.gd"), "EphemeralAudioManager")

	for stage: Dictionary in STAGES:
		var packed := ResourceLoader.load(_stage_path(stage), "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
		if packed == null:
			_fail("Could not load %s" % _stage_path(stage))
			continue
		var instance := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
		instance.position = stage["pos"]
		instance.rotation_degrees.y = stage["yaw"]
		_adopt(world, instance, stage["name"])
		# Player is deliberately NOT editable: the 5-camera projector rig must stay untouched.
		world.set_editable_instance(instance, true)

	print("SAVE  %s" % WORLD_PATH)
	_save(world, WORLD_PATH)
	world.free()


func _world_is_baked() -> bool:
	if not ResourceLoader.exists(WORLD_PATH):
		return false
	var deps := ResourceLoader.get_dependencies(WORLD_PATH)
	for stage: Dictionary in STAGES:
		var path := _stage_path(stage)
		var found := false
		for dep in deps:
			found = found or dep.ends_with(path)
		if not found:
			return false
	return true


func _script_node(script_name: String) -> Node:
	var node := Node.new()
	node.set_script(load("%s/%s" % [SCRIPT_DIR, script_name]))
	return node


func _adopt(world: Node, node: Node, node_name: String) -> void:
	node.name = node_name
	world.add_child(node)
	node.owner = world


func _stage_path(stage: Dictionary) -> String:
	return "%s/%s.tscn" % [SCENE_DIR, stage["name"]]


func _count_owned(node: Node, root_node: Node) -> int:
	var total := 1 if node == root_node or node.owner == root_node else 0
	for child in node.get_children():
		total += _count_owned(child, root_node)
	return total


func _save(root_node: Node, path: String) -> void:
	var packed := PackedScene.new()
	var pack_error := packed.pack(root_node)
	if pack_error != OK:
		_fail("Could not pack %s (%s)" % [path, error_string(pack_error)])
		return
	var save_error := ResourceSaver.save(packed, path)
	if save_error != OK:
		_fail("Could not save %s (%s)" % [path, error_string(save_error)])
		return
	_strip_null_shader_parameters(path)


## The headless dummy renderer reports every shader default as null; drop those lines so the
## materials inherit the real defaults declared in their .gdshader.
func _strip_null_shader_parameters(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var kept: PackedStringArray = []
	for line in text.split("\n"):
		if not (line.begins_with("shader_parameter/") and line.strip_edges().ends_with("= null")):
			kept.append(line)
	var cleaned := "\n".join(kept)
	if cleaned == text:
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Could not rewrite %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(cleaned)
	file.close()


func _fail(message: String) -> void:
	_errors += 1
	push_error("Scene baker: " + message)
