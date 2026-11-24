extends Node3D
class_name CenterWallStage

## Primary interactive projection stage on the Center Wall (-Z, at (0, 1.5, -4.0)).
## Hosts Setup Lobby, 5x5 Ephemeral Jeopardy Board, Wager Stage, Active Clue / Result,
## and Grand Finale monoliths, all strictly framed inside the 16:9 safe frustum.

const GLASS_SHADER_PATH := "res://shaders/glass_tile.gdshader"

var game_state: JeopardyGameState
var audio: EphemeralAudioManager

var _setup_group: Node3D
var _board_group: Node3D
var _wager_group: Node3D
var _clue_group: Node3D
var _finale_group: Node3D

# Setup controls
var _setup_pack_btn: GlassButton3D
var _setup_pack_desc: Label3D
var _setup_team_btns: Array[GlassButton3D] = []
var _setup_mode_btn: GlassButton3D
var _setup_start_btn: GlassButton3D

# Board elements
var _board_banner: Label3D
var _category_headers: Array[GlassButton3D] = []
var _tiles: Dictionary = {}  # "c_r" -> JeopardyTile3D

# Wager elements
var _wager_title: Label3D
var _wager_subtitle: Label3D
var _wager_amount_label: Label3D
var _wager_range_label: Label3D
var _wager_lock_btn: GlassButton3D

# Clue & Result elements
var _clue_header_label: Label3D
var _clue_timer_bar_bg: MeshInstance3D
var _clue_timer_bar_fill: MeshInstance3D
var _clue_timer_fill_mat: StandardMaterial3D
var _clue_timer_text: Label3D
var _clue_card_panel: GlassButton3D
var _clue_text_label: Label3D
var _quiz_buttons_root: Node3D
var _choice_buttons: Array[GlassButton3D] = []
var _host_buttons_root: Node3D
var _host_reveal_btn: GlassButton3D
var _host_answer_label: Label3D
var _host_judge_root: Node3D
var _result_root: Node3D
var _result_outcome_label: Label3D
var _result_answer_label: Label3D
var _result_fact_label: Label3D
var _result_continue_btn: GlassButton3D

# Finale elements
var _finale_winner_label: Label3D
var _finale_scores_label: Label3D
var _finale_play_again_btn: GlassButton3D
var _finale_setup_btn: GlassButton3D


func initialize(p_state: JeopardyGameState, p_audio: EphemeralAudioManager) -> void:
	game_state = p_state
	audio = p_audio
	_build_setup_group()
	_build_board_group()
	_build_wager_group()
	_build_clue_group()
	_build_finale_group()
	_connect_signals()
	_refresh_setup_ui()
	_rebuild_board_for_pack(game_state.current_pack)
	_sync_phase_visibility(game_state.phase)


func _connect_signals() -> void:
	game_state.phase_changed.connect(_on_phase_changed)
	game_state.pack_changed.connect(_on_pack_changed)
	game_state.teams_updated.connect(_on_teams_updated)
	game_state.play_mode_changed.connect(_on_play_mode_changed)
	game_state.board_reset.connect(_on_board_reset)
	game_state.tile_cleared.connect(_on_tile_cleared)
	game_state.wager_updated.connect(_on_wager_updated)
	game_state.clue_started.connect(_on_clue_started)
	game_state.host_answer_revealed.connect(_on_host_answer_revealed)
	game_state.clue_resolved.connect(_on_clue_resolved)
	game_state.timer_updated.connect(_on_timer_updated)
	game_state.game_finished.connect(_on_game_finished)


