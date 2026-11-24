extends Node3D
class_name LeftWallStage

## Left Wall Projection Stage (-X, at (-4.0, 1.5, 0.0), rotated +90 deg Y).
## Hosts interactive Team Score Podiums (tap any podium to claim turn / buzz in)
## and single-touch Sanctuary Control Crystals (New Game, Mode, Pause/+10s, Mute, Final, Pack).
##
## All nodes live in LeftWallStage.tscn; the script binds to them and never moves hand-placed ones.

const MAX_TEAMS := 4
const PODIUM_HOME := Vector3(0.0, 0.36, 0.0)
const CONTROL_SIZE := Vector3(1.88, 0.40, 0.08)

## Re-centers the podium row for 1-3 teams while the podiums still sit at their default X spacing.
## Dragging any podium sideways in the editor (or turning this off) keeps every saved X exactly.
@export var auto_space_podiums: bool = true

var game_state: JeopardyGameState
var audio: EphemeralAudioManager

var _podium_buttons: Array[GlassButton3D] = []
var _podiums_hand_placed: bool = false
var _mode_btn: GlassButton3D
var _timer_pause_btn: GlassButton3D
var _mute_btn: GlassButton3D
var _pack_btn: GlassButton3D
var _status_label: Label3D


func initialize(p_state: JeopardyGameState, p_audio: EphemeralAudioManager) -> void:
	game_state = p_state
	audio = p_audio
	if not _bind_nodes():
		build_default_nodes(null)
		_bind_nodes()
	_wire_buttons()
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
	if game_state.has_signal(&"audio_mute_changed"):
		game_state.connect(&"audio_mute_changed", func(_m) -> void: _refresh_control_labels())


func _bind_nodes() -> bool:
	_status_label = get_node_or_null("StatusLabel") as Label3D
	_mode_btn = get_node_or_null("ModeButton") as GlassButton3D
	_pack_btn = get_node_or_null("PackButton") as GlassButton3D
	_timer_pause_btn = get_node_or_null("TimerPauseButton") as GlassButton3D
	_mute_btn = get_node_or_null("MuteButton") as GlassButton3D
	_podium_buttons = CenterWallStage.collect_buttons(self, "TeamPodium_%d", range(MAX_TEAMS))
	if _podium_buttons.size() != MAX_TEAMS:
		return false

	_podiums_hand_placed = false
	for i in range(MAX_TEAMS):
		if not is_equal_approx(_podium_buttons[i].position.x, _podium_x(i, MAX_TEAMS)):
			_podiums_hand_placed = true
	var required: Array[Node] = [_status_label, _mode_btn, _pack_btn, _timer_pause_btn, _mute_btn]
	return CenterWallStage.all_present(required)


func _wire_buttons() -> void:
	for i in range(MAX_TEAMS):
		CenterWallStage.wire_button(self, "TeamPodium_%d" % i, func() -> void:
			audio.play_sfx("tap", 0.05)
			game_state.set_active_team(i)
		)
	CenterWallStage.wire_button(self, "NewGameButton", func() -> void:
		audio.play_sfx("tap")
		game_state.start_new_game()
	)
	CenterWallStage.wire_button(self, "ModeButton", func() -> void:
		audio.play_sfx("tap")
		game_state.toggle_play_mode()
	)
	CenterWallStage.wire_button(self, "PackButton", func() -> void:
		audio.play_sfx("tap")
		game_state.cycle_pack()
	)
	CenterWallStage.wire_button(self, "TimerPauseButton", func() -> void:
		audio.play_sfx("tap")
		game_state.toggle_timer_pause()
	)
	CenterWallStage.wire_button(self, "MuteButton", _on_mute_tapped)
	CenterWallStage.wire_button(self, "FinalRoundButton", func() -> void:
		audio.play_sfx("daily_double", 0.02, -4.0)
		game_state.begin_final_jeopardy()
	)


func _on_mute_tapped() -> void:
	# Routed through the synced game state so a replica surface mutes the audio host.
	if game_state.has_method("toggle_audio_mute"):
		game_state.call("toggle_audio_mute")
	else:
		audio.toggle_mute()
	audio.play_sfx("tap")


func _is_audio_muted() -> bool:
	# Replica surfaces always mute their local audio manager, so only the synced flag is meaningful there.
	if game_state.is_replica and "audio_muted" in game_state:
		return bool(game_state.get("audio_muted"))
	return audio.is_muted


