extends Node3D
class_name EphemeralJeopardyController

## Main scene coordinator for the 5-Projector Single-Touch Ephemeral Jeopardy Sanctuary.
## Supports three runtime roles via RoomRole:
##   - ALL_5: All 5 cameras in one browser/window (default)
##   - WALLS_4: Left/Center/Right/Back authoritative host + hybrid BroadcastChannel/WS sync
##   - FLOOR_ONLY: Floor-only fullscreen replica synced live with WALLS_4

@export var forced_role: int = -1

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
	active_role = RoomRole.detect_role(forced_role)

	sanctuary_env.initialize(game_state)
	floor_stage.initialize(game_state, audio_manager)

	if active_role == RoomRole.Role.FLOOR_ONLY:
		_configure_floor_only_role()
	else:
		center_wall.initialize(game_state, audio_manager)
		left_wall.initialize(game_state, audio_manager)
		right_wall.initialize(game_state, audio_manager)
		back_wall.initialize(game_state, audio_manager)
		_connect_audio_events()
		if active_role == RoomRole.Role.WALLS_4:
			_configure_walls_4_role()
		else:
			player.set_display_mode(Player.DisplayMode.ALL_5)


func _configure_walls_4_role() -> void:
	player.set_display_mode(Player.DisplayMode.WALLS_4)
	# Keep floor visuals visible (wall cameras see outer mandala rim) but disable stray floor ray hits
	floor_stage.set_floor_interactions_enabled(false)
	_start_room_sync(true)


func _configure_floor_only_role() -> void:
	player.set_display_mode(Player.DisplayMode.FLOOR_ONLY)
	game_state.is_replica = true
	audio_manager.set_muted(true)

	# Hide and disable wall stages on the floor display
	for wall in [center_wall, left_wall, right_wall, back_wall]:
		wall.visible = false
		wall.process_mode = Node.PROCESS_MODE_DISABLED

	_start_room_sync(false)


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