# ------------------------------------------------------------------------------
# SETUP LOBBY
# ------------------------------------------------------------------------------
func _build_setup_group() -> void:
	_setup_group = Node3D.new()
	_setup_group.name = "SetupGroup"
	add_child(_setup_group)

	var title := _make_label("EPHEMERAL JEOPARDY", 98, Color(0.95, 0.99, 1.0), Vector3(0.0, 1.24, 0.05), 2200.0)
	_setup_group.add_child(title)

	var tagline := _make_label(
		"SINGLE-TOUCH 360° SANCTUARY  •  TAP ANY LUMINOUS MONOLITH",
		32,
		Color(0.56, 0.88, 0.98),
		Vector3(0.0, 0.93, 0.05),
		2200.0,
	)
	_setup_group.add_child(tagline)

	# Pack selector crystal
	_setup_pack_btn = GlassButton3D.new()
	_setup_pack_btn.name = "PackSelectorButton"
	_setup_pack_btn.position = Vector3(0.0, 0.42, 0.0)
	_setup_pack_btn.configure(
		Vector3(5.6, 0.56, 0.09),
		"PACK: EPHEMERAL WONDERS",
		"TAP TO SWITCH QUESTION PACK",
		52,
		Color(0.06, 0.14, 0.29, 0.90),
		Color(0.36, 0.88, 1.0, 1.0),
		Color(1.0, 0.84, 0.44, 1.0),
	)
	_setup_pack_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("tap")
		game_state.cycle_pack()
	)
	_setup_group.add_child(_setup_pack_btn)

	_setup_pack_desc = _make_label("", 32, Color(0.80, 0.90, 0.98), Vector3(0.0, 0.02, 0.05), 1850.0)
	_setup_group.add_child(_setup_pack_desc)

	# Team count selector (1..4)
	var team_lbl := _make_label("PLAYERS / TEAMS", 28, Color(0.68, 0.86, 0.96), Vector3(-1.45, -0.26, 0.05), 900.0)
	_setup_group.add_child(team_lbl)

	_setup_team_btns.clear()
	for count in range(1, 5):
		var btn := GlassButton3D.new()
		btn.name = "TeamCount_%d" % count
		var x_pos := -2.65 + float(count - 1) * 0.80
		btn.position = Vector3(x_pos, -0.58, 0.0)
		var sub := "SOLO" if count == 1 else "TEAMS"
		btn.configure(
			Vector3(0.70, 0.42, 0.08),
			str(count),
			sub,
			46,
			Color(0.06, 0.13, 0.26, 0.88),
			Color(0.36, 0.85, 1.0, 1.0),
		)
		var c_val := count
		btn.tapped.connect(func(_b, _p, _v) -> void:
			audio.play_sfx("tap")
			game_state.set_team_count(c_val)
		)
		_setup_group.add_child(btn)
		_setup_team_btns.append(btn)

	# Play mode toggle (Quiz vs Host)
	var mode_lbl := _make_label("INTERACTION MODE", 28, Color(0.68, 0.86, 0.96), Vector3(1.60, -0.26, 0.05), 950.0)
	_setup_group.add_child(mode_lbl)

	_setup_mode_btn = GlassButton3D.new()
	_setup_mode_btn.name = "ModeToggleButton"
	_setup_mode_btn.position = Vector3(1.60, -0.58, 0.0)
	_setup_mode_btn.configure(
		Vector3(2.85, 0.42, 0.08),
		"SINGLE-TOUCH QUIZ",
		"4 ANSWER CARDS • TAP TO SWITCH",
		36,
		Color(0.09, 0.14, 0.30, 0.88),
		Color(0.72, 0.56, 1.0, 1.0),
	)
	_setup_mode_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("tap")
		game_state.toggle_play_mode()
	)
	_setup_group.add_child(_setup_mode_btn)

	# Big luminous BEGIN monolith
	_setup_start_btn = GlassButton3D.new()
	_setup_start_btn.name = "BeginGameButton"
	_setup_start_btn.position = Vector3(0.0, -1.16, 0.06)
	_setup_start_btn.configure(
		Vector3(3.40, 0.50, 0.10),
		"ENTER THE SANCTUARY",
		"TAP TO ILLUMINATE THE BOARD",
		48,
		Color(0.08, 0.24, 0.34, 0.92),
		Color(0.98, 0.84, 0.44, 1.0),
		Color(0.36, 0.96, 0.88, 1.0),
	)
	_setup_start_btn.set_highlighted(true, 0.65)
	_setup_start_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("daily_double", 0.02, -3.0)
		game_state.start_new_game()
	)
	_setup_group.add_child(_setup_start_btn)


func _refresh_setup_ui() -> void:
	if game_state.current_pack != null:
		var pack := game_state.current_pack
		_setup_pack_btn.set_texts(
			"PACK: %s" % pack.title.to_upper(),
			"TAP TO CYCLE (%d / %d)" % [game_state.current_pack_index + 1, max(1, game_state.packs.size())],
		)
		_setup_pack_btn.set_palette(Color(0.06, 0.14, 0.29, 0.90), pack.accent_color, Color(1.0, 0.84, 0.44))
		_setup_pack_desc.text = pack.subtitle

	for i in range(_setup_team_btns.size()):
		var selected := (i + 1) == game_state.team_count
		var btn := _setup_team_btns[i]
		btn.set_highlighted(selected, 1.0)
		if selected:
			btn.set_palette(Color(0.11, 0.27, 0.39, 0.92), Color(1.0, 0.84, 0.44), Color(0.4, 0.95, 1.0))
		else:
			btn.set_palette(Color(0.06, 0.13, 0.26, 0.85), Color(0.32, 0.78, 0.95), Color(1.0, 0.84, 0.44))

	if game_state.play_mode == JeopardyGameState.PlayMode.QUIZ:
		_setup_mode_btn.set_texts("SINGLE-TOUCH QUIZ", "4 ANSWER CARDS • TAP TO SWITCH")
	else:
		_setup_mode_btn.set_texts("LIVE HOST REVEAL", "ORAL ANSWERS • TAP TO SWITCH")


