@tool
extends Node3D
class_name CenterWallStage

## Primary interactive projection stage on the Center Wall (-Z, at (0, 1.5, -4.0)).
## Hosts Setup Lobby, 5x5 Ephemeral Jeopardy Board, Wager Stage, Active Clue / Result,
## and Grand Finale monoliths, all strictly framed inside the 16:9 safe frustum.
##
## All nodes live in CenterWallStage.tscn. At runtime the stage binds to them by path and only updates
## game-driven text/color/visibility, so positions and panel sizes edited in the Godot Editor are kept.

enum PreviewScreen { BOARD, SETUP, WAGER, CLUE_QUIZ, CLUE_HOST, RESULT, FINALE }

const DEFAULT_PACK_PATH := "res://data/packs/ephemeral_wonders.json"
const BOARD_GRID := Vector2i(5, 5)
const COL_STEP := 1.29
const ROW_STEP := 0.43
const CHOICE_LETTERS := ["A", "B", "C", "D"]
const WAGER_PRESETS := [
	{"name": "WagerPreset_25", "label": "25%", "frac": 0.25, "x": -2.25},
	{"name": "WagerPreset_50", "label": "50%", "frac": 0.50, "x": -0.75},
	{"name": "WagerPreset_75", "label": "75%", "frac": 0.75, "x": 0.75},
	{"name": "WagerPreset_AllIn", "label": "ALL IN", "frac": 1.00, "x": 2.25},
]

## Editor only: which screen is shown while you edit. Play Mode always follows the game phase.
@export_enum(
	"Board (5x5)",
	"Setup Lobby",
	"Daily Double Wager",
	"Active Clue (Quiz)",
	"Active Clue (Host)",
	"Clue Result",
	"Finale",
)
var editor_preview_screen: int = 0:
	set(value):
		editor_preview_screen = value
		if Engine.is_editor_hint() and is_inside_tree():
			apply_preview_screen()

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

# Board elements
var _board_banner: Label3D
var _category_headers: Array[GlassButton3D] = []
var _tiles: Dictionary = {}  # "c_r" -> JeopardyTile3D (tiles in play for the current pack)
var _dynamic_board: Node3D = null  # Only used by packs that are not 5x5
var _scene_board_hidden: bool = false

# Wager elements
var _wager_title: Label3D
var _wager_subtitle: Label3D
var _wager_amount_label: Label3D
var _wager_range_label: Label3D
var _wager_lock_btn: GlassButton3D

# Clue & Result elements
var _clue_header_label: Label3D
var _clue_timer_bar_fill: MeshInstance3D
var _clue_timer_fill_mat: StandardMaterial3D
var _clue_timer_fill_base_scale: float = 1.0
var _clue_timer_text: Label3D
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


func _ready() -> void:
	if Engine.is_editor_hint():
		apply_preview_screen()


func initialize(p_state: JeopardyGameState, p_audio: EphemeralAudioManager) -> void:
	game_state = p_state
	audio = p_audio
	if not _bind_nodes():
		build_default_nodes(null)
		_bind_nodes()
	_wire_buttons()
	_connect_signals()
	_refresh_setup_ui()
	_rebuild_board_for_pack(game_state.current_pack)
	_reset_clue_overlays()
	_sync_phase_visibility(game_state.phase)


## Creates every missing stage node. Existing nodes are never touched, so manual edits survive.
## Pass the scene root as owner_root to make the nodes saveable; pass null for a code-only instance.
func build_default_nodes(owner_root: Node) -> void:
	var pack := JeopardyPack.load_from_file(DEFAULT_PACK_PATH)
	_build_setup_group(owner_root, pack)
	_build_board_group(owner_root, pack)
	_build_wager_group(owner_root)
	_build_clue_group(owner_root, pack)
	_build_finale_group(owner_root)


## Shows exactly one screen (and, for clue screens, one sub-panel) without overlapping the others.
func apply_preview_screen() -> void:
	var screen := editor_preview_screen
	var is_clue := (
		screen == PreviewScreen.CLUE_QUIZ
		or screen == PreviewScreen.CLUE_HOST
		or screen == PreviewScreen.RESULT
	)
	set_child_visible(self, "SetupGroup", screen == PreviewScreen.SETUP)
	set_child_visible(self, "BoardGroup", screen == PreviewScreen.BOARD)
	set_child_visible(self, "WagerGroup", screen == PreviewScreen.WAGER)
	set_child_visible(self, "ClueGroup", is_clue)
	set_child_visible(self, "FinaleGroup", screen == PreviewScreen.FINALE)
	set_child_visible(self, "ClueGroup/QuizChoices", screen == PreviewScreen.CLUE_QUIZ)
	set_child_visible(self, "ClueGroup/HostControls", screen == PreviewScreen.CLUE_HOST)
	set_child_visible(self, "ClueGroup/ResultOverlay", screen == PreviewScreen.RESULT)