## Creates every missing stage node. Existing nodes are never touched, so manual edits survive.
## Pass the scene root as owner_root to make the nodes saveable; pass null for a code-only instance.
func build_default_nodes(owner_root: Node) -> void:
	CenterWallStage.ensure_label(
		self,
		owner_root,
		"PodiumTitle",
		"TEAM PODIUMS  •  TAP TO BUZZ / SELECT",
		48,
		Color(0.92, 0.98, 1.0),
		Vector3(0.0, 1.34, 0.05),
		2100.0,
	)
	CenterWallStage.ensure_label(
		self,
		owner_root,
		"StatusLabel",
		"EPHEMERAL WONDERS  •  25 / 25 CLUES REMAINING",
		30,
		Color(0.62, 0.88, 0.98),
		Vector3(0.0, 1.04, 0.05),
		2050.0,
	)

	# 4 Team Podium slots (shown based on team_count)
	for i in range(MAX_TEAMS):
		var preset: Dictionary = JeopardyGameState.TEAM_PRESETS[i]
		var col: Color = preset["color"]
		var pos := PODIUM_HOME + Vector3(_podium_x(i, MAX_TEAMS), 0.0, 0.0)
		CenterWallStage.ensure_button(self, owner_root, "TeamPodium_%d" % i, pos, {
			"panel_size": Vector3(1.45, 0.98, 0.09),
			"primary_text": ("★ " if i == 0 else "") + str(preset["name"]),
			"secondary_text": "$0",
			"primary_font_size": 46,
			"secondary_font_size": 44,
			"base_color": _podium_base_color(col, i == 0),
			"rim_color": col,
			"accent_color": Color(1.0, 0.88, 0.50),
			"text_color": Color(0.98, 0.99, 1.0),
			"highlight_amount": 1.05 if i == 0 else 0.0,
		})

	# Bottom 2 rows of Sanctuary Control Crystals (6 buttons, 3x2 grid)
	CenterWallStage.ensure_label(
		self,
		owner_root,
		"ControlsTitle",
		"SANCTUARY CONTROLS",
		30,
		Color(0.70, 0.85, 0.98),
		Vector3(0.0, -0.30, 0.05),
		1800.0,
	)
	_ensure_control(owner_root, "NewGameButton", Vector3(-2.05, -0.64, 0.0), {
		"primary_text": "NEW GAME",
		"secondary_text": "RESET BOARD",
		"base_color": Color(0.07, 0.18, 0.30, 0.90),
		"rim_color": Color(0.36, 0.92, 0.86, 1.0),
	})
	_ensure_control(owner_root, "ModeButton", Vector3(0.0, -0.64, 0.0), {
		"primary_text": "MODE: QUIZ",
		"secondary_text": "TAP TO SWITCH",
		"base_color": Color(0.09, 0.14, 0.30, 0.90),
		"rim_color": Color(0.76, 0.56, 1.0, 1.0),
	})
	_ensure_control(owner_root, "PackButton", Vector3(2.05, -0.64, 0.0), {
		"primary_text": "SWITCH PACK",
		"secondary_text": "EPHEMERAL WONDERS",
		"base_color": Color(0.08, 0.15, 0.30, 0.90),
		"rim_color": Color(1.0, 0.82, 0.42, 1.0),
	})
	_ensure_control(owner_root, "TimerPauseButton", Vector3(-2.05, -1.12, 0.0), {
		"primary_text": "PAUSE TIMER",
		"secondary_text": "+ HOLD MOMENT",
		"base_color": Color(0.07, 0.14, 0.28, 0.90),
		"rim_color": Color(0.42, 0.86, 1.0, 1.0),
	})
	_ensure_control(owner_root, "MuteButton", Vector3(0.0, -1.12, 0.0), {
		"primary_text": "AUDIO: ON",
		"secondary_text": "TAP TO TOGGLE",
		"base_color": Color(0.07, 0.14, 0.28, 0.90),
		"rim_color": Color(0.42, 0.86, 1.0, 1.0),
	})
	_ensure_control(owner_root, "FinalRoundButton", Vector3(2.05, -1.12, 0.0), {
		"primary_text": "FINAL ROUND",
		"secondary_text": "THE LAST ECHO",
		"base_color": Color(0.14, 0.11, 0.30, 0.90),
		"rim_color": Color(1.0, 0.78, 0.36, 1.0),
	})


func _ensure_control(owner_root: Node, node_name: String, pos: Vector3, props: Dictionary) -> void:
	var shared := {"panel_size": CONTROL_SIZE, "primary_font_size": 34}
	CenterWallStage.ensure_button(self, owner_root, node_name, pos, props.merged(shared))


func _podium_x(index: int, count: int) -> float:
	var spacing := 1.56 if count == 4 else (2.05 if count == 3 else 2.55)
	return (float(index) - 0.5 * float(count - 1)) * spacing


func _podium_base_color(col: Color, active: bool) -> Color:
	if active:
		return Color(col.r * 0.16, col.g * 0.18, col.b * 0.28, 0.92)
	return Color(0.06, 0.12, 0.25, 0.86)


func _refresh_podiums() -> void:
	var count := game_state.teams.size()
	var auto_space := auto_space_podiums and not _podiums_hand_placed

	for i in range(_podium_buttons.size()):
		var pod := _podium_buttons[i]
		if i >= count:
			pod.visible = false
			continue
		pod.visible = true
		if auto_space:
			pod.position.x = _podium_x(i, count)

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
		pod.set_palette(_podium_base_color(col, active), col, Color(1.0, 0.88, 0.50), Color(0.98, 0.99, 1.0))


func _refresh_control_labels() -> void:
	var mode_str := "QUIZ" if game_state.play_mode == JeopardyGameState.PlayMode.QUIZ else "HOST"
	_mode_btn.set_texts("MODE: %s" % mode_str, "TAP TO SWITCH")
	_timer_pause_btn.set_texts("RESUME TIMER" if game_state.timer_paused else "PAUSE TIMER", "+ HOLD MOMENT")
	_mute_btn.set_texts("AUDIO: MUTED" if _is_audio_muted() else "AUDIO: ON", "TAP TO TOGGLE")
	if game_state.current_pack != null:
		_pack_btn.set_texts("SWITCH PACK", game_state.current_pack.title.to_upper())
		_status_label.text = "%s  •  %d / %d CLUES REMAINING" % [
			game_state.current_pack.title.to_upper(),
			game_state.remaining_tiles,
			game_state.total_tiles,
		]