# ------------------------------------------------------------------------------
# 5x5 JEOPARDY BOARD
# ------------------------------------------------------------------------------
func _build_board_group() -> void:
	_board_group = Node3D.new()
	_board_group.name = "BoardGroup"
	add_child(_board_group)

	_board_banner = _make_label(
		"EPHEMERAL WONDERS  •  SELECT A MONOLITH",
		40,
		Color(0.92, 0.97, 1.0),
		Vector3(0.0, 1.40, 0.04),
		2150.0,
	)
	_board_group.add_child(_board_banner)


func _rebuild_board_for_pack(pack: JeopardyPack) -> void:
	if pack == null:
		return
	for hdr in _category_headers:
		if is_instance_valid(hdr):
			hdr.queue_free()
	_category_headers.clear()

	for tile in _tiles.values():
		if is_instance_valid(tile):
			tile.queue_free()
	_tiles.clear()

	var cols := pack.get_category_count()
	var rows := pack.get_row_count()
	var col_step := 1.29
	var x_start := -0.5 * float(cols - 1) * col_step

	for c in range(cols):
		var cat: Dictionary = pack.categories[c]
		var x_pos := x_start + float(c) * col_step

		# Category header glass plaque (non-interactive)
		var hdr := GlassButton3D.new()
		hdr.name = "CategoryHeader_%d" % c
		hdr.position = Vector3(x_pos, 0.99, 0.0)
		var short_name := str(cat.get("short_name", cat.get("name", "CAT")))
		hdr.configure(
			Vector3(1.18, 0.39, 0.07),
			short_name.to_upper(),
			"",
			36,
			Color(0.09, 0.17, 0.34, 0.92),
			pack.accent_color,
			Color(1.0, 0.84, 0.44),
		)
		hdr.enable_idle_float = false
		hdr.set_interactable_active(false)
		_board_group.add_child(hdr)
		_category_headers.append(hdr)

		var clues: Array = cat.get("clues", [])
		for r in range(rows):
			var clue: Dictionary = clues[r]
			var val := int(clue.get("value", (r + 1) * 200))
			var y_pos := 0.51 - float(r) * 0.43

			var tile := JeopardyTile3D.new()
			tile.name = "Tile_%d_%d" % [c, r]
			tile.position = Vector3(x_pos, y_pos, 0.0)
			tile.setup_tile(c, r, val, pack.accent_color)
			tile.tile_tapped.connect(_on_tile_tapped)
			_board_group.add_child(tile)
			_tiles["%d_%d" % [c, r]] = tile

	_update_board_banner()


func _update_board_banner() -> void:
	if _board_banner == null or game_state.current_pack == null:
		return
	var team_name := "EXPLORER"
	if game_state.active_team_index < game_state.teams.size():
		team_name = str(game_state.teams[game_state.active_team_index]["name"])
	_board_banner.text = "%s  •  %s CHOOSES  •  %d/%d REMAINING" % [
		game_state.current_pack.title.to_upper(),
		team_name,
		game_state.remaining_tiles,
		game_state.total_tiles,
	]


func _on_tile_tapped(cat_idx: int, row_idx: int, _tile: JeopardyTile3D) -> void:
	if game_state.phase != JeopardyGameState.Phase.BOARD:
		return
	audio.play_sfx("dissolve")
	game_state.select_tile(cat_idx, row_idx)


