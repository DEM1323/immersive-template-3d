extends Node3D
class_name RightWallStage

## Right Wall Projection Stage (+X, at (+4.0, 1.5, 0.0), rotated -90 deg Y).
## Displays "Echoes of the Round" (live history chronicle), Ephemeral Progress,
## Contextual Countdown Focus during Clues, and mirrored Wager Controls during
## Daily Double / Final Jeopardy so players standing on the right can interact too.

var game_state: JeopardyGameState
var audio: EphemeralAudioManager

var _chronicle_group: Node3D
var _chronicle_title: Label3D
var _chronicle_progress: Label3D
var _chronicle_body: Label3D
var _clue_timer_group: Node3D
var _big_timer_label: Label3D
var _big_team_label: Label3D
var _extend_btn: GlassButton3D
var _wager_mirror_group: Node3D
var _wager_mirror_amount: Label3D


func initialize(p_state: JeopardyGameState, p_audio: EphemeralAudioManager) -> void:
	game_state = p_state
	audio = p_audio
	_build_layout()
	_connect_signals()
	_refresh_chronicle()
	_sync_phase(game_state.phase)


func _connect_signals() -> void:
	game_state.phase_changed.connect(func(n, _o) -> void: _sync_phase(n))
	game_state.history_updated.connect(func(_h) -> void: _refresh_chronicle())
	game_state.pack_changed.connect(func(_p) -> void: _refresh_chronicle())
	game_state.board_reset.connect(func(_p) -> void: _refresh_chronicle())
	game_state.teams_updated.connect(func(_t, _idx) -> void: _refresh_active_team())
	game_state.timer_updated.connect(_on_timer_updated)
	game_state.wager_updated.connect(_on_wager_updated)


func _build_layout() -> void:
	# --- Chronicle / Echoes Group ---
	_chronicle_group = Node3D.new()
	_chronicle_group.name = "ChronicleGroup"
	add_child(_chronicle_group)

	_chronicle_title = CenterWallStage._make_label(
		"ECHOES OF THE ROUND",
		52,
		Color(0.95, 0.98, 1.0),
		Vector3(0.0, 1.32, 0.05),
		2050.0,
	)
	_chronicle_group.add_child(_chronicle_title)

	_chronicle_progress = CenterWallStage._make_label(
		"25 MONOLITHS AWAITING TOUCH",
		32,
		Color(0.56, 0.90, 1.0),
		Vector3(0.0, 1.00, 0.05),
		2000.0,
	)
	_chronicle_group.add_child(_chronicle_progress)

	var backdrop := GlassButton3D.new()
	backdrop.position = Vector3(0.0, -0.08, -0.02)
	backdrop.configure(
		Vector3(5.90, 1.78, 0.08),
		"",
		"",
		40,
		Color(0.05, 0.11, 0.24, 0.88),
		Color(0.40, 0.82, 1.0, 1.0),
	)
	backdrop.enable_idle_float = false
	backdrop.set_interactable_active(false)
	_chronicle_group.add_child(backdrop)

	_chronicle_body = CenterWallStage._make_label(
		"Touch any glowing monolith on the Center Wall to dissolve a clue into light.",
		38,
		Color(0.88, 0.94, 1.0),
		Vector3(0.0, -0.06, 0.08),
		1760.0,
	)
	_chronicle_group.add_child(_chronicle_body)

	# --- Active Clue Countdown Halo Group ---
	_clue_timer_group = Node3D.new()
	_clue_timer_group.name = "ActiveClueTimerGroup"
	add_child(_clue_timer_group)

	var timer_title := CenterWallStage._make_label(
		"EPHEMERAL COUNTDOWN",
		48,
		Color(0.78, 0.92, 1.0),
		Vector3(0.0, 1.24, 0.05),
		2000.0,
	)
	_clue_timer_group.add_child(timer_title)

	var timer_card := GlassButton3D.new()
	timer_card.position = Vector3(0.0, 0.22, -0.02)
	timer_card.configure(
		Vector3(4.2, 1.48, 0.08),
		"",
		"",
		40,
		Color(0.06, 0.12, 0.26, 0.90),
		Color(0.36, 0.90, 1.0, 1.0),
	)
	timer_card.enable_idle_float = false
	timer_card.set_interactable_active(false)
	_clue_timer_group.add_child(timer_card)

	_big_timer_label = CenterWallStage._make_label("25", 168, Color(0.45, 0.94, 1.0), Vector3(0.0, 0.36, 0.08), 1200.0)
	_clue_timer_group.add_child(_big_timer_label)

	_big_team_label = CenterWallStage._make_label(
		"ACTIVE: AURORA",
		40,
		Color(1.0, 0.88, 0.52),
		Vector3(0.0, -0.26, 0.08),
		1500.0,
	)
	_clue_timer_group.add_child(_big_team_label)

	_extend_btn = GlassButton3D.new()
	_extend_btn.position = Vector3(0.0, -0.92, 0.04)
	_extend_btn.configure(
		Vector3(2.8, 0.48, 0.09),
		"+10 SECONDS",
		"EXTEND THE MOMENT",
		44,
		Color(0.08, 0.18, 0.32, 0.90),
		Color(1.0, 0.84, 0.44, 1.0),
	)
	_extend_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("tap")
		game_state.extend_timer(10.0)
	)
	_clue_timer_group.add_child(_extend_btn)

	# --- Wager Mirror Group ---
	_wager_mirror_group = Node3D.new()
	_wager_mirror_group.name = "WagerMirrorGroup"
	add_child(_wager_mirror_group)

	var wm_title := CenterWallStage._make_label(
		"WAGER CONSOLE",
		56,
		Color(1.0, 0.86, 0.46),
		Vector3(0.0, 1.24, 0.05),
		1900.0,
	)
	_wager_mirror_group.add_child(wm_title)

	_wager_mirror_amount = CenterWallStage._make_label(
		"$500",
		128,
		Color(1.0, 0.94, 0.72),
		Vector3(0.0, 0.48, 0.06),
		1500.0,
	)
	_wager_mirror_group.add_child(_wager_mirror_amount)

	var mirror_presets := [
		{"label": "25%", "frac": 0.25, "x": -1.95},
		{"label": "50%", "frac": 0.50, "x": -0.65},
		{"label": "75%", "frac": 0.75, "x": 0.65},
		{"label": "ALL IN", "frac": 1.00, "x": 1.95},
	]
	for p in mirror_presets:
		var btn := GlassButton3D.new()
		btn.position = Vector3(float(p["x"]), -0.28, 0.0)
		btn.configure(
			Vector3(1.16, 0.44, 0.08),
			str(p["label"]),
			"",
			42,
			Color(0.11, 0.12, 0.30, 0.90),
			Color(0.86, 0.56, 1.0, 1.0),
		)
		var frac := float(p["frac"])
		btn.tapped.connect(func(_b, _pos, _v) -> void:
			audio.play_sfx("tap")
			game_state.set_wager_fraction(frac)
		)
		_wager_mirror_group.add_child(btn)

	var lock_btn := GlassButton3D.new()
	lock_btn.position = Vector3(0.0, -0.94, 0.05)
	lock_btn.configure(
		Vector3(2.80, 0.50, 0.10),
		"LOCK WAGER",
		"CONFIRM",
		48,
		Color(0.15, 0.24, 0.34, 0.92),
		Color(1.0, 0.84, 0.42, 1.0),
	)
	lock_btn.set_highlighted(true, 0.65)
	lock_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("dissolve")
		game_state.lock_wager()
	)
	_wager_mirror_group.add_child(lock_btn)


