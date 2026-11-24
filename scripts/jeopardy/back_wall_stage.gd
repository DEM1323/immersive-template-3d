extends Node3D
class_name BackWallStage

## Back Wall Projection Stage (+Z, at (0.0, 1.5, +4.0), rotated 180 deg Y).
## Acts as a radiant 360-degree Spectator Mirror, Live Leaderboard, and quick
## back-of-room participation console (Cycle Team / Continue / New Game).
##
## All nodes live in BackWallStage.tscn; the script binds to them and never moves hand-placed ones.

var game_state: JeopardyGameState
var audio: EphemeralAudioManager

var _header_label: Label3D
var _main_label: Label3D
var _sub_label: Label3D
var _primary_action_btn: GlassButton3D


func initialize(p_state: JeopardyGameState, p_audio: EphemeralAudioManager) -> void:
	game_state = p_state
	audio = p_audio
	if not _bind_nodes():
		build_default_nodes(null)
		_bind_nodes()
	_wire_buttons()
	_connect_signals()
	_refresh_view()


func _connect_signals() -> void:
	game_state.phase_changed.connect(func(_n, _o) -> void: _refresh_view())
	game_state.teams_updated.connect(func(_t, _idx) -> void: _refresh_view())
	game_state.clue_started.connect(func(_p) -> void: _refresh_view())
	game_state.clue_resolved.connect(func(_r) -> void: _refresh_view())
	game_state.timer_updated.connect(_on_timer_updated)
	game_state.pack_changed.connect(func(_p) -> void: _refresh_view())


func _bind_nodes() -> bool:
	_header_label = get_node_or_null("HeaderLabel") as Label3D
	_main_label = get_node_or_null("MainLabel") as Label3D
	_sub_label = get_node_or_null("SubLabel") as Label3D
	_primary_action_btn = get_node_or_null("PrimaryActionBtn") as GlassButton3D
	var required: Array[Node] = [_header_label, _main_label, _sub_label, _primary_action_btn]
	return CenterWallStage.all_present(required)


func _wire_buttons() -> void:
	CenterWallStage.wire_button(self, "SwitchTeamBtn", func() -> void:
		audio.play_sfx("tap")
		game_state.cycle_active_team()
	)
	CenterWallStage.wire_button(self, "PrimaryActionBtn", _on_primary_action_tapped)


## Creates every missing stage node. Existing nodes are never touched, so manual edits survive.
## Pass the scene root as owner_root to make the nodes saveable; pass null for a code-only instance.
func build_default_nodes(owner_root: Node) -> void:
	CenterWallStage.ensure_label(
		self,
		owner_root,
		"HeaderLabel",
		"EPHEMERAL JEOPARDY  •  360° IMMERSIVE SANCTUARY",
		48,
		Color(0.86, 0.96, 1.0),
		Vector3(0.0, 1.30, 0.05),
		2100.0,
	)
	CenterWallStage.ensure_button(self, owner_root, "MirrorBackdrop", Vector3(0.0, 0.24, -0.02), {
		"panel_size": Vector3(5.90, 1.50, 0.08),
		"primary_text": "",
		"primary_font_size": 40,
		"base_color": Color(0.05, 0.11, 0.24, 0.88),
		"rim_color": Color(0.56, 0.72, 1.0, 1.0),
		"accent_color": Color(1.0, 0.84, 0.44, 1.0),
		"enable_idle_float": false,
		"interaction_enabled": false,
	})
	CenterWallStage.ensure_label(
		self,
		owner_root,
		"MainLabel",
		"EPHEMERAL WONDERS",
		58,
		Color(0.98, 0.99, 1.0),
		Vector3(0.0, 0.44, 0.08),
		1800.0,
	)
	CenterWallStage.ensure_label(
		self,
		owner_root,
		"SubLabel",
		"Face the Center Wall to configure teams & begin,\nor tap START right here.",
		38,
		Color(0.76, 0.90, 1.0),
		Vector3(0.0, -0.18, 0.08),
		1780.0,
	)
	CenterWallStage.ensure_button(self, owner_root, "SwitchTeamBtn", Vector3(-1.45, -0.96, 0.04), {
		"panel_size": Vector3(2.55, 0.46, 0.09),
		"primary_text": "SWITCH ACTIVE TEAM",
		"secondary_text": "BACK WALL BUZZ",
		"primary_font_size": 38,
		"base_color": Color(0.08, 0.15, 0.30, 0.90),
		"rim_color": Color(0.42, 0.90, 1.0, 1.0),
	})
	CenterWallStage.ensure_button(self, owner_root, "PrimaryActionBtn", Vector3(1.45, -0.96, 0.04), {
		"panel_size": Vector3(2.55, 0.46, 0.09),
		"primary_text": "START GAME",
		"secondary_text": "ILLUMINATE BOARD",
		"primary_font_size": 38,
		"base_color": Color(0.10, 0.21, 0.34, 0.92),
		"rim_color": Color(1.0, 0.84, 0.44, 1.0),
	})


func _on_primary_action_tapped() -> void:
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