# ------------------------------------------------------------------------------
# WAGER STAGE (DAILY DOUBLE & FINAL JEOPARDY)
# ------------------------------------------------------------------------------
func _build_wager_group() -> void:
	_wager_group = Node3D.new()
	_wager_group.name = "WagerGroup"
	add_child(_wager_group)

	_wager_title = _make_label(
		"EPHEMERAL SURGE • DAILY DOUBLE",
		70,
		Color(1.0, 0.86, 0.45),
		Vector3(0.0, 1.24, 0.05),
		2150.0,
	)
	_wager_group.add_child(_wager_title)

	_wager_subtitle = _make_label(
		"AURORA — CHOOSE YOUR WAGER",
		40,
		Color(0.76, 0.94, 1.0),
		Vector3(0.0, 0.88, 0.05),
		2100.0,
	)
	_wager_group.add_child(_wager_subtitle)

	var display_backdrop := GlassButton3D.new()
	display_backdrop.name = "WagerBackdrop"
	display_backdrop.position = Vector3(0.0, 0.36, -0.02)
	display_backdrop.configure(
		Vector3(3.4, 0.66, 0.08),
		"",
		"",
		40,
		Color(0.11, 0.08, 0.26, 0.90),
		Color(1.0, 0.78, 0.36, 1.0),
	)
	display_backdrop.enable_idle_float = false
	display_backdrop.set_interactable_active(false)
	_wager_group.add_child(display_backdrop)

	_wager_amount_label = _make_label("$500", 112, Color(1.0, 0.94, 0.68), Vector3(0.0, 0.42, 0.08), 1600.0)
	_wager_group.add_child(_wager_amount_label)

	_wager_range_label = _make_label(
		"MIN $200  •  MAX $1000",
		28,
		Color(0.75, 0.86, 0.96),
		Vector3(0.0, 0.12, 0.08),
		1600.0,
	)
	_wager_group.add_child(_wager_range_label)

	# Quick preset fraction crystals
	var presets := [
		{"label": "25%", "frac": 0.25, "x": -2.25},
		{"label": "50%", "frac": 0.50, "x": -0.75},
		{"label": "75%", "frac": 0.75, "x": 0.75},
		{"label": "ALL IN", "frac": 1.00, "x": 2.25},
	]
	for p in presets:
		var btn := GlassButton3D.new()
		btn.position = Vector3(float(p["x"]), -0.34, 0.0)
		btn.configure(
			Vector3(1.32, 0.42, 0.08),
			str(p["label"]),
			"",
			46,
			Color(0.10, 0.14, 0.32, 0.90),
			Color(0.84, 0.56, 1.0, 1.0),
			Color(1.0, 0.84, 0.44, 1.0),
		)
		var frac := float(p["frac"])
		btn.tapped.connect(func(_b, _pos, _v) -> void:
			audio.play_sfx("tap")
			game_state.set_wager_fraction(frac)
		)
		_wager_group.add_child(btn)

	# Fine +/- $200 & LOCK WAGER row
	var minus_btn := GlassButton3D.new()
	minus_btn.position = Vector3(-2.15, -0.96, 0.0)
	minus_btn.configure(
		Vector3(1.30, 0.48, 0.08),
		"- $200",
		"",
		46,
		Color(0.14, 0.11, 0.26, 0.90),
		Color(0.55, 0.78, 1.0, 1.0),
	)
	minus_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("tap", 0.05)
		game_state.adjust_wager(-200)
	)
	_wager_group.add_child(minus_btn)

	_wager_lock_btn = GlassButton3D.new()
	_wager_lock_btn.name = "LockWagerButton"
	_wager_lock_btn.position = Vector3(0.0, -0.96, 0.06)
	_wager_lock_btn.configure(
		Vector3(2.65, 0.52, 0.10),
		"LOCK WAGER",
		"REVEAL CLUE",
		48,
		Color(0.16, 0.24, 0.34, 0.92),
		Color(1.0, 0.84, 0.42, 1.0),
	)
	_wager_lock_btn.set_highlighted(true, 0.7)
	_wager_lock_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("dissolve")
		game_state.lock_wager()
	)
	_wager_group.add_child(_wager_lock_btn)

	var plus_btn := GlassButton3D.new()
	plus_btn.position = Vector3(2.15, -0.96, 0.0)
	plus_btn.configure(
		Vector3(1.30, 0.48, 0.08),
		"+ $200",
		"",
		46,
		Color(0.14, 0.11, 0.26, 0.90),
		Color(0.55, 0.78, 1.0, 1.0),
	)
	plus_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("tap", 0.05)
		game_state.adjust_wager(200)
	)
	_wager_group.add_child(plus_btn)