func _bind_nodes() -> bool:
	_setup_group = get_node_or_null("SetupGroup") as Node3D
	_setup_pack_btn = get_node_or_null("SetupGroup/PackSelectorButton") as GlassButton3D
	_setup_pack_desc = get_node_or_null("SetupGroup/PackDescription") as Label3D
	_setup_mode_btn = get_node_or_null("SetupGroup/ModeToggleButton") as GlassButton3D
	_setup_team_btns = collect_buttons(self, "SetupGroup/TeamCount_%d", range(1, 5))

	_board_group = get_node_or_null("BoardGroup") as Node3D
	_board_banner = get_node_or_null("BoardGroup/BoardBanner") as Label3D

	_wager_group = get_node_or_null("WagerGroup") as Node3D
	_wager_title = get_node_or_null("WagerGroup/WagerTitle") as Label3D
	_wager_subtitle = get_node_or_null("WagerGroup/WagerSubtitle") as Label3D
	_wager_amount_label = get_node_or_null("WagerGroup/WagerAmount") as Label3D
	_wager_range_label = get_node_or_null("WagerGroup/WagerRange") as Label3D
	_wager_lock_btn = get_node_or_null("WagerGroup/LockWagerButton") as GlassButton3D

	_clue_group = get_node_or_null("ClueGroup") as Node3D
	_clue_header_label = get_node_or_null("ClueGroup/ClueHeader") as Label3D
	_clue_timer_bar_fill = get_node_or_null("ClueGroup/ClueTimerBarFill") as MeshInstance3D
	_clue_timer_text = get_node_or_null("ClueGroup/ClueTimerText") as Label3D
	_clue_text_label = get_node_or_null("ClueGroup/ClueText") as Label3D
	_quiz_buttons_root = get_node_or_null("ClueGroup/QuizChoices") as Node3D
	_choice_buttons = collect_buttons(self, "ClueGroup/QuizChoices/Choice_%s", CHOICE_LETTERS)
	_host_buttons_root = get_node_or_null("ClueGroup/HostControls") as Node3D
	_host_reveal_btn = get_node_or_null("ClueGroup/HostControls/RevealAnswerButton") as GlassButton3D
	_host_answer_label = get_node_or_null("ClueGroup/HostControls/HostAnswer") as Label3D
	_host_judge_root = get_node_or_null("ClueGroup/HostControls/JudgeControls") as Node3D
	_result_root = get_node_or_null("ClueGroup/ResultOverlay") as Node3D
	_result_outcome_label = get_node_or_null("ClueGroup/ResultOverlay/ResultOutcome") as Label3D
	_result_answer_label = get_node_or_null("ClueGroup/ResultOverlay/ResultAnswer") as Label3D
	_result_fact_label = get_node_or_null("ClueGroup/ResultOverlay/ResultFact") as Label3D
	_result_continue_btn = get_node_or_null("ClueGroup/ResultOverlay/ContinueButton") as GlassButton3D
	if _clue_timer_bar_fill != null:
		_clue_timer_fill_mat = _clue_timer_bar_fill.get_active_material(0) as StandardMaterial3D
		_clue_timer_fill_base_scale = _clue_timer_bar_fill.scale.x

	_finale_group = get_node_or_null("FinaleGroup") as Node3D
	_finale_winner_label = get_node_or_null("FinaleGroup/FinaleWinner") as Label3D
	_finale_scores_label = get_node_or_null("FinaleGroup/FinaleScores") as Label3D

	if _setup_team_btns.size() != 4 or _choice_buttons.size() != 4:
		return false
	var required: Array[Node] = [
		_setup_group, _setup_pack_btn, _setup_pack_desc, _setup_mode_btn,
		_board_group, _board_banner,
		_wager_group, _wager_title, _wager_subtitle, _wager_amount_label, _wager_range_label, _wager_lock_btn,
		_clue_group, _clue_header_label, _clue_timer_bar_fill, _clue_timer_text, _clue_text_label,
		_quiz_buttons_root, _host_buttons_root, _host_reveal_btn, _host_answer_label, _host_judge_root,
		_result_root, _result_outcome_label, _result_answer_label, _result_fact_label, _result_continue_btn,
		_finale_group, _finale_winner_label, _finale_scores_label,
	]
	return all_present(required)


