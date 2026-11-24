@tool
extends Node3D
class_name RightWallStage

## Right Wall Projection Stage (+X, at (+4.0, 1.5, 0.0), rotated -90 deg Y).
## Displays "Echoes of the Round" (live history chronicle), Ephemeral Progress,
## Contextual Countdown Focus during Clues, and mirrored Wager Controls during
## Daily Double / Final Jeopardy so players standing on the right can interact too.
##
## All nodes live in RightWallStage.tscn; the script binds to them and never moves hand-placed ones.

enum PreviewScreen { CHRONICLE, CLUE_TIMER, WAGER }

const HOW_TO_PLAY_TEXT := (
	"HOW TO PLAY\n\n"
	+ "• Tap any glowing value monolith on the Center Wall\n"
	+ "• Answer before the ephemeral light fades\n"
	+ "• Watch for hidden Ephemeral Surges (Daily Doubles)\n"
	+ "• Tap Team Podiums on the Left Wall or Floor to buzz in"
)
const MIRROR_PRESETS := [
	{"name": "MirrorPreset_25", "label": "25%", "frac": 0.25, "x": -1.95},
	{"name": "MirrorPreset_50", "label": "50%", "frac": 0.50, "x": -0.65},
	{"name": "MirrorPreset_75", "label": "75%", "frac": 0.75, "x": 0.65},
	{"name": "MirrorPreset_AllIn", "label": "ALL IN", "frac": 1.00, "x": 1.95},
]

## Editor only: which screen is shown while you edit. Play Mode always follows the game phase.
@export_enum("Echoes Chronicle", "Active Clue Timer", "Wager Console")
var editor_preview_screen: int = 0:
	set(value):
		editor_preview_screen = value
		if Engine.is_editor_hint() and is_inside_tree():
			apply_preview_screen()

var game_state: JeopardyGameState
var audio: EphemeralAudioManager

var _chronicle_group: Node3D
var _chronicle_progress: Label3D
var _chronicle_body: Label3D
var _clue_timer_group: Node3D
var _big_timer_label: Label3D
var _big_team_label: Label3D
var _wager_mirror_group: Node3D
var _wager_mirror_amount: Label3D


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
	_refresh_chronicle()
	_sync_phase(game_state.phase)


func apply_preview_screen() -> void:
	var screen := editor_preview_screen
	CenterWallStage.set_child_visible(self, "ChronicleGroup", screen == PreviewScreen.CHRONICLE)
	CenterWallStage.set_child_visible(self, "ActiveClueTimerGroup", screen == PreviewScreen.CLUE_TIMER)
	CenterWallStage.set_child_visible(self, "WagerMirrorGroup", screen == PreviewScreen.WAGER)


func _connect_signals() -> void:
	game_state.phase_changed.connect(func(n, _o) -> void: _sync_phase(n))
	game_state.history_updated.connect(func(_h) -> void: _refresh_chronicle())
	game_state.pack_changed.connect(func(_p) -> void: _refresh_chronicle())
	game_state.board_reset.connect(func(_p) -> void: _refresh_chronicle())
	game_state.teams_updated.connect(func(_t, _idx) -> void: _refresh_active_team())
	game_state.timer_updated.connect(_on_timer_updated)
	game_state.wager_updated.connect(_on_wager_updated)


func _bind_nodes() -> bool:
	_chronicle_group = get_node_or_null("ChronicleGroup") as Node3D
	_chronicle_progress = get_node_or_null("ChronicleGroup/ChronicleProgress") as Label3D
	_chronicle_body = get_node_or_null("ChronicleGroup/ChronicleBody") as Label3D
	_clue_timer_group = get_node_or_null("ActiveClueTimerGroup") as Node3D
	_big_timer_label = get_node_or_null("ActiveClueTimerGroup/BigTimer") as Label3D
	_big_team_label = get_node_or_null("ActiveClueTimerGroup/ActiveTeam") as Label3D
	_wager_mirror_group = get_node_or_null("WagerMirrorGroup") as Node3D
	_wager_mirror_amount = get_node_or_null("WagerMirrorGroup/WagerMirrorAmount") as Label3D
	var required: Array[Node] = [
		_chronicle_group, _chronicle_progress, _chronicle_body,
		_clue_timer_group, _big_timer_label, _big_team_label,
		_wager_mirror_group, _wager_mirror_amount,
	]
	return CenterWallStage.all_present(required)


func _wire_buttons() -> void:
	CenterWallStage.wire_button(self, "ActiveClueTimerGroup/ExtendTimerButton", func() -> void:
		audio.play_sfx("tap")
		game_state.extend_timer(10.0)
	)
	for preset: Dictionary in MIRROR_PRESETS:
		var frac := float(preset["frac"])
		CenterWallStage.wire_button(self, "WagerMirrorGroup/%s" % preset["name"], func() -> void:
			audio.play_sfx("tap")
			game_state.set_wager_fraction(frac)
		)
	CenterWallStage.wire_button(self, "WagerMirrorGroup/MirrorLockButton", func() -> void:
		audio.play_sfx("dissolve")
		game_state.lock_wager()
	)


## Creates every missing stage node. Existing nodes are never touched, so manual edits survive.
## Pass the scene root as owner_root to make the nodes saveable; pass null for a code-only instance.
func build_default_nodes(owner_root: Node) -> void:
	_build_chronicle(owner_root)
	_build_clue_timer(owner_root)
	_build_wager_mirror(owner_root)