func _sync_phase(p: int) -> void:
	var is_clue := (p == JeopardyGameState.Phase.CLUE_ACTIVE or p == JeopardyGameState.Phase.FINAL_CLUE)
	var is_wager := (p == JeopardyGameState.Phase.DAILY_DOUBLE_WAGER or p == JeopardyGameState.Phase.FINAL_WAGER)
	_chronicle_group.visible = (not is_clue and not is_wager)
	_clue_timer_group.visible = is_clue
	_wager_mirror_group.visible = is_wager
	_refresh_active_team()
	_refresh_chronicle()


func _refresh_active_team() -> void:
	if game_state.active_team_index < game_state.teams.size():
		var t: Dictionary = game_state.teams[game_state.active_team_index]
		_big_team_label.text = "ACTIVE: %s" % str(t["name"])
		_big_team_label.modulate = t["color"]


func _refresh_chronicle() -> void:
	if game_state.current_pack != null:
		_chronicle_progress.text = "%s  •  %d / %d REMAINING" % [
			game_state.current_pack.title.to_upper(),
			game_state.remaining_tiles,
			game_state.total_tiles,
		]

	if game_state.history.is_empty():
		_chronicle_body.text = (
			"HOW TO PLAY\n\n"
			+ "• Tap any glowing value monolith on the Center Wall\n"
			+ "• Answer before the ephemeral light fades\n"
			+ "• Watch for hidden Ephemeral Surges (Daily Doubles)\n"
			+ "• Tap Team Podiums on the Left Wall or Floor to buzz in"
		)
		return

	var lines: Array[String] = []
	for i in range(min(5, game_state.history.size())):
		var item: Dictionary = game_state.history[i]
		var icon := "✦" if bool(item["was_correct"]) else "◇"
		lines.append("%s  %s ($%d) — %s\n     %s" % [
			icon,
			str(item["team_name"]),
			int(item["value"]),
			str(item["outcome"]),
			str(item["answer"]),
		])
	_chronicle_body.text = "\n\n".join(lines)


func _on_timer_updated(remaining: float, total: float, paused: bool) -> void:
	var ratio := clampf(remaining / maxf(total, 0.01), 0.0, 1.0)
	_big_timer_label.text = "HOLD" if paused else "%d" % int(ceil(remaining))
	if ratio > 0.45:
		_big_timer_label.modulate = Color(0.45, 0.94, 1.0)
	elif ratio > 0.22:
		_big_timer_label.modulate = Color(1.0, 0.82, 0.36)
	else:
		_big_timer_label.modulate = Color(1.0, 0.40, 0.52)


func _on_wager_updated(current_w: int, _min_w: int, _max_w: int) -> void:
	_wager_mirror_amount.text = "$%d" % current_w