func _wire_buttons() -> void:
	wire_button(self, "SetupGroup/PackSelectorButton", func() -> void:
		audio.play_sfx("tap")
		game_state.cycle_pack()
	)
	for count in range(1, 5):
		wire_button(self, "SetupGroup/TeamCount_%d" % count, func() -> void:
			audio.play_sfx("tap")
			game_state.set_team_count(count)
		)
	wire_button(self, "SetupGroup/ModeToggleButton", func() -> void:
		audio.play_sfx("tap")
		game_state.toggle_play_mode()
	)
	wire_button(self, "SetupGroup/BeginGameButton", func() -> void:
		audio.play_sfx("daily_double", 0.02, -3.0)
		game_state.start_new_game()
	)

	for preset: Dictionary in WAGER_PRESETS:
		var frac := float(preset["frac"])
		wire_button(self, "WagerGroup/%s" % preset["name"], func() -> void:
			audio.play_sfx("tap")
			game_state.set_wager_fraction(frac)
		)
	wire_button(self, "WagerGroup/WagerMinusButton", func() -> void:
		audio.play_sfx("tap", 0.05)
		game_state.adjust_wager(-200)
	)
	wire_button(self, "WagerGroup/WagerPlusButton", func() -> void:
		audio.play_sfx("tap", 0.05)
		game_state.adjust_wager(200)
	)
	wire_button(self, "WagerGroup/LockWagerButton", func() -> void:
		audio.play_sfx("dissolve")
		game_state.lock_wager()
	)

	for i in range(CHOICE_LETTERS.size()):
		wire_button(self, "ClueGroup/QuizChoices/Choice_%s" % CHOICE_LETTERS[i], func() -> void:
			audio.play_sfx("tap")
			game_state.submit_choice(i)
		)
	wire_button(self, "ClueGroup/HostControls/RevealAnswerButton", func() -> void:
		audio.play_sfx("tap")
		game_state.reveal_host_answer()
	)
	var judge := "ClueGroup/HostControls/JudgeControls/"
	wire_button(self, judge + "JudgeCorrectButton", func() -> void:
		game_state.submit_host_judgment(true, false)
	)
	wire_button(self, judge + "JudgePassButton", func() -> void:
		game_state.submit_host_judgment(false, true)
	)
	wire_button(self, judge + "JudgeIncorrectButton", func() -> void:
		game_state.submit_host_judgment(false, false)
	)
	wire_button(self, "ClueGroup/ResultOverlay/ContinueButton", func() -> void:
		audio.play_sfx("tap")
		game_state.continue_after_result()
	)

	wire_button(self, "FinaleGroup/PlayAgainButton", func() -> void:
		audio.play_sfx("daily_double", 0.02, -3.0)
		game_state.start_new_game()
	)
	wire_button(self, "FinaleGroup/ChangePackButton", func() -> void:
		audio.play_sfx("tap")
		game_state.return_to_setup()
	)


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
func _build_setup_group(owner_root: Node, pack: JeopardyPack) -> void:
	var group := ensure_group(self, owner_root, "SetupGroup", false)
	ensure_label(
		group,
		owner_root,
		"SetupTitle",
		"EPHEMERAL JEOPARDY",
		98,
		Color(0.95, 0.99, 1.0),
		Vector3(0.0, 1.24, 0.05),
		2200.0,
	)
	ensure_label(
		group,
		owner_root,
		"SetupTagline",
		"SINGLE-TOUCH 360° SANCTUARY  •  TAP ANY LUMINOUS MONOLITH",
		32,
		Color(0.56, 0.88, 0.98),
		Vector3(0.0, 0.93, 0.05),
		2200.0,
	)

	# Pack selector crystal
	ensure_button(group, owner_root, "PackSelectorButton", Vector3(0.0, 0.42, 0.0), {
		"panel_size": Vector3(5.6, 0.56, 0.09),
		"primary_text": "PACK: EPHEMERAL WONDERS",
		"secondary_text": "TAP TO SWITCH QUESTION PACK",
		"primary_font_size": 52,
		"base_color": Color(0.06, 0.14, 0.29, 0.90),
		"rim_color": pack.accent_color if pack != null else Color(0.36, 0.88, 1.0, 1.0),
		"accent_color": Color(1.0, 0.84, 0.44, 1.0),
	})
	ensure_label(
		group,
		owner_root,
		"PackDescription",
		pack.subtitle if pack != null else "",
		32,
		Color(0.80, 0.90, 0.98),
		Vector3(0.0, 0.02, 0.05),
		1850.0,
	)

	# Team count selector (1..4)
	ensure_label(
		group,
		owner_root,
		"TeamsLabel",
		"PLAYERS / TEAMS",
		28,
		Color(0.68, 0.86, 0.96),
		Vector3(-1.45, -0.26, 0.05),
		900.0,
	)
	for count in range(1, 5):
		var selected := count == 2
		ensure_button(group, owner_root, "TeamCount_%d" % count, Vector3(-3.45 + float(count) * 0.80, -0.58, 0.0), {
			"panel_size": Vector3(0.70, 0.42, 0.08),
			"primary_text": str(count),
			"secondary_text": "SOLO" if count == 1 else "TEAMS",
			"primary_font_size": 46,
			"base_color": Color(0.11, 0.27, 0.39, 0.92) if selected else Color(0.06, 0.13, 0.26, 0.85),
			"rim_color": Color(1.0, 0.84, 0.44) if selected else Color(0.32, 0.78, 0.95),
			"accent_color": Color(0.4, 0.95, 1.0) if selected else Color(1.0, 0.84, 0.44),
			"highlight_amount": 1.0 if selected else 0.0,
		})

	# Play mode toggle (Quiz vs Host)
	ensure_label(
		group,
		owner_root,
		"ModeLabel",
		"INTERACTION MODE",
		28,
		Color(0.68, 0.86, 0.96),
		Vector3(1.60, -0.26, 0.05),
		950.0,
	)
	ensure_button(group, owner_root, "ModeToggleButton", Vector3(1.60, -0.58, 0.0), {
		"panel_size": Vector3(2.85, 0.42, 0.08),
		"primary_text": "SINGLE-TOUCH QUIZ",
		"secondary_text": "4 ANSWER CARDS • TAP TO SWITCH",
		"primary_font_size": 36,
		"base_color": Color(0.09, 0.14, 0.30, 0.88),
		"rim_color": Color(0.72, 0.56, 1.0, 1.0),
	})

	# Big luminous BEGIN monolith
	ensure_button(group, owner_root, "BeginGameButton", Vector3(0.0, -1.16, 0.06), {
		"panel_size": Vector3(3.40, 0.50, 0.10),
		"primary_text": "ENTER THE SANCTUARY",
		"secondary_text": "TAP TO ILLUMINATE THE BOARD",
		"primary_font_size": 48,
		"base_color": Color(0.08, 0.24, 0.34, 0.92),
		"rim_color": Color(0.98, 0.84, 0.44, 1.0),
		"accent_color": Color(0.36, 0.96, 0.88, 1.0),
		"highlight_amount": 0.65,
	})


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
func _build_board_group(owner_root: Node, pack: JeopardyPack) -> void:
	var group := ensure_group(self, owner_root, "BoardGroup", true)
	ensure_label(
		group,
		owner_root,
		"BoardBanner",
		"EPHEMERAL WONDERS  •  SELECT A MONOLITH",
		40,
		Color(0.92, 0.97, 1.0),
		Vector3(0.0, 1.40, 0.04),
		2150.0,
	)
	if pack != null:
		_ensure_board_grid(group, owner_root, pack, BOARD_GRID)


