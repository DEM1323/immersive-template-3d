extends Node3D
class_name FloorStage

## Floor Projection Stage (-Y, centered at (0, 0, 0), viewed from (0, 1.5, 0) looking down).
## Top of floor projection (-Z) faces Center Wall; +X faces Right Wall.
## Hosts the glowing geometric Sanctuary Mandala with live world-space touch ripples
## plus interactive Team Floor Touch Pads strictly within the 16:9 safe zone.
##
## All nodes live in FloorStage.tscn; the script binds to them and never moves hand-placed ones.

const FLOOR_SHADER_PATH := "res://shaders/floor_mandala.gdshader"
const MANDALA_SIZE := 6.4
const MAX_TEAMS := 4

var game_state: JeopardyGameState
var audio: EphemeralAudioManager

var _mandala_mesh: MeshInstance3D
var _mandala_mat: ShaderMaterial
var _floor_touch_body: ImmersiveInteractable3D
var _team_pads: Array[GlassButton3D] = []
var _center_label: Label3D
var _ripple_age: float = 10.0


func initialize(p_state: JeopardyGameState, p_audio: EphemeralAudioManager) -> void:
	game_state = p_state
	audio = p_audio
	if not _bind_nodes():
		build_default_nodes(null)
		_bind_nodes()
	_wire_touch()
	_connect_signals()
	_refresh_team_pads()
	_sync_state_visuals(game_state.phase)
	set_process(true)


func _process(delta: float) -> void:
	if _mandala_mat == null:
		return
	if _ripple_age < 4.0:
		_ripple_age += delta
		_mandala_mat.set_shader_parameter("ripple_age", _ripple_age)


func _connect_signals() -> void:
	game_state.phase_changed.connect(func(n, _o) -> void: _sync_state_visuals(n))
	game_state.teams_updated.connect(func(_t, _idx) -> void: _refresh_team_pads())
	game_state.timer_updated.connect(_on_timer_updated)
	game_state.clue_resolved.connect(_on_clue_resolved)
	var bus := get_node_or_null(^"/root/InteractionBus")
	if bus != null and not bus.is_connected(&"touch_ripple", _on_bus_touch_ripple):
		bus.connect(&"touch_ripple", _on_bus_touch_ripple)


func _bind_nodes() -> bool:
	_mandala_mesh = get_node_or_null("MandalaPlane") as MeshInstance3D
	_mandala_mat = null
	if _mandala_mesh != null:
		_mandala_mat = _mandala_mesh.get_active_material(0) as ShaderMaterial
	_floor_touch_body = get_node_or_null("FloorRippleSurface") as ImmersiveInteractable3D
	_center_label = get_node_or_null("CenterLabel") as Label3D
	_team_pads = CenterWallStage.collect_buttons(self, "FloorTeamPad_%d", range(MAX_TEAMS))
	var required: Array[Node] = [_mandala_mesh, _floor_touch_body, _center_label]
	return _team_pads.size() == MAX_TEAMS and CenterWallStage.all_present(required)


func _wire_touch() -> void:
	_floor_touch_body.tapped.connect(_on_floor_surface_tapped)
	for i in range(_team_pads.size()):
		_team_pads[i].tapped.connect(func(_b, hit_pos, _vp) -> void:
			audio.play_sfx("tap", 0.06)
			game_state.set_active_team(i)
			var col: Color = game_state.teams[i]["color"] if i < game_state.teams.size() else Color.CYAN
			trigger_floor_ripple(hit_pos, col)
		)


## Creates every missing stage node. Existing nodes are never touched, so manual edits survive.
## Pass the scene root as owner_root to make the nodes saveable; pass null for a code-only instance.
func build_default_nodes(owner_root: Node) -> void:
	if not has_node("MandalaPlane"):
		var mandala := _make_mandala()
		mandala.name = "MandalaPlane"
		add_child(mandala)
		mandala.owner = owner_root

	# Full-floor touch surface (slightly below pads so pads get hit first)
	if not has_node("FloorRippleSurface"):
		var body := ImmersiveInteractable3D.new()
		body.name = "FloorRippleSurface"
		body.local_cooldown_sec = 0.08
		add_child(body)
		body.owner = owner_root
		var shape := BoxShape3D.new()
		shape.size = Vector3(MANDALA_SIZE, 0.04, MANDALA_SIZE)
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		col.shape = shape
		col.position = Vector3(0.0, -0.02, 0.0)
		body.add_child(col)
		col.owner = owner_root

	# Upright center compass label (reads facing Center Wall)
	if not has_node("CenterLabel"):
		var label := CenterWallStage.ensure_label(
			self,
			owner_root,
			"CenterLabel",
			"EPHEMERAL\nSANCTUARY",
			36,
			Color(0.95, 0.99, 1.0, 1.0),
			Vector3(0.0, 0.04, 0.0),
			850.0,
		)
		label.pixel_size = 0.0022
		label.render_priority = 7
		label.rotation.x = -PI * 0.5

	_build_team_floor_pads(owner_root)


