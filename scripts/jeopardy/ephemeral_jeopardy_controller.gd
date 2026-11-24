@tool
extends Node3D
class_name EphemeralJeopardyController

## Main scene coordinator for the 5-Projector Single-Touch Ephemeral Jeopardy Sanctuary.
## Supports per-surface URLs (left.html, center.html, right.html, back.html, floor.html),
## 4-wall + floor split (walls.html + floor.html), and combined 5-wall mode (index.html).
## Also provides an Inspector screen preview switcher for effortless manual editing in Godot Editor.

@export var forced_role: int = -1

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
			_apply_editor_preview_screen()

@onready var player: Player = $Player
@onready var game_state: JeopardyGameState = $JeopardyGameState
@onready var audio_manager: EphemeralAudioManager = $EphemeralAudioManager
@onready var sanctuary_env: SanctuaryEnvironment = $SanctuaryEnvironment
@onready var center_wall: CenterWallStage = $CenterWallStage
@onready var left_wall: LeftWallStage = $LeftWallStage
@onready var right_wall: RightWallStage = $RightWallStage
@onready var back_wall: BackWallStage = $BackWallStage
@onready var floor_stage: FloorStage = $FloorStage

var active_role: int = RoomRole.Role.ALL_5
var sync_transport: RoomSyncTransport = null
var state_sync: GameStateSync = null


func _ready() -> void:
	if Engine.is_editor_hint():
		_apply_editor_preview_screen()
		return

	active_role = RoomRole.detect_role(forced_role)
	var is_host := RoomRole.is_authoritative_host(active_role)

	sanctuary_env.initialize(game_state)
	floor_stage.initialize(game_state, audio_manager)

	if not is_host:
		game_state.is_replica = true
		audio_manager.set_muted(true)

	# Initialize only the wall stages needed for this surface role (saves CPU & hides off-screen colliders)
	match active_role:
		RoomRole.Role.LEFT_ONLY:
			left_wall.initialize(game_state, audio_manager)
			_disable_walls([center_wall, right_wall, back_wall])
			floor_stage.set_floor_interactions_enabled(false)
			player.set_display_mode(Player.DisplayMode.LEFT_ONLY)
		RoomRole.Role.CENTER_ONLY:
			center_wall.initialize(game_state, audio_manager)
			_disable_walls([left_wall, right_wall, back_wall])
			floor_stage.set_floor_interactions_enabled(false)
			player.set_display_mode(Player.DisplayMode.CENTER_ONLY)
			_connect_audio_events()
		RoomRole.Role.RIGHT_ONLY:
			right_wall.initialize(game_state, audio_manager)
			_disable_walls([center_wall, left_wall, back_wall])
			floor_stage.set_floor_interactions_enabled(false)
			player.set_display_mode(Player.DisplayMode.RIGHT_ONLY)
		RoomRole.Role.BACK_ONLY:
			back_wall.initialize(game_state, audio_manager)
			_disable_walls([center_wall, left_wall, right_wall])
			floor_stage.set_floor_interactions_enabled(false)
			player.set_display_mode(Player.DisplayMode.BACK_ONLY)
		RoomRole.Role.FLOOR_ONLY:
			_disable_walls([center_wall, left_wall, right_wall, back_wall])
			player.set_display_mode(Player.DisplayMode.FLOOR_ONLY)
		RoomRole.Role.WALLS_4:
			center_wall.initialize(game_state, audio_manager)
			left_wall.initialize(game_state, audio_manager)
			right_wall.initialize(game_state, audio_manager)
			back_wall.initialize(game_state, audio_manager)
			floor_stage.set_floor_interactions_enabled(false)
			player.set_display_mode(Player.DisplayMode.WALLS_4)
			_connect_audio_events()
		_:
			center_wall.initialize(game_state, audio_manager)
			left_wall.initialize(game_state, audio_manager)
			right_wall.initialize(game_state, audio_manager)
			back_wall.initialize(game_state, audio_manager)
			player.set_display_mode(Player.DisplayMode.ALL_5)
			_connect_audio_events()

	if RoomRole.is_sync_enabled(active_role):
		_start_room_sync(is_host)


func _apply_editor_preview_screen() -> void:
	var c_wall := get_node_or_null("CenterWallStage")
	if c_wall != null and "editor_preview_screen" in c_wall:
		c_wall.set("editor_preview_screen", editor_preview_screen)
	var r_wall := get_node_or_null("RightWallStage")
	if r_wall != null and "editor_preview_screen" in r_wall:
		var r_mode := 0
		if editor_preview_screen == 2:
			r_mode = 2  # Wager Console
		elif editor_preview_screen == 3 or editor_preview_screen == 4:
			r_mode = 1  # Active Clue Timer
		r_wall.set("editor_preview_screen", r_mode)


func _disable_walls(walls: Array[Node3D]) -> void:
	for wall in walls:
		if wall == null:
			continue
		wall.visible = false
		wall.process_mode = Node.PROCESS_MODE_DISABLED


func _start_room_sync(is_host: bool) -> void:
	sync_transport = RoomSyncTransport.new()
	sync_transport.name = "RoomSyncTransport"
	add_child(sync_transport)
	sync_transport.configure(
		RoomRole.role_to_string(active_role),
		RoomRole.detect_room_id(),
		RoomRole.detect_ws_url(),
		true,
	)
	sync_transport.status_changed.connect(func(status_text: String) -> void:
		player.sync_status_text = status_text
	)

	state_sync = GameStateSync.new()
	state_sync.name = "GameStateSync"
	add_child(state_sync)
	state_sync.initialize(game_state, floor_stage, audio_manager, sync_transport, is_host)
	sync_transport.start()
	player.sync_status_text = sync_transport.get_status_summary()


func _connect_audio_events() -> void:
	game_state.audio_mute_changed.connect(func(is_muted: bool) -> void:
		audio_manager.set_muted(is_muted)
	)
	game_state.daily_double_triggered.connect(func(_c, _r, _t, _m) -> void:
		audio_manager.play_sfx("daily_double", 0.02)
	)
	game_state.timer_urgent_tick.connect(func(_sec) -> void:
		audio_manager.play_sfx("tick", 0.03, -2.0)
	)
	game_state.clue_resolved.connect(func(res: Dictionary) -> void:
		if bool(res.get("was_correct", false)):
			audio_manager.play_sfx("correct", 0.02)
		elif bool(res.get("timed_out", false)):
			audio_manager.play_sfx("time_up", 0.01)
		else:
			audio_manager.play_sfx("wrong", 0.02)
	)
	game_state.game_finished.connect(func(_standings) -> void:
		audio_manager.play_sfx("finale", 0.01)
	)