## Creates any missing header/tile of a cols x rows grid under `parent` at its default coordinates.
func _ensure_board_grid(parent: Node3D, owner_root: Node, pack: JeopardyPack, grid: Vector2i) -> void:
	var x_start := -0.5 * float(grid.x - 1) * COL_STEP
	for c in range(grid.x):
		var x_pos := x_start + float(c) * COL_STEP

		# Category header glass plaque (non-interactive)
		ensure_button(parent, owner_root, "CategoryHeader_%d" % c, Vector3(x_pos, 0.99, 0.0), {
			"panel_size": Vector3(1.18, 0.39, 0.07),
			"primary_text": _header_text(pack, c),
			"primary_font_size": 36,
			"base_color": Color(0.09, 0.17, 0.34, 0.92),
			"rim_color": pack.accent_color,
			"accent_color": Color(1.0, 0.84, 0.44),
			"enable_idle_float": false,
			"interaction_enabled": false,
		})

		for r in range(grid.y):
			var tile_name := "Tile_%d_%d" % [c, r]
			if parent.has_node(tile_name):
				continue
			var tile := JeopardyTile3D.new()
			tile.position = Vector3(x_pos, 0.51 - float(r) * ROW_STEP, 0.0)
			tile.set_meta(&"_edit_group_", true)
			tile.setup_tile(c, r, _tile_value(pack, c, r), pack.accent_color)
			_adopt(parent, owner_root, tile, tile_name)


func _header_text(pack: JeopardyPack, c: int) -> String:
	if c >= pack.categories.size():
		return "CATEGORY"
	var cat: Dictionary = pack.categories[c]
	return str(cat.get("short_name", cat.get("name", "CAT"))).to_upper()


func _tile_value(pack: JeopardyPack, c: int, r: int) -> int:
	return int(pack.get_clue(c, r).get("value", (r + 1) * 200))


