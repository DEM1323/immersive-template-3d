extends Node3D
class_name LeftWallStage

## Left Wall Projection Stage (-X, at (-4.0, 1.5, 0.0), rotated +90 deg Y).
## Hosts interactive Team Score Podiums (tap any podium to claim turn / buzz in)
## and single-touch Sanctuary Control Crystals (New Game, Mode, Pause/+10s, Mute, Final, Pack).

var game_state: JeopardyGameState
var audio: EphemeralAudioManager

var _podium_buttons: Array[GlassButton3D] = []
var _mode_btn: GlassButton3D
var _timer_pause_btn: GlassButton3D
var _mute_btn: GlassButton3D
var _pack_btn: GlassButton3D
var _status_label: Label3D


func initialize(p_state: JeopardyGameState, p_audio: EphemeralAudioManager) -> void:
	game_state = p_state
	audio = p_audio
	_build_layout()
	_connect_signals()
	_refresh_podiums()
	_refresh_control_labels()


func _connect_signals() -> void:
	game_state.teams_updated.connect(func(_t, _idx) -> void: _refresh_podiums())
	game_state.play_mode_changed.connect(func(_m) -> void: _refresh_control_labels())
	game_state.pack_changed.connect(func(_p) -> void: _refresh_control_labels())
	game_state.timer_updated.connect(func(_rem, _tot, _paused) -> void: _refresh_control_labels())
	game_state.phase_changed.connect(func(_n, _o) -> void: _refresh_control_labels())
	audio.mute_changed.connect(func(_m) -> void: _refresh_control_labels())


func _build_layout() -> void:
	var title := CenterWallStage._make_label(
		"TEAM PODIUMS  •  TAP TO BUZZ / SELECT",
		48,
		Color(0.92, 0.98, 1.0),
		Vector3(0.0, 1.34, 0.05),
		2100.0,
	)
	add_child(title)

	_status_label = CenterWallStage._make_label(
		"EPHEMERAL SANCTUARY READY",
		30,
		Color(0.62, 0.88, 0.98),
		Vector3(0.0, 1.04, 0.05),
		2050.0,
	)
	add_child(_status_label)

	# 4 Team Podium slots (dynamically arranged & shown based on team_count)
	_podium_buttons.clear()
	for i in range(4):
		var pod := GlassButton3D.new()
		pod.name = "TeamPodium_%d" % i
		pod.configure(
			Vector3(1.45, 0.98, 0.09),
			"TEAM %d" % (i + 1),
			"$0",
			46,
			Color(0.06, 0.13, 0.27, 0.90),
			Color(0.36, 0.88, 1.0, 1.0),
		)
		pod.secondary_font_size = 44
		var team_idx := i
		pod.tapped.connect(func(_b, _p, _v) -> void:
			audio.play_sfx("tap", 0.05)
			game_state.set_active_team(team_idx)
		)
		add_child(pod)
		_podium_buttons.append(pod)

	# Bottom 2 rows of Sanctuary Control Crystals (6 buttons, 3x2 grid)
	var controls_title := CenterWallStage._make_label(
		"SANCTUARY CONTROLS",
		30,
		Color(0.70, 0.85, 0.98),
		Vector3(0.0, -0.30, 0.05),
		1800.0,
	)
	add_child(controls_title)

	var new_game_btn := GlassButton3D.new()
	new_game_btn.position = Vector3(-2.05, -0.64, 0.0)
	new_game_btn.configure(
		Vector3(1.88, 0.40, 0.08),
		"NEW GAME",
		"RESET BOARD",
		34,
		Color(0.07, 0.18, 0.30, 0.90),
		Color(0.36, 0.92, 0.86, 1.0),
	)
	new_game_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("tap")
		game_state.start_new_game()
	)
	add_child(new_game_btn)

	_mode_btn = GlassButton3D.new()
	_mode_btn.position = Vector3(0.0, -0.64, 0.0)
	_mode_btn.configure(
		Vector3(1.88, 0.40, 0.08),
		"MODE: QUIZ",
		"TAP TO SWITCH",
		34,
		Color(0.09, 0.14, 0.30, 0.90),
		Color(0.76, 0.56, 1.0, 1.0),
	)
	_mode_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("tap")
		game_state.toggle_play_mode()
	)
	add_child(_mode_btn)

	_pack_btn = GlassButton3D.new()
	_pack_btn.position = Vector3(2.05, -0.64, 0.0)
	_pack_btn.configure(
		Vector3(1.88, 0.40, 0.08),
		"NEXT PACK",
		"SWITCH THEME",
		34,
		Color(0.08, 0.15, 0.30, 0.90),
		Color(1.0, 0.82, 0.42, 1.0),
	)
	_pack_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("tap")
		game_state.cycle_pack()
	)
	add_child(_pack_btn)

	_timer_pause_btn = GlassButton3D.new()
	_timer_pause_btn.position = Vector3(-2.05, -1.12, 0.0)
	_timer_pause_btn.configure(
		Vector3(1.88, 0.40, 0.08),
		"PAUSE TIMER",
		"+ HOLD MOMENT",
		34,
		Color(0.07, 0.14, 0.28, 0.90),
		Color(0.42, 0.86, 1.0, 1.0),
	)
	_timer_pause_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("tap")
		game_state.toggle_timer_pause()
	)
	add_child(_timer_pause_btn)

	_mute_btn = GlassButton3D.new()
	_mute_btn.position = Vector3(0.0, -1.12, 0.0)
	_mute_btn.configure(
		Vector3(1.88, 0.40, 0.08),
		"AUDIO: ON",
		"TAP TO MUTE",
		34,
		Color(0.07, 0.14, 0.28, 0.90),
		Color(0.42, 0.86, 1.0, 1.0),
	)
	_mute_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.toggle_mute()
		audio.play_sfx("tap")
	)
	add_child(_mute_btn)

	var final_btn := GlassButton3D.new()
	final_btn.position = Vector3(2.05, -1.12, 0.0)
	final_btn.configure(
		Vector3(1.88, 0.40, 0.08),
		"FINAL ROUND",
		"THE LAST ECHO",
		34,
		Color(0.14, 0.11, 0.30, 0.90),
		Color(1.0, 0.78, 0.36, 1.0),
	)
	final_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("daily_double", 0.02, -4.0)
		game_state.begin_final_jeopardy()
	)
	add_child(final_btn)


