extends Node3D
class_name BackWallStage

## Back Wall Projection Stage (+Z, at (0.0, 1.5, +4.0), rotated 180 deg Y).
## Acts as a radiant 360-degree Spectator Mirror, Live Leaderboard, and quick
## back-of-room participation console (Cycle Team / Continue / New Game).

var game_state: JeopardyGameState
var audio: EphemeralAudioManager

var _header_label: Label3D
var _main_label: Label3D
var _sub_label: Label3D
var _primary_action_btn: GlassButton3D
var _buzz_cycle_btn: GlassButton3D


func initialize(p_state: JeopardyGameState, p_audio: EphemeralAudioManager) -> void:
	game_state = p_state
	audio = p_audio
	_build_layout()
	_connect_signals()
	_refresh_view()


func _connect_signals() -> void:
	game_state.phase_changed.connect(func(_n, _o) -> void: _refresh_view())
	game_state.teams_updated.connect(func(_t, _idx) -> void: _refresh_view())
	game_state.clue_started.connect(func(_p) -> void: _refresh_view())
	game_state.clue_resolved.connect(func(_r) -> void: _refresh_view())
	game_state.timer_updated.connect(_on_timer_updated)
	game_state.pack_changed.connect(func(_p) -> void: _refresh_view())


func _build_layout() -> void:
	_header_label = CenterWallStage._make_label(
		"EPHEMERAL JEOPARDY  •  SANCTUARY MIRROR",
		48,
		Color(0.86, 0.96, 1.0),
		Vector3(0.0, 1.30, 0.05),
		2100.0,
	)
	add_child(_header_label)

	var panel := GlassButton3D.new()
	panel.position = Vector3(0.0, 0.24, -0.02)
	panel.configure(
		Vector3(5.90, 1.50, 0.08),
		"",
		"",
		40,
		Color(0.05, 0.11, 0.24, 0.88),
		Color(0.56, 0.72, 1.0, 1.0),
		Color(1.0, 0.84, 0.44, 1.0),
	)
	panel.enable_idle_float = false
	panel.set_interactable_active(false)
	add_child(panel)

	_main_label = CenterWallStage._make_label(
		"WELCOME TO THE SANCTUARY",
		58,
		Color(0.98, 0.99, 1.0),
		Vector3(0.0, 0.44, 0.08),
		1800.0,
	)
	add_child(_main_label)

	_sub_label = CenterWallStage._make_label(
		"Step inside and touch any luminous monolith.",
		38,
		Color(0.76, 0.90, 1.0),
		Vector3(0.0, -0.18, 0.08),
		1780.0,
	)
	add_child(_sub_label)

	_buzz_cycle_btn = GlassButton3D.new()
	_buzz_cycle_btn.position = Vector3(-1.45, -0.96, 0.04)
	_buzz_cycle_btn.configure(
		Vector3(2.55, 0.46, 0.09),
		"SWITCH ACTIVE TEAM",
		"BACK WALL BUZZ",
		38,
		Color(0.08, 0.15, 0.30, 0.90),
		Color(0.42, 0.90, 1.0, 1.0),
	)
	_buzz_cycle_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("tap")
		game_state.cycle_active_team()
	)
	add_child(_buzz_cycle_btn)

	_primary_action_btn = GlassButton3D.new()
	_primary_action_btn.position = Vector3(1.45, -0.96, 0.04)
	_primary_action_btn.configure(
		Vector3(2.55, 0.46, 0.09),
		"BEGIN / CONTINUE",
		"SYNC WITH CENTER",
		38,
		Color(0.10, 0.21, 0.34, 0.92),
		Color(1.0, 0.84, 0.44, 1.0),
	)
	_primary_action_btn.tapped.connect(_on_primary_action_tapped)
	add_child(_primary_action_btn)