# ------------------------------------------------------------------------------
# ACTIVE CLUE & RESULT STAGE
# ------------------------------------------------------------------------------
func _build_clue_group() -> void:
	_clue_group = Node3D.new()
	_clue_group.name = "ClueGroup"
	add_child(_clue_group)

	_clue_header_label = _make_label(
		"CATEGORY  •  $400",
		46,
		Color(1.0, 0.86, 0.48),
		Vector3(0.0, 1.36, 0.05),
		2150.0,
	)
	_clue_group.add_child(_clue_header_label)

	# Ephemeral countdown bar
	var bg_mesh := BoxMesh.new()
	bg_mesh.size = Vector3(5.6, 0.065, 0.03)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.albedo_color = Color(0.12, 0.20, 0.34, 0.55)
	bg_mesh.material = bg_mat
	_clue_timer_bar_bg = MeshInstance3D.new()
	_clue_timer_bar_bg.mesh = bg_mesh
	_clue_timer_bar_bg.position = Vector3(0.0, 1.12, 0.0)
	_clue_group.add_child(_clue_timer_bar_bg)

	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(5.6, 0.068, 0.04)
	_clue_timer_fill_mat = StandardMaterial3D.new()
	_clue_timer_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_clue_timer_fill_mat.albedo_color = Color(0.32, 0.90, 1.0, 1.0)
	fill_mesh.material = _clue_timer_fill_mat
	_clue_timer_bar_fill = MeshInstance3D.new()
	_clue_timer_bar_fill.mesh = fill_mesh
	_clue_timer_bar_fill.position = Vector3(0.0, 1.12, 0.015)
	_clue_group.add_child(_clue_timer_bar_fill)

	_clue_timer_text = _make_label("25s", 30, Color(0.75, 0.94, 1.0), Vector3(3.05, 1.12, 0.05), 300.0)
	_clue_group.add_child(_clue_timer_text)

	# Floating frosted glass clue slab
	_clue_card_panel = GlassButton3D.new()
	_clue_card_panel.name = "ClueMonolithBackdrop"
	_clue_card_panel.position = Vector3(0.0, 0.48, -0.02)
	_clue_card_panel.configure(
		Vector3(6.25, 1.00, 0.08),
		"",
		"",
		40,
		Color(0.05, 0.11, 0.24, 0.90),
		Color(0.38, 0.88, 1.0, 1.0),
		Color(1.0, 0.84, 0.44, 1.0),
	)
	_clue_card_panel.enable_idle_float = false
	_clue_card_panel.set_interactable_active(false)
	_clue_group.add_child(_clue_card_panel)

	_clue_text_label = _make_label("", 60, Color(0.97, 0.99, 1.0), Vector3(0.0, 0.48, 0.08), 1820.0)
	_clue_group.add_child(_clue_text_label)

	# --- Quiz Mode: 4 Large Single-Touch Answer Cards ---
	_quiz_buttons_root = Node3D.new()
	_quiz_buttons_root.name = "QuizChoices"
	_clue_group.add_child(_quiz_buttons_root)

	_choice_buttons.clear()
	var choice_coords := [
		Vector3(-1.58, -0.34, 0.04),
		Vector3(1.58, -0.34, 0.04),
		Vector3(-1.58, -0.94, 0.04),
		Vector3(1.58, -0.94, 0.04),
	]
	var choice_letters := ["A", "B", "C", "D"]
	for i in range(4):
		var btn := GlassButton3D.new()
		btn.name = "Choice_%s" % choice_letters[i]
		btn.position = choice_coords[i]
		btn.configure(
			Vector3(2.96, 0.48, 0.09),
			"%s) Option" % choice_letters[i],
			"",
			44,
			Color(0.07, 0.15, 0.30, 0.90),
			Color(0.36, 0.86, 1.0, 1.0),
			Color(1.0, 0.84, 0.44, 1.0),
		)
		var idx := i
		btn.tapped.connect(func(_b, _p, _v) -> void:
			audio.play_sfx("tap")
			game_state.submit_choice(idx)
		)
		_quiz_buttons_root.add_child(btn)
		_choice_buttons.append(btn)

	# --- Host Mode: Reveal + Judge Controls ---
	_host_buttons_root = Node3D.new()
	_host_buttons_root.name = "HostControls"
	_clue_group.add_child(_host_buttons_root)

	_host_reveal_btn = GlassButton3D.new()
	_host_reveal_btn.position = Vector3(0.0, -0.46, 0.05)
	_host_reveal_btn.configure(
		Vector3(3.40, 0.50, 0.09),
		"REVEAL ANSWER",
		"HOST MODE • SINGLE TAP",
		48,
		Color(0.09, 0.18, 0.34, 0.92),
		Color(1.0, 0.84, 0.44, 1.0),
	)
	_host_reveal_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("tap")
		game_state.reveal_host_answer()
	)
	_host_buttons_root.add_child(_host_reveal_btn)

	_host_answer_label = _make_label("", 52, Color(1.0, 0.92, 0.62), Vector3(0.0, -0.34, 0.06), 1950.0)
	_host_answer_label.visible = false
	_host_buttons_root.add_child(_host_answer_label)

	_host_judge_root = Node3D.new()
	_host_judge_root.visible = false
	_host_buttons_root.add_child(_host_judge_root)

	var correct_btn := GlassButton3D.new()
	correct_btn.position = Vector3(-2.05, -0.96, 0.04)
	correct_btn.configure(
		Vector3(1.85, 0.46, 0.09),
		"CORRECT",
		"+ POINTS",
		42,
		Color(0.06, 0.24, 0.18, 0.92),
		Color(0.32, 0.96, 0.68, 1.0),
	)
	correct_btn.tapped.connect(func(_b, _p, _v) -> void:
		game_state.submit_host_judgment(true, false)
	)
	_host_judge_root.add_child(correct_btn)

	var pass_btn := GlassButton3D.new()
	pass_btn.position = Vector3(0.0, -0.96, 0.04)
	pass_btn.configure(
		Vector3(1.85, 0.46, 0.09),
		"PASS / SKIP",
		"NO PENALTY",
		40,
		Color(0.11, 0.15, 0.28, 0.90),
		Color(0.62, 0.80, 0.96, 1.0),
	)
	pass_btn.tapped.connect(func(_b, _p, _v) -> void:
		game_state.submit_host_judgment(false, true)
	)
	_host_judge_root.add_child(pass_btn)

	var wrong_btn := GlassButton3D.new()
	wrong_btn.position = Vector3(2.05, -0.96, 0.04)
	wrong_btn.configure(
		Vector3(1.85, 0.46, 0.09),
		"INCORRECT",
		"- POINTS",
		42,
		Color(0.26, 0.09, 0.16, 0.92),
		Color(1.0, 0.45, 0.58, 1.0),
	)
	wrong_btn.tapped.connect(func(_b, _p, _v) -> void:
		game_state.submit_host_judgment(false, false)
	)
	_host_judge_root.add_child(wrong_btn)

	# --- Result Overlay ---
	_result_root = Node3D.new()
	_result_root.name = "ResultOverlay"
	_clue_group.add_child(_result_root)

	_result_outcome_label = _make_label("CORRECT! +$400", 66, Color(0.42, 0.98, 0.74), Vector3(0.0, -0.18, 0.08), 1950.0)
	_result_root.add_child(_result_outcome_label)

	_result_answer_label = _make_label(
		"What is Refraction?",
		46,
		Color(1.0, 0.92, 0.64),
		Vector3(0.0, -0.47, 0.08),
		1950.0,
	)
	_result_root.add_child(_result_answer_label)

	_result_fact_label = _make_label("", 32, Color(0.80, 0.90, 0.98), Vector3(0.0, -0.71, 0.08), 1920.0)
	_result_root.add_child(_result_fact_label)

	_result_continue_btn = GlassButton3D.new()
	_result_continue_btn.name = "ContinueButton"
	_result_continue_btn.position = Vector3(0.0, -1.14, 0.06)
	_result_continue_btn.configure(
		Vector3(3.15, 0.44, 0.09),
		"RETURN TO BOARD",
		"",
		44,
		Color(0.08, 0.21, 0.34, 0.92),
		Color(0.42, 0.92, 1.0, 1.0),
		Color(1.0, 0.84, 0.44, 1.0),
	)
	_result_continue_btn.set_highlighted(true, 0.6)
	_result_continue_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("tap")
		game_state.continue_after_result()
	)
	_result_root.add_child(_result_continue_btn)