func _rebuild_board_for_pack(pack: JeopardyPack) -> void:
	if pack == null:
		return
	var grid := Vector2i(pack.get_category_count(), pack.get_row_count())
	var board_parent := _board_group

	if _dynamic_board != null:
		_dynamic_board.queue_free()
		_dynamic_board = null
	if grid == BOARD_GRID:
		# The authored 5x5 tiles are updated in place; only tiles deleted from the scene get created.
		_set_scene_board_hidden(false)
	else:
		_set_scene_board_hidden(true)
		_dynamic_board = Node3D.new()
		_board_group.add_child(_dynamic_board)
		board_parent = _dynamic_board
	_ensure_board_grid(board_parent, null, pack, grid)

	_category_headers.clear()
	_tiles.clear()
	for c in range(grid.x):
		var hdr := board_parent.get_node("CategoryHeader_%d" % c) as GlassButton3D
		hdr.set_texts(_header_text(pack, c))
		hdr.rim_color = pack.accent_color
		_category_headers.append(hdr)

		for r in range(grid.y):
			var tile := board_parent.get_node("Tile_%d_%d" % [c, r]) as JeopardyTile3D
			tile.apply_clue_data(c, r, _tile_value(pack, c, r), pack.accent_color)
			if not tile.tile_tapped.is_connected(_on_tile_tapped):
				tile.tile_tapped.connect(_on_tile_tapped)
			_tiles["%d_%d" % [c, r]] = tile

	_update_board_banner()


## Non-5x5 packs hide (never free) the authored board so switching back restores it exactly.
func _set_scene_board_hidden(hidden: bool) -> void:
	if hidden == _scene_board_hidden:
		return
	_scene_board_hidden = hidden
	for c in range(BOARD_GRID.x):
		set_child_visible(_board_group, "CategoryHeader_%d" % c, not hidden)
		for r in range(BOARD_GRID.y):
			set_child_visible(_board_group, "Tile_%d_%d" % [c, r], not hidden)


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
func _build_wager_group(owner_root: Node) -> void:
	var group := ensure_group(self, owner_root, "WagerGroup", false)
	ensure_label(
		group,
		owner_root,
		"WagerTitle",
		"EPHEMERAL SURGE • DAILY DOUBLE",
		70,
		Color(1.0, 0.86, 0.45),
		Vector3(0.0, 1.24, 0.05),
		2150.0,
	)
	ensure_label(
		group,
		owner_root,
		"WagerSubtitle",
		"AURORA — CHOOSE YOUR WAGER",
		40,
		Color(0.76, 0.94, 1.0),
		Vector3(0.0, 0.88, 0.05),
		2100.0,
	)
	ensure_button(group, owner_root, "WagerBackdrop", Vector3(0.0, 0.36, -0.02), {
		"panel_size": Vector3(3.4, 0.66, 0.08),
		"primary_text": "",
		"primary_font_size": 40,
		"base_color": Color(0.11, 0.08, 0.26, 0.90),
		"rim_color": Color(1.0, 0.78, 0.36, 1.0),
		"enable_idle_float": false,
		"interaction_enabled": false,
	})
	ensure_label(
		group,
		owner_root,
		"WagerAmount",
		"$500",
		112,
		Color(1.0, 0.94, 0.68),
		Vector3(0.0, 0.42, 0.08),
		1600.0,
	)
	ensure_label(
		group,
		owner_root,
		"WagerRange",
		"MIN $200  •  MAX $1000",
		28,
		Color(0.75, 0.86, 0.96),
		Vector3(0.0, 0.12, 0.08),
		1600.0,
	)

	# Quick preset fraction crystals
	for preset: Dictionary in WAGER_PRESETS:
		ensure_button(group, owner_root, str(preset["name"]), Vector3(float(preset["x"]), -0.34, 0.0), {
			"panel_size": Vector3(1.32, 0.42, 0.08),
			"primary_text": str(preset["label"]),
			"primary_font_size": 46,
			"base_color": Color(0.10, 0.14, 0.32, 0.90),
			"rim_color": Color(0.84, 0.56, 1.0, 1.0),
			"accent_color": Color(1.0, 0.84, 0.44, 1.0),
		})

	# Fine +/- $200 & LOCK WAGER row
	var step_props := {
		"panel_size": Vector3(1.30, 0.48, 0.08),
		"primary_font_size": 46,
		"base_color": Color(0.14, 0.11, 0.26, 0.90),
		"rim_color": Color(0.55, 0.78, 1.0, 1.0),
	}
	var minus_props := step_props.merged({"primary_text": "- $200"})
	var plus_props := step_props.merged({"primary_text": "+ $200"})
	ensure_button(group, owner_root, "WagerMinusButton", Vector3(-2.15, -0.96, 0.0), minus_props)
	ensure_button(group, owner_root, "LockWagerButton", Vector3(0.0, -0.96, 0.06), {
		"panel_size": Vector3(2.65, 0.52, 0.10),
		"primary_text": "LOCK WAGER",
		"secondary_text": "REVEAL CLUE",
		"primary_font_size": 48,
		"base_color": Color(0.16, 0.24, 0.34, 0.92),
		"rim_color": Color(1.0, 0.84, 0.42, 1.0),
		"highlight_amount": 0.7,
	})
	ensure_button(group, owner_root, "WagerPlusButton", Vector3(2.15, -0.96, 0.0), plus_props)