func _refresh_podiums() -> void:
	var count := game_state.teams.size()
	var spacing := 1.56 if count == 4 else (2.05 if count == 3 else 2.55)
	var x_start := -0.5 * float(count - 1) * spacing

	for i in range(_podium_buttons.size()):
		var pod := _podium_buttons[i]
		if i >= count:
			pod.visible = false
			continue
		pod.visible = true
		pod.position = Vector3(x_start + float(i) * spacing, 0.36, 0.0)

		var t: Dictionary = game_state.teams[i]
		var col: Color = t["color"]
		var score := int(t["score"])
		var streak := int(t["streak"])
		var active := (i == game_state.active_team_index)
		var name_line := "%s%s" % ["★ " if active else "", str(t["name"])]
		var score_prefix := "-$" if score < 0 else "$"
		var detail := "%s%d" % [score_prefix, abs(score)]
		if streak >= 2:
			detail += "\nSTREAK x%d" % streak

		pod.set_texts(name_line, detail)
		pod.set_highlighted(active, 1.05)
		var base := Color(col.r * 0.16, col.g * 0.18, col.b * 0.28, 0.92) if active else Color(0.06, 0.12, 0.25, 0.86)
		pod.set_palette(base, col, Color(1.0, 0.88, 0.50), Color(0.98, 0.99, 1.0))


func _refresh_control_labels() -> void:
	var mode_str := "QUIZ" if game_state.play_mode == JeopardyGameState.PlayMode.QUIZ else "HOST"
	_mode_btn.set_texts("MODE: %s" % mode_str, "TAP TO SWITCH")
	_timer_pause_btn.set_texts("RESUME TIMER" if game_state.timer_paused else "PAUSE TIMER", "+ HOLD MOMENT")
	_mute_btn.set_texts("AUDIO: MUTED" if audio.is_muted else "AUDIO: ON", "TAP TO TOGGLE")
	if game_state.current_pack != null:
		_pack_btn.set_texts("SWITCH PACK", game_state.current_pack.title.to_upper())
		_status_label.text = "%s  •  %d / %d CLUES REMAINING" % [
			game_state.current_pack.title.to_upper(),
			game_state.remaining_tiles,
			game_state.total_tiles,
		]