# ------------------------------------------------------------------------------
# FINALE STAGE
# ------------------------------------------------------------------------------
func _build_finale_group() -> void:
	_finale_group = Node3D.new()
	_finale_group.name = "FinaleGroup"
	add_child(_finale_group)

	var header := _make_label("THE SANCTUARY REMEMBERS", 72, Color(1.0, 0.88, 0.50), Vector3(0.0, 1.24, 0.05), 2150.0)
	_finale_group.add_child(header)

	var panel := GlassButton3D.new()
	panel.position = Vector3(0.0, 0.22, -0.02)
	panel.configure(
		Vector3(5.8, 1.48, 0.08),
		"",
		"",
		40,
		Color(0.07, 0.12, 0.26, 0.90),
		Color(1.0, 0.84, 0.44, 1.0),
	)
	panel.enable_idle_float = false
	panel.set_interactable_active(false)
	_finale_group.add_child(panel)

	_finale_winner_label = _make_label("AURORA PREVAILS!", 66, Color(0.44, 0.98, 0.82), Vector3(0.0, 0.62, 0.08), 1850.0)
	_finale_group.add_child(_finale_winner_label)

	_finale_scores_label = _make_label("", 42, Color(0.94, 0.97, 1.0), Vector3(0.0, -0.02, 0.08), 1850.0)
	_finale_group.add_child(_finale_scores_label)

	_finale_play_again_btn = GlassButton3D.new()
	_finale_play_again_btn.position = Vector3(-1.45, -0.98, 0.05)
	_finale_play_again_btn.configure(
		Vector3(2.55, 0.50, 0.10),
		"PLAY AGAIN",
		"FRESH BOARD",
		46,
		Color(0.08, 0.24, 0.34, 0.92),
		Color(0.38, 0.96, 0.84, 1.0),
	)
	_finale_play_again_btn.set_highlighted(true, 0.7)
	_finale_play_again_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("daily_double", 0.02, -3.0)
		game_state.start_new_game()
	)
	_finale_group.add_child(_finale_play_again_btn)

	_finale_setup_btn = GlassButton3D.new()
	_finale_setup_btn.position = Vector3(1.45, -0.98, 0.05)
	_finale_setup_btn.configure(
		Vector3(2.55, 0.50, 0.10),
		"CHANGE PACK",
		"RETURN TO LOBBY",
		44,
		Color(0.10, 0.14, 0.30, 0.90),
		Color(0.84, 0.62, 1.0, 1.0),
	)
	_finale_setup_btn.tapped.connect(func(_b, _p, _v) -> void:
		audio.play_sfx("tap")
		game_state.return_to_setup()
	)
	_finale_group.add_child(_finale_setup_btn)