# ------------------------------------------------------------------------------
# ACTIVE CLUE & RESULT STAGE
# ------------------------------------------------------------------------------
func _build_clue_group(owner_root: Node, pack: JeopardyPack) -> void:
	var sample: Dictionary = pack.get_clue(0, 0) if pack != null else {}
	var sample_category := str(pack.categories[0].get("name", "CATEGORY")) if pack != null else "CATEGORY"
	var group := ensure_group(self, owner_root, "ClueGroup", false)
	ensure_label(
		group,
		owner_root,
		"ClueHeader",
		"%s  •  $%d" % [sample_category.to_upper(), int(sample.get("value", 400))],
		46,
		Color(1.0, 0.86, 0.48),
		Vector3(0.0, 1.36, 0.05),
		2150.0,
	)

	# Ephemeral countdown bar
	if not group.has_node("ClueTimerBarBg"):
		var bg_mat := StandardMaterial3D.new()
		bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bg_mat.albedo_color = Color(0.12, 0.20, 0.34, 0.55)
		var bg := _make_bar(Vector3(5.6, 0.065, 0.03), bg_mat)
		bg.position = Vector3(0.0, 1.12, 0.0)
		_adopt(group, owner_root, bg, "ClueTimerBarBg")
	if not group.has_node("ClueTimerBarFill"):
		var fill_mat := StandardMaterial3D.new()
		fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fill_mat.albedo_color = Color(0.32, 0.90, 1.0, 1.0)
		var fill := _make_bar(Vector3(5.6, 0.068, 0.04), fill_mat)
		fill.position = Vector3(0.0, 1.12, 0.015)
		_adopt(group, owner_root, fill, "ClueTimerBarFill")
	ensure_label(
		group,
		owner_root,
		"ClueTimerText",
		"25s",
		30,
		Color(0.75, 0.94, 1.0),
		Vector3(3.05, 1.12, 0.05),
		300.0,
	)

	# Floating frosted glass clue slab
	ensure_button(group, owner_root, "ClueMonolithBackdrop", Vector3(0.0, 0.48, -0.02), {
		"panel_size": Vector3(6.25, 1.00, 0.08),
		"primary_text": "",
		"primary_font_size": 40,
		"base_color": Color(0.05, 0.11, 0.24, 0.90),
		"rim_color": Color(0.38, 0.88, 1.0, 1.0),
		"accent_color": Color(1.0, 0.84, 0.44, 1.0),
		"enable_idle_float": false,
		"interaction_enabled": false,
	})
	ensure_label(
		group,
		owner_root,
		"ClueText",
		str(sample.get("clue", "")),
		60,
		Color(0.97, 0.99, 1.0),
		Vector3(0.0, 0.48, 0.08),
		1820.0,
	)
	_build_quiz_choices(group, owner_root, sample)
	_build_host_controls(group, owner_root, sample)
	_build_result_overlay(group, owner_root, sample)


## Quiz Mode: 4 large single-touch answer cards.
func _build_quiz_choices(clue_group: Node3D, owner_root: Node, sample: Dictionary) -> void:
	var group := ensure_group(clue_group, owner_root, "QuizChoices", false)
	var choice_coords := [
		Vector3(-1.58, -0.34, 0.04),
		Vector3(1.58, -0.34, 0.04),
		Vector3(-1.58, -0.94, 0.04),
		Vector3(1.58, -0.94, 0.04),
	]
	var choices: Array = sample.get("choices", [])
	for i in range(CHOICE_LETTERS.size()):
		var answer := str(choices[i]) if i < choices.size() else "Option"
		ensure_button(group, owner_root, "Choice_%s" % CHOICE_LETTERS[i], choice_coords[i], {
			"panel_size": Vector3(2.96, 0.48, 0.09),
			"primary_text": "%s) %s" % [CHOICE_LETTERS[i], answer],
			"primary_font_size": 44,
			"base_color": Color(0.07, 0.15, 0.30, 0.90),
			"rim_color": Color(0.36, 0.86, 1.0, 1.0),
			"accent_color": Color(1.0, 0.84, 0.44, 1.0),
		})