func _make_mandala() -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(MANDALA_SIZE, MANDALA_SIZE)
	var mandala := MeshInstance3D.new()
	mandala.mesh = quad
	# Rotate -90 deg X so local +Y points to -Z (Center wall) and +Z points UP (+Y)
	mandala.rotation.x = -PI * 0.5
	mandala.position = Vector3(0.0, 0.005, 0.0)

	if ResourceLoader.exists(FLOOR_SHADER_PATH):
		var shader := load(FLOOR_SHADER_PATH) as Shader
		if shader != null:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			mat.render_priority = -8
			mandala.material_override = mat
	if mandala.material_override == null:
		var fallback := StandardMaterial3D.new()
		fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fallback.albedo_color = Color(0.03, 0.06, 0.14, 1.0)
		mandala.material_override = fallback
	return mandala


func _build_team_floor_pads(owner_root: Node) -> void:
	# Strictly inside 16:9 floor safe bounds: x in [-1.25, +1.25], z in [-0.70, +0.70]
	var pad_positions: Array[Vector3] = [
		Vector3(-0.96, 0.035, -0.44),  # Front-Left
		Vector3(0.96, 0.035, -0.44),   # Front-Right
		Vector3(-0.96, 0.035, 0.44),   # Back-Left
		Vector3(0.96, 0.035, 0.44),    # Back-Right
	]
	for i in range(MAX_TEAMS):
		if has_node("FloorTeamPad_%d" % i):
			continue
		var preset: Dictionary = JeopardyGameState.TEAM_PRESETS[i]
		var col: Color = preset["color"]
		var pad := CenterWallStage.ensure_button(self, owner_root, "FloorTeamPad_%d" % i, pad_positions[i], {
			"panel_size": Vector3(0.74, 0.34, 0.03),
			"primary_text": str(preset["name"]),
			"secondary_text": "$0",
			"primary_font_size": 36,
			"secondary_font_size": 28,
			"base_color": _pad_base_color(col, i == 0),
			"rim_color": col,
			"accent_color": Color(1.0, 0.86, 0.44),
			"text_color": Color(0.98, 0.99, 1.0),
			"highlight_amount": 1.0 if i == 0 else 0.0,
			"enable_idle_float": false,
			"panel_render_priority": 3,
			"label_render_priority": 6,
		})
		pad.rotation.x = -PI * 0.5


func _pad_base_color(col: Color, active: bool) -> Color:
	if active:
		return Color(col.r * 0.18, col.g * 0.20, col.b * 0.30, 0.90)
	return Color(0.05, 0.11, 0.24, 0.85)


func _on_floor_surface_tapped(_body: ImmersiveInteractable3D, hit_pos: Vector3, _vp: int) -> void:
	audio.play_sfx("tap", 0.10, -8.0)
	trigger_floor_ripple(hit_pos, Color(0.46, 0.94, 1.0, 1.0))


func _on_bus_touch_ripple(world_pos: Vector3, _normal: Vector3, viewport_index: int, color: Color) -> void:
	if viewport_index == 4:
		trigger_floor_ripple(world_pos, color)


func trigger_floor_ripple(world_pos: Vector3, color: Color) -> void:
	if _mandala_mat == null:
		return
	# Measured in the mandala's own plane so ripples stay under the finger if it is moved or resized.
	var local_pos := _mandala_mesh.to_local(world_pos)
	var plane_size := Vector2(MANDALA_SIZE, MANDALA_SIZE)
	if _mandala_mesh.mesh is QuadMesh:
		plane_size = (_mandala_mesh.mesh as QuadMesh).size
	var u := clampf(0.5 + local_pos.x / plane_size.x, 0.0, 1.0)
	var v := clampf(0.5 - local_pos.y / plane_size.y, 0.0, 1.0)
	_ripple_age = 0.0
	_mandala_mat.set_shader_parameter("ripple_uv", Vector2(u, v))
	_mandala_mat.set_shader_parameter("ripple_age", 0.0)
	_mandala_mat.set_shader_parameter("ripple_color", Vector3(color.r, color.g, color.b))