func _build_chronicle(owner_root: Node) -> void:
	var group := CenterWallStage.ensure_group(self, owner_root, "ChronicleGroup", true)
	CenterWallStage.ensure_label(
		group,
		owner_root,
		"ChronicleTitle",
		"ECHOES OF THE ROUND",
		52,
		Color(0.95, 0.98, 1.0),
		Vector3(0.0, 1.32, 0.05),
		2050.0,
	)
	CenterWallStage.ensure_label(
		group,
		owner_root,
		"ChronicleProgress",
		"EPHEMERAL WONDERS  •  25 / 25 REMAINING",
		32,
		Color(0.56, 0.90, 1.0),
		Vector3(0.0, 1.00, 0.05),
		2000.0,
	)
	CenterWallStage.ensure_button(group, owner_root, "ChronicleBackdrop", Vector3(0.0, -0.08, -0.02), {
		"panel_size": Vector3(5.90, 1.78, 0.08),
		"primary_text": "",
		"primary_font_size": 40,
		"base_color": Color(0.05, 0.11, 0.24, 0.88),
		"rim_color": Color(0.40, 0.82, 1.0, 1.0),
		"enable_idle_float": false,
		"interaction_enabled": false,
	})
	CenterWallStage.ensure_label(
		group,
		owner_root,
		"ChronicleBody",
		HOW_TO_PLAY_TEXT,
		38,
		Color(0.88, 0.94, 1.0),
		Vector3(0.0, -0.06, 0.08),
		1760.0,
	)


func _build_clue_timer(owner_root: Node) -> void:
	var group := CenterWallStage.ensure_group(self, owner_root, "ActiveClueTimerGroup", false)
	CenterWallStage.ensure_label(
		group,
		owner_root,
		"TimerTitle",
		"EPHEMERAL COUNTDOWN",
		48,
		Color(0.78, 0.92, 1.0),
		Vector3(0.0, 1.24, 0.05),
		2000.0,
	)
	CenterWallStage.ensure_button(group, owner_root, "TimerBackdrop", Vector3(0.0, 0.22, -0.02), {
		"panel_size": Vector3(4.2, 1.48, 0.08),
		"primary_text": "",
		"primary_font_size": 40,
		"base_color": Color(0.06, 0.12, 0.26, 0.90),
		"rim_color": Color(0.36, 0.90, 1.0, 1.0),
		"enable_idle_float": false,
		"interaction_enabled": false,
	})
	CenterWallStage.ensure_label(
		group,
		owner_root,
		"BigTimer",
		"25",
		168,
		Color(0.45, 0.94, 1.0),
		Vector3(0.0, 0.36, 0.08),
		1200.0,
	)
	CenterWallStage.ensure_label(
		group,
		owner_root,
		"ActiveTeam",
		"ACTIVE: AURORA",
		40,
		Color(1.0, 0.88, 0.52),
		Vector3(0.0, -0.26, 0.08),
		1500.0,
	)
	CenterWallStage.ensure_button(group, owner_root, "ExtendTimerButton", Vector3(0.0, -0.92, 0.04), {
		"panel_size": Vector3(2.8, 0.48, 0.09),
		"primary_text": "+10 SECONDS",
		"secondary_text": "EXTEND THE MOMENT",
		"primary_font_size": 44,
		"base_color": Color(0.08, 0.18, 0.32, 0.90),
		"rim_color": Color(1.0, 0.84, 0.44, 1.0),
	})


func _build_wager_mirror(owner_root: Node) -> void:
	var group := CenterWallStage.ensure_group(self, owner_root, "WagerMirrorGroup", false)
	CenterWallStage.ensure_label(
		group,
		owner_root,
		"WagerMirrorTitle",
		"WAGER CONSOLE",
		56,
		Color(1.0, 0.86, 0.46),
		Vector3(0.0, 1.24, 0.05),
		1900.0,
	)
	CenterWallStage.ensure_label(
		group,
		owner_root,
		"WagerMirrorAmount",
		"$500",
		128,
		Color(1.0, 0.94, 0.72),
		Vector3(0.0, 0.48, 0.06),
		1500.0,
	)
	for preset: Dictionary in MIRROR_PRESETS:
		var pos := Vector3(float(preset["x"]), -0.28, 0.0)
		CenterWallStage.ensure_button(group, owner_root, str(preset["name"]), pos, {
			"panel_size": Vector3(1.16, 0.44, 0.08),
			"primary_text": str(preset["label"]),
			"primary_font_size": 42,
			"base_color": Color(0.11, 0.12, 0.30, 0.90),
			"rim_color": Color(0.86, 0.56, 1.0, 1.0),
		})
	CenterWallStage.ensure_button(group, owner_root, "MirrorLockButton", Vector3(0.0, -0.94, 0.05), {
		"panel_size": Vector3(2.80, 0.50, 0.10),
		"primary_text": "LOCK WAGER",
		"secondary_text": "CONFIRM",
		"primary_font_size": 48,
		"base_color": Color(0.15, 0.24, 0.34, 0.92),
		"rim_color": Color(1.0, 0.84, 0.42, 1.0),
		"highlight_amount": 0.65,
	})


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
		_chronicle_body.text = HOW_TO_PLAY_TEXT
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