## Host Mode: reveal + judge controls.
func _build_host_controls(clue_group: Node3D, owner_root: Node, sample: Dictionary) -> void:
	var group := ensure_group(clue_group, owner_root, "HostControls", false)
	ensure_button(group, owner_root, "RevealAnswerButton", Vector3(0.0, -0.46, 0.05), {
		"panel_size": Vector3(3.40, 0.50, 0.09),
		"primary_text": "REVEAL ANSWER",
		"secondary_text": "HOST MODE • SINGLE TAP",
		"primary_font_size": 48,
		"base_color": Color(0.09, 0.18, 0.34, 0.92),
		"rim_color": Color(1.0, 0.84, 0.44, 1.0),
	})
	if not group.has_node("HostAnswer"):
		# Saved hidden because it replaces the Reveal button in place once the host taps it.
		var answer := ensure_label(
			group,
			owner_root,
			"HostAnswer",
			str(sample.get("answer", "")),
			52,
			Color(1.0, 0.92, 0.62),
			Vector3(0.0, -0.34, 0.06),
			1950.0,
		)
		answer.visible = false

	var judge := ensure_group(group, owner_root, "JudgeControls", true)
	ensure_button(judge, owner_root, "JudgeCorrectButton", Vector3(-2.05, -0.96, 0.04), {
		"panel_size": Vector3(1.85, 0.46, 0.09),
		"primary_text": "CORRECT",
		"secondary_text": "+ POINTS",
		"primary_font_size": 42,
		"base_color": Color(0.06, 0.24, 0.18, 0.92),
		"rim_color": Color(0.32, 0.96, 0.68, 1.0),
	})
	ensure_button(judge, owner_root, "JudgePassButton", Vector3(0.0, -0.96, 0.04), {
		"panel_size": Vector3(1.85, 0.46, 0.09),
		"primary_text": "PASS / SKIP",
		"secondary_text": "NO PENALTY",
		"primary_font_size": 40,
		"base_color": Color(0.11, 0.15, 0.28, 0.90),
		"rim_color": Color(0.62, 0.80, 0.96, 1.0),
	})
	ensure_button(judge, owner_root, "JudgeIncorrectButton", Vector3(2.05, -0.96, 0.04), {
		"panel_size": Vector3(1.85, 0.46, 0.09),
		"primary_text": "INCORRECT",
		"secondary_text": "- POINTS",
		"primary_font_size": 42,
		"base_color": Color(0.26, 0.09, 0.16, 0.92),
		"rim_color": Color(1.0, 0.45, 0.58, 1.0),
	})


func _build_result_overlay(clue_group: Node3D, owner_root: Node, sample: Dictionary) -> void:
	var group := ensure_group(clue_group, owner_root, "ResultOverlay", false)
	ensure_label(
		group,
		owner_root,
		"ResultOutcome",
		"AURORA  •  CORRECT!  +$200",
		66,
		Color(0.42, 0.98, 0.74),
		Vector3(0.0, -0.18, 0.08),
		1950.0,
	)
	ensure_label(
		group,
		owner_root,
		"ResultAnswer",
		str(sample.get("answer", "What is Refraction?")),
		46,
		Color(1.0, 0.92, 0.64),
		Vector3(0.0, -0.47, 0.08),
		1950.0,
	)
	ensure_label(
		group,
		owner_root,
		"ResultFact",
		str(sample.get("fact", "")),
		32,
		Color(0.80, 0.90, 0.98),
		Vector3(0.0, -0.71, 0.08),
		1920.0,
	)
	ensure_button(group, owner_root, "ContinueButton", Vector3(0.0, -1.14, 0.06), {
		"panel_size": Vector3(3.15, 0.44, 0.09),
		"primary_text": "RETURN TO BOARD",
		"primary_font_size": 44,
		"base_color": Color(0.08, 0.21, 0.34, 0.92),
		"rim_color": Color(0.42, 0.92, 1.0, 1.0),
		"accent_color": Color(1.0, 0.84, 0.44, 1.0),
		"highlight_amount": 0.6,
	})