func _refresh_team_pads() -> void:
	var count := game_state.teams.size()
	for i in range(_team_pads.size()):
		var pad := _team_pads[i]
		if i >= count:
			pad.visible = false
			continue
		pad.visible = true
		var t: Dictionary = game_state.teams[i]
		var col: Color = t["color"]
		var active := (i == game_state.active_team_index)
		pad.set_texts(str(t["name"]), EphemeralTheme.format_money(int(t["score"])))
		pad.set_highlighted(active, 1.0)
		pad.set_palette(_pad_base_color(col, active), col, Color(1.0, 0.86, 0.44), Color(0.98, 0.99, 1.0))


func set_floor_interactions_enabled(enabled: bool) -> void:
	if _floor_touch_body != null:
		_floor_touch_body.set_interactable_active(enabled)
	for pad in _team_pads:
		if is_instance_valid(pad):
			pad.set_interactable_active(enabled)


func _sync_state_visuals(p: int) -> void:
	if _mandala_mat == null:
		return
	match p:
		JeopardyGameState.Phase.SETUP:
			_center_label.text = "EPHEMERAL\nSANCTUARY"
			_mandala_mat.set_shader_parameter("ring_color", Color(0.32, 0.84, 0.98, 1.0))
			_mandala_mat.set_shader_parameter("accent_color", Color(0.95, 0.80, 0.42, 1.0))
			_mandala_mat.set_shader_parameter("pulse_speed", 0.75)
			_mandala_mat.set_shader_parameter("show_timer_arc", 0.0)
		JeopardyGameState.Phase.BOARD:
			_center_label.text = "CHOOSE A\nMONOLITH"
			_mandala_mat.set_shader_parameter("ring_color", Color(0.28, 0.84, 0.96, 1.0))
			_mandala_mat.set_shader_parameter("accent_color", Color(0.96, 0.82, 0.44, 1.0))
			_mandala_mat.set_shader_parameter("pulse_speed", 0.9)
			_mandala_mat.set_shader_parameter("show_timer_arc", 0.0)
		JeopardyGameState.Phase.DAILY_DOUBLE_WAGER, JeopardyGameState.Phase.FINAL_WAGER:
			_center_label.text = "EPHEMERAL\nSURGE"
			_mandala_mat.set_shader_parameter("ring_color", Color(0.92, 0.42, 1.0, 1.0))
			_mandala_mat.set_shader_parameter("accent_color", Color(1.0, 0.82, 0.34, 1.0))
			_mandala_mat.set_shader_parameter("pulse_speed", 2.1)
			_mandala_mat.set_shader_parameter("show_timer_arc", 0.0)
			trigger_floor_ripple(Vector3.ZERO, Color(1.0, 0.82, 0.40))
		JeopardyGameState.Phase.CLUE_ACTIVE, JeopardyGameState.Phase.FINAL_CLUE:
			_center_label.text = "ANSWER\nNOW"
			_mandala_mat.set_shader_parameter("ring_color", Color(0.30, 0.92, 0.96, 1.0))
			_mandala_mat.set_shader_parameter("pulse_speed", 1.4)
			_mandala_mat.set_shader_parameter("show_timer_arc", 1.0)
		JeopardyGameState.Phase.GAME_OVER:
			_center_label.text = "FINALE"
			_mandala_mat.set_shader_parameter("ring_color", Color(1.0, 0.84, 0.42, 1.0))
			_mandala_mat.set_shader_parameter("accent_color", Color(0.38, 0.98, 0.78, 1.0))
			_mandala_mat.set_shader_parameter("pulse_speed", 1.6)
			_mandala_mat.set_shader_parameter("show_timer_arc", 0.0)
			trigger_floor_ripple(Vector3.ZERO, Color(1.0, 0.88, 0.45))


func _on_timer_updated(remaining: float, total: float, _paused: bool) -> void:
	if _mandala_mat == null:
		return
	var ratio := clampf(remaining / maxf(total, 0.01), 0.0, 1.0)
	_mandala_mat.set_shader_parameter("timer_ratio", ratio)
	_mandala_mat.set_shader_parameter("pulse_speed", lerpf(3.4, 1.2, ratio))
	if game_state.phase == JeopardyGameState.Phase.CLUE_ACTIVE or game_state.phase == JeopardyGameState.Phase.FINAL_CLUE:
		_center_label.text = "%ds" % int(ceil(remaining))


func _on_clue_resolved(res: Dictionary) -> void:
	var was_correct := bool(res.get("was_correct", false))
	var burst_col := Color(0.34, 0.98, 0.72) if was_correct else Color(1.0, 0.44, 0.56)
	trigger_floor_ripple(Vector3.ZERO, burst_col)
	if _mandala_mat != null:
		_mandala_mat.set_shader_parameter("show_timer_arc", 0.0)
		_mandala_mat.set_shader_parameter("ring_color", burst_col)
	_center_label.text = "CORRECT!" if was_correct else str(res.get("outcome", ""))