# ------------------------------------------------------------------------------
# SIGNAL HANDLERS
# ------------------------------------------------------------------------------
func _sync_phase_visibility(p: int) -> void:
	_setup_group.visible = (p == JeopardyGameState.Phase.SETUP)
	_board_group.visible = (p == JeopardyGameState.Phase.BOARD)
	_wager_group.visible = (
		p == JeopardyGameState.Phase.DAILY_DOUBLE_WAGER
		or p == JeopardyGameState.Phase.FINAL_WAGER
	)
	_clue_group.visible = (
		p == JeopardyGameState.Phase.CLUE_ACTIVE
		or p == JeopardyGameState.Phase.FINAL_CLUE
		or p == JeopardyGameState.Phase.CLUE_RESULT
	)
	_finale_group.visible = (p == JeopardyGameState.Phase.GAME_OVER)


func _on_phase_changed(new_phase: int, _old_phase: int) -> void:
	_sync_phase_visibility(new_phase)
	if new_phase == JeopardyGameState.Phase.SETUP:
		_refresh_setup_ui()
	elif new_phase == JeopardyGameState.Phase.BOARD:
		_update_board_banner()
	elif new_phase == JeopardyGameState.Phase.DAILY_DOUBLE_WAGER:
		var team: Dictionary = game_state.teams[game_state.active_team_index]
		_wager_title.text = "EPHEMERAL SURGE  •  DAILY DOUBLE"
		_wager_subtitle.text = "%s — CHOOSE YOUR WAGER" % str(team["name"])
		_wager_lock_btn.set_texts("LOCK WAGER", "REVEAL CLUE")
	elif new_phase == JeopardyGameState.Phase.FINAL_WAGER:
		var team: Dictionary = game_state.teams[game_state.active_team_index]
		var cat := str(game_state.active_clue.get("category", "THE LAST ECHO"))
		_wager_title.text = "FINAL JEOPARDY  •  %s" % cat.to_upper()
		_wager_subtitle.text = "%s — LOCK YOUR FINAL WAGER" % str(team["name"])
		var more := game_state.final_wager_team_cursor < game_state.teams.size() - 1
		_wager_lock_btn.set_texts("LOCK WAGER", "NEXT TEAM" if more else "REVEAL FINAL CLUE")


func _on_pack_changed(pack: JeopardyPack) -> void:
	_refresh_setup_ui()
	_rebuild_board_for_pack(pack)


func _on_teams_updated(_teams: Array[Dictionary], _active_idx: int) -> void:
	_refresh_setup_ui()
	_update_board_banner()


func _on_play_mode_changed(_mode: int) -> void:
	_refresh_setup_ui()
	if game_state.phase == JeopardyGameState.Phase.CLUE_ACTIVE or game_state.phase == JeopardyGameState.Phase.FINAL_CLUE:
		_sync_clue_input_mode()


func _on_board_reset(pack: JeopardyPack) -> void:
	_rebuild_board_for_pack(pack)


func _on_tile_cleared(cat_idx: int, row_idx: int, was_correct: bool) -> void:
	var key := "%d_%d" % [cat_idx, row_idx]
	if _tiles.has(key):
		(_tiles[key] as JeopardyTile3D).play_dissolve_to_ghost(was_correct)
	_update_board_banner()


func _on_wager_updated(current_w: int, min_w: int, max_w: int) -> void:
	_wager_amount_label.text = "$%d" % current_w
	_wager_range_label.text = "MIN $%d  •  MAX $%d" % [min_w, max_w]


func _on_clue_started(payload: Dictionary) -> void:
	var prefix := ""
	if bool(payload.get("is_final", false)):
		prefix = "FINAL JEOPARDY  •  "
	elif bool(payload.get("is_daily_double", false)):
		prefix = "DAILY DOUBLE  •  "
	_clue_header_label.text = "%s%s  •  $%d" % [
		prefix,
		str(payload.get("category", "")).to_upper(),
		int(payload.get("value", 0)),
	]
	_clue_text_label.text = str(payload.get("clue", ""))

	var choices: Array = payload.get("choices", [])
	var letters := ["A", "B", "C", "D"]
	for i in range(4):
		var txt := "%s) %s" % [letters[i], str(choices[i]) if i < choices.size() else ""]
		_choice_buttons[i].set_texts(txt)
		_choice_buttons[i].set_palette(
			Color(0.07, 0.15, 0.30, 0.90),
			Color(0.36, 0.86, 1.0, 1.0),
			Color(1.0, 0.84, 0.44, 1.0),
		)
		_choice_buttons[i].set_highlighted(false)

	_host_reveal_btn.visible = true
	_host_answer_label.visible = false
	_host_judge_root.visible = false
	_result_root.visible = false
	_sync_clue_input_mode()