# ------------------------------------------------------------------------------
# FINALE STAGE
# ------------------------------------------------------------------------------
func _build_finale_group(owner_root: Node) -> void:
	var group := ensure_group(self, owner_root, "FinaleGroup", false)
	ensure_label(
		group,
		owner_root,
		"FinaleHeader",
		"THE SANCTUARY REMEMBERS",
		72,
		Color(1.0, 0.88, 0.50),
		Vector3(0.0, 1.24, 0.05),
		2150.0,
	)
	ensure_button(group, owner_root, "FinaleBackdrop", Vector3(0.0, 0.22, -0.02), {
		"panel_size": Vector3(5.8, 1.48, 0.08),
		"primary_text": "",
		"primary_font_size": 40,
		"base_color": Color(0.07, 0.12, 0.26, 0.90),
		"rim_color": Color(1.0, 0.84, 0.44, 1.0),
		"enable_idle_float": false,
		"interaction_enabled": false,
	})
	ensure_label(
		group,
		owner_root,
		"FinaleWinner",
		"AURORA PREVAILS!  $9400",
		66,
		Color(0.44, 0.98, 0.82),
		Vector3(0.0, 0.62, 0.08),
		1850.0,
	)
	ensure_label(
		group,
		owner_root,
		"FinaleScores",
		"#1  AURORA  —  $9400   (14 correct, best streak 5)\n#2  SOLARIS  —  $6200   (9 correct, best streak 3)",
		42,
		Color(0.94, 0.97, 1.0),
		Vector3(0.0, -0.02, 0.08),
		1850.0,
	)
	ensure_button(group, owner_root, "PlayAgainButton", Vector3(-1.45, -0.98, 0.05), {
		"panel_size": Vector3(2.55, 0.50, 0.10),
		"primary_text": "PLAY AGAIN",
		"secondary_text": "FRESH BOARD",
		"primary_font_size": 46,
		"base_color": Color(0.08, 0.24, 0.34, 0.92),
		"rim_color": Color(0.38, 0.96, 0.84, 1.0),
		"highlight_amount": 0.7,
	})
	ensure_button(group, owner_root, "ChangePackButton", Vector3(1.45, -0.98, 0.05), {
		"panel_size": Vector3(2.55, 0.50, 0.10),
		"primary_text": "CHANGE PACK",
		"secondary_text": "RETURN TO LOBBY",
		"primary_font_size": 44,
		"base_color": Color(0.10, 0.14, 0.30, 0.90),
		"rim_color": Color(0.84, 0.62, 1.0, 1.0),
	})


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
	for i in range(4):
		var txt := "%s) %s" % [CHOICE_LETTERS[i], str(choices[i]) if i < choices.size() else ""]
		_choice_buttons[i].set_texts(txt)
		_choice_buttons[i].set_palette(
			Color(0.07, 0.15, 0.30, 0.90),
			Color(0.36, 0.86, 1.0, 1.0),
			Color(1.0, 0.84, 0.44, 1.0),
		)
		_choice_buttons[i].set_highlighted(false)

	_reset_clue_overlays()


func _reset_clue_overlays() -> void:
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
	_clue_timer_bar_fill.scale.x = _clue_timer_fill_base_scale * maxf(ratio, 0.002)
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


# ------------------------------------------------------------------------------
# SHARED SCENE BUILDERS (also used by the Left/Right/Back/Floor stages)
# The ensure_* helpers return an existing child untouched, or create it with the given defaults.
# ------------------------------------------------------------------------------
static func ensure_group(parent: Node, owner_root: Node, node_name: String, shown: bool) -> Node3D:
	var group := parent.get_node_or_null(node_name) as Node3D
	if group == null:
		group = Node3D.new()
		group.visible = shown
		_adopt(parent, owner_root, group, node_name)
	return group


static func ensure_button(
	parent: Node,
	owner_root: Node,
	node_name: String,
	pos: Vector3,
	props: Dictionary,
) -> GlassButton3D:
	var btn := parent.get_node_or_null(node_name) as GlassButton3D
	if btn == null:
		btn = GlassButton3D.new()
		btn.position = pos
		# Clicking the generated glass/labels in the editor viewport selects the button itself.
		btn.set_meta(&"_edit_group_", true)
		for prop: String in props:
			btn.set(prop, props[prop])
		_adopt(parent, owner_root, btn, node_name)
	return btn


static func ensure_label(
	parent: Node,
	owner_root: Node,
	node_name: String,
	text: String,
	font_size: int,
	color: Color,
	pos: Vector3,
	wrap_width: float,
) -> Label3D:
	var label := parent.get_node_or_null(node_name) as Label3D
	if label == null:
		label = _make_label(text, font_size, color, pos, wrap_width)
		_adopt(parent, owner_root, label, node_name)
	return label


## Connects a button's tap to `action` if the button still exists in the scene.
static func wire_button(stage: Node, path: String, action: Callable) -> void:
	var btn := stage.get_node_or_null(path) as GlassButton3D
	if btn != null:
		btn.tapped.connect(func(_b, _hit_pos, _viewport) -> void: action.call())


static func collect_buttons(stage: Node, path_format: String, keys: Array) -> Array[GlassButton3D]:
	var found: Array[GlassButton3D] = []
	for key in keys:
		var btn := stage.get_node_or_null(path_format % key) as GlassButton3D
		if btn != null:
			found.append(btn)
	return found


static func set_child_visible(parent: Node, path: String, shown: bool) -> void:
	var node := parent.get_node_or_null(path) as Node3D
	if node != null:
		node.visible = shown


static func all_present(nodes: Array[Node]) -> bool:
	for node in nodes:
		if node == null:
			return false
	return true


static func _adopt(parent: Node, owner_root: Node, node: Node, node_name: String) -> void:
	node.name = node_name
	parent.add_child(node)
	if owner_root != null:
		node.owner = owner_root


static func _make_bar(size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var bar := MeshInstance3D.new()
	bar.mesh = mesh
	return bar