func _on_primary_action_tapped(_b: ImmersiveInteractable3D, _p: Vector3, _v: int) -> void:
	audio.play_sfx("tap")
	match game_state.phase:
		JeopardyGameState.Phase.SETUP, JeopardyGameState.Phase.GAME_OVER:
			game_state.start_new_game()
		JeopardyGameState.Phase.CLUE_RESULT:
			game_state.continue_after_result()
		JeopardyGameState.Phase.DAILY_DOUBLE_WAGER, JeopardyGameState.Phase.FINAL_WAGER:
			game_state.lock_wager()
		_:
			game_state.return_to_setup()


func _refresh_view() -> void:
	match game_state.phase:
		JeopardyGameState.Phase.SETUP:
			_header_label.text = "EPHEMERAL JEOPARDY  •  360° IMMERSIVE SANCTUARY"
			var pack_name := game_state.current_pack.title.to_upper() if game_state.current_pack != null else "JEOPARDY"
			_main_label.text = pack_name
			_sub_label.text = "Face the Center Wall to configure teams & begin,\nor tap START right here."
			_primary_action_btn.set_texts("START GAME", "ILLUMINATE BOARD")

		JeopardyGameState.Phase.BOARD:
			_header_label.text = "LIVE LEADERBOARD  •  %d/%d CLUES LEFT" % [
				game_state.remaining_tiles,
				game_state.total_tiles,
			]
			_main_label.text = _format_leaderboard()
			var active_name := str(game_state.teams[game_state.active_team_index]["name"])
			_sub_label.text = "CURRENT TURN: %s" % active_name
			_primary_action_btn.set_texts("RETURN TO LOBBY", "CHANGE PACK")

		JeopardyGameState.Phase.DAILY_DOUBLE_WAGER, JeopardyGameState.Phase.FINAL_WAGER:
			_header_label.text = "WAGER IN PROGRESS"
			_main_label.text = "EPHEMERAL SURGE" if game_state.active_is_daily_double else "THE LAST ECHO"
			var active_name := str(game_state.teams[game_state.active_team_index]["name"])
			_sub_label.text = "%s IS SETTING THEIR WAGER" % active_name
			_primary_action_btn.set_texts("LOCK WAGER", "CONFIRM")

		JeopardyGameState.Phase.CLUE_ACTIVE, JeopardyGameState.Phase.FINAL_CLUE:
			_header_label.text = "ACTIVE CLUE  •  $%d" % game_state.active_value
			_main_label.text = str(game_state.active_clue.get("clue", ""))
			_sub_label.text = "TIME REMAINING: %ds" % int(ceil(game_state.timer_remaining))
			_primary_action_btn.set_texts("RETURN TO LOBBY", "EXIT CLUE")

		JeopardyGameState.Phase.CLUE_RESULT:
			_header_label.text = "CLUE RESOLVED"
			_main_label.text = str(game_state.last_result.get("answer", ""))
			_sub_label.text = "%s  •  %s" % [
				str(game_state.last_result.get("team_name", "")),
				str(game_state.last_result.get("outcome", "")),
			]
			_primary_action_btn.set_texts("CONTINUE", "NEXT STEP")

		JeopardyGameState.Phase.GAME_OVER:
			_header_label.text = "FINAL STANDINGS"
			_main_label.text = _format_leaderboard()
			_sub_label.text = "Thank you for illuminating the sanctuary."
			_primary_action_btn.set_texts("PLAY AGAIN", "NEW BOARD")


func _on_timer_updated(remaining: float, _total: float, paused: bool) -> void:
	if game_state.phase == JeopardyGameState.Phase.CLUE_ACTIVE or game_state.phase == JeopardyGameState.Phase.FINAL_CLUE:
		_sub_label.text = "TIMER PAUSED" if paused else "TIME REMAINING: %ds" % int(ceil(remaining))


func _format_leaderboard() -> String:
	var standings := game_state.get_standings()
	var lines: Array[String] = []
	for i in range(standings.size()):
		var t: Dictionary = standings[i]
		lines.append("#%d  %s  —  %s" % [i + 1, str(t["name"]), EphemeralTheme.format_money(int(t["score"]))])
	return "\n".join(lines)