func _sync_clue_input_mode() -> void:
	var is_quiz := game_state.play_mode == JeopardyGameState.PlayMode.QUIZ
	_quiz_buttons_root.visible = is_quiz
	_host_buttons_root.visible = not is_quiz


func _on_host_answer_revealed(answer_text: String) -> void:
	_host_reveal_btn.visible = false
	_host_answer_label.text = answer_text
	_host_answer_label.visible = true
	_host_judge_root.visible = true


func _on_clue_resolved(res: Dictionary) -> void:
	_quiz_buttons_root.visible = false
	_host_buttons_root.visible = false
	_result_root.visible = true

	var was_correct := bool(res.get("was_correct", false))
	var delta := int(res.get("score_delta", 0))
	var team_name := str(res.get("team_name", ""))
	if was_correct:
		_result_outcome_label.text = "%s  •  CORRECT!  +%s" % [team_name, EphemeralTheme.format_money(delta)]
		_result_outcome_label.modulate = Color(0.38, 0.98, 0.72)
	elif bool(res.get("is_pass", false)):
		_result_outcome_label.text = "%s  •  PASSED  •  NO SCORE CHANGE" % team_name
		_result_outcome_label.modulate = Color(0.84, 0.78, 1.0)
	elif bool(res.get("timed_out", false)) and delta == 0:
		_result_outcome_label.text = "THE MOMENT PASSED  •  NO SCORE CHANGE"
		_result_outcome_label.modulate = Color(0.84, 0.78, 1.0)
	else:
		_result_outcome_label.text = "%s  •  %s  -%s" % [
			team_name,
			str(res.get("outcome", "INCORRECT")),
			EphemeralTheme.format_money(abs(delta)),
		]
		_result_outcome_label.modulate = Color(1.0, 0.50, 0.62)

	_result_answer_label.text = str(res.get("answer", ""))
	_result_fact_label.text = str(res.get("fact", ""))

	if bool(res.get("is_final", false)):
		var more_final := game_state.final_answer_team_cursor < game_state.teams.size() - 1
		_result_continue_btn.set_texts(
			"NEXT TEAM'S FINAL ANSWER" if more_final else "VIEW FINAL STANDINGS",
			"",
		)
	elif game_state.remaining_tiles <= 0:
		_result_continue_btn.set_texts("ENTER FINAL JEOPARDY", "")
	else:
		_result_continue_btn.set_texts("RETURN TO BOARD", "")


func _on_timer_updated(remaining: float, total: float, paused: bool) -> void:
	var ratio := clampf(remaining / maxf(total, 0.01), 0.0, 1.0)
	_clue_timer_bar_fill.scale.x = maxf(ratio, 0.002)
	if ratio > 0.45:
		_clue_timer_fill_mat.albedo_color = Color(0.32, 0.90, 1.0, 1.0)
	elif ratio > 0.22:
		_clue_timer_fill_mat.albedo_color = Color(1.0, 0.80, 0.34, 1.0)
	else:
		_clue_timer_fill_mat.albedo_color = Color(1.0, 0.36, 0.48, 1.0)
	_clue_timer_text.text = "PAUSED" if paused else "%ds" % int(ceil(remaining))


func _on_game_finished(standings: Array[Dictionary]) -> void:
	if standings.is_empty():
		return
	var winner: Dictionary = standings[0]
	if standings.size() > 1 and int(standings[0]["score"]) == int(standings[1]["score"]):
		_finale_winner_label.text = "A RADIANT TIE!"
	else:
		_finale_winner_label.text = "%s PREVAILS!  %s" % [
			str(winner["name"]),
			EphemeralTheme.format_money(int(winner["score"])),
		]

	var lines: Array[String] = []
	for i in range(standings.size()):
		var t: Dictionary = standings[i]
		lines.append("#%d  %s  —  %s   (%d correct, best streak %d)" % [
			i + 1,
			str(t["name"]),
			EphemeralTheme.format_money(int(t["score"])),
			int(t["correct"]),
			int(t["best_streak"]),
		])
	_finale_scores_label.text = "\n".join(lines)


static func _make_label(
	text: String,
	font_size: int,
	color: Color,
	pos: Vector3,
	wrap_width: float,
	use_display_font: bool = false,
) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = font_size
	lbl.font = EphemeralTheme.get_display_font() if (use_display_font or font_size >= 64) else EphemeralTheme.get_ui_font()
	lbl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	lbl.render_priority = 4
	lbl.pixel_size = 0.0032
	lbl.modulate = color
	lbl.outline_size = 10
	lbl.outline_modulate = Color(0.02, 0.04, 0.10, 0.92)
	lbl.position = pos
	lbl.width = wrap_width
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.double_sided = false
	return lbl
