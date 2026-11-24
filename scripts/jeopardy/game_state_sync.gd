extends Node
class_name GameStateSync

## Synchronizes an authoritative Host (center.html or walls.html) with any combination
## of replica surfaces (left.html, right.html, back.html, floor.html) over RoomSyncTransport.

const HEARTBEAT_INTERVAL_SEC := 2.0
const REPLICA_HELLO_RETRY_SEC := 1.5

var game_state: JeopardyGameState
var floor_stage: Node3D
var audio: EphemeralAudioManager
var transport: RoomSyncTransport
var is_host: bool = true

var _state_seq: int = 0
var _last_applied_seq: int = -1
var _heartbeat_accum: float = 0.0
var _has_snapshot: bool = false
var _hello_retry_accum: float = 0.0
var _suppress_ripple_echo: bool = false


func initialize(
	p_state: JeopardyGameState,
	p_floor_stage: Node3D,
	p_audio: EphemeralAudioManager,
	p_transport: RoomSyncTransport,
	p_is_host: bool,
) -> void:
	game_state = p_state
	floor_stage = p_floor_stage
	audio = p_audio
	transport = p_transport
	is_host = p_is_host

	transport.message_received.connect(_on_message_received)
	transport.peer_connected.connect(_on_peer_connected)

	if is_host:
		_wire_host_signals()
	else:
		_wire_replica_signals()

	set_process(true)


func _process(delta: float) -> void:
	if is_host:
		_heartbeat_accum += delta
		if _heartbeat_accum >= HEARTBEAT_INTERVAL_SEC:
			_heartbeat_accum = 0.0
			broadcast_snapshot()
	elif not _has_snapshot:
		_hello_retry_accum += delta
		if _hello_retry_accum >= REPLICA_HELLO_RETRY_SEC:
			_hello_retry_accum = 0.0
			send_hello()


func _notification(what: int) -> void:
	# Re-hydrate immediately if any replica kiosk browser regains focus/visibility
	if not is_host and (what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN):
		send_hello()


func _wire_host_signals() -> void:
	game_state.phase_changed.connect(func(_n, _o) -> void: broadcast_snapshot())
	game_state.pack_changed.connect(func(_p) -> void: broadcast_snapshot())
	game_state.teams_updated.connect(func(_t, _idx) -> void: broadcast_snapshot())
	game_state.play_mode_changed.connect(func(_m) -> void: broadcast_snapshot())
	game_state.audio_mute_changed.connect(func(_m) -> void: broadcast_snapshot())
	game_state.board_reset.connect(func(_p) -> void: broadcast_snapshot())
	game_state.wager_updated.connect(func(_c, _min_w, _max_w) -> void: broadcast_snapshot())
	game_state.clue_started.connect(func(_c) -> void: broadcast_snapshot())
	game_state.host_answer_revealed.connect(func(_a) -> void: broadcast_snapshot())
	game_state.clue_resolved.connect(func(res: Dictionary) -> void:
		broadcast_snapshot()
		_broadcast_event("clue_resolved", {"result": _serialize_result(res)})
	)
	game_state.timer_anchor_changed.connect(func(rem: float, tot: float, paused: bool, anchor: float) -> void:
		_broadcast_event("timer_anchor", {
			"remaining": rem,
			"total": tot,
			"paused": paused,
			"anchor_unix": anchor,
		})
	)
	game_state.game_finished.connect(func(_s) -> void: broadcast_snapshot())


func _wire_replica_signals() -> void:
	game_state.remote_command_requested.connect(_on_replica_command_requested)
	var bus := get_node_or_null("/root/InteractionBus")
	if bus != null and bus.has_signal(&"touch_ripple"):
		if not bus.is_connected(&"touch_ripple", _on_local_floor_ripple):
			bus.connect(&"touch_ripple", _on_local_floor_ripple)


func _on_peer_connected(_transport_name: String) -> void:
	if is_host:
		broadcast_snapshot()
	else:
		send_hello()


func send_hello() -> void:
	if transport == null:
		return
	transport.send_message({"type": "hello"})


func broadcast_snapshot() -> void:
	if not is_host or transport == null or game_state == null:
		return
	_state_seq += 1
	transport.send_message({
		"type": "snapshot",
		"seq": _state_seq,
		"state": game_state.export_sync_snapshot(),
	})


func _broadcast_event(event_name: String, data: Dictionary) -> void:
	if not is_host or transport == null:
		return
	_state_seq += 1
	transport.send_message({
		"type": "event",
		"seq": _state_seq,
		"name": event_name,
		"data": data,
	})


func _on_replica_command_requested(command: String, payload: Dictionary) -> void:
	if is_host or transport == null:
		return
	transport.send_message({
		"type": "command",
		"name": command,
		"data": payload,
	})


func _on_local_floor_ripple(world_pos: Vector3, _normal: Vector3, viewport_index: int, color: Color) -> void:
	if is_host or _suppress_ripple_echo or viewport_index != 4 or transport == null:
		return
	transport.send_message({
		"type": "command",
		"name": "floor_ripple",
		"data": {
			"x": world_pos.x,
			"z": world_pos.z,
			"color": color.to_html(false),
		},
	})


func _on_message_received(msg: Dictionary) -> void:
	var msg_type := str(msg.get("type", ""))
	if is_host:
		_handle_host_message(msg_type, msg)
	else:
		_handle_replica_message(msg_type, msg)


func _handle_host_message(msg_type: String, msg: Dictionary) -> void:
	if msg_type == "hello":
		broadcast_snapshot()
		return
	if msg_type != "command":
		return
	var cmd_name := str(msg.get("name", ""))
	var data: Dictionary = msg.get("data", {}) if msg.get("data") is Dictionary else {}
	match cmd_name:
		"buzz_team":
			var idx := int(data.get("team_index", -1))
			if idx >= 0 and idx < game_state.teams.size():
				_play_host_sfx("tap", 0.05)
				game_state.set_active_team(idx)
		"cycle_active_team":
			_play_host_sfx("tap", 0.04)
			game_state.cycle_active_team()
		"start_new_game":
			_play_host_sfx("daily_double", 0.02, -3.0)
			game_state.start_new_game()
		"return_to_setup":
			_play_host_sfx("tap")
			game_state.return_to_setup()
		"toggle_play_mode":
			_play_host_sfx("tap")
			game_state.toggle_play_mode()
		"set_play_mode":
			_play_host_sfx("tap")
			game_state.set_play_mode(int(data.get("mode", 0)))
		"cycle_pack":
			_play_host_sfx("tap")
			game_state.cycle_pack()
		"select_pack":
			_play_host_sfx("tap")
			game_state.select_pack(int(data.get("index", 0)))
		"set_team_count":
			_play_host_sfx("tap")
			game_state.set_team_count(int(data.get("count", 2)))
		"toggle_timer_pause":
			_play_host_sfx("tap")
			game_state.toggle_timer_pause()
		"extend_timer":
			_play_host_sfx("tap")
			game_state.extend_timer(float(data.get("seconds", 10.0)))
		"set_wager_fraction":
			_play_host_sfx("tap")
			game_state.set_wager_fraction(float(data.get("fraction", 0.5)))
		"adjust_wager":
			_play_host_sfx("tap", 0.05)
			game_state.adjust_wager(int(data.get("delta", 0)))
		"lock_wager":
			_play_host_sfx("dissolve")
			game_state.lock_wager()
		"begin_final_jeopardy":
			_play_host_sfx("daily_double", 0.02, -4.0)
			game_state.begin_final_jeopardy()
		"continue_after_result":
			_play_host_sfx("tap")
			game_state.continue_after_result()
		"select_tile":
			_play_host_sfx("dissolve")
			game_state.select_tile(int(data.get("cat_idx", -1)), int(data.get("row_idx", -1)))
		"submit_choice":
			_play_host_sfx("tap")
			game_state.submit_choice(int(data.get("choice_index", 0)))
		"reveal_host_answer":
			_play_host_sfx("tap")
			game_state.reveal_host_answer()
		"submit_host_judgment":
			game_state.submit_host_judgment(bool(data.get("was_correct", false)), bool(data.get("is_pass", false)))
		"toggle_mute":
			game_state.toggle_audio_mute()
			if audio != null:
				audio.set_muted(game_state.audio_muted)
				audio.play_sfx("tap")
		"floor_ripple":
			_apply_remote_floor_ripple(data)
			# Relay floor ripple to all other wall replicas so their lower floor rims ripple too
			_broadcast_event("floor_ripple", data)


func _handle_replica_message(msg_type: String, msg: Dictionary) -> void:
	var seq := int(msg.get("seq", -1))
	if msg_type == "snapshot":
		# Accept if sequence increased, or if host restarted (seq reset well below last_applied_seq)
		if seq >= 0 and seq < _last_applied_seq and (_last_applied_seq - seq) < 5:
			return
		_last_applied_seq = max(seq, 0)
		var state_dict: Variant = msg.get("state", null)
		if state_dict is Dictionary:
			_has_snapshot = true
			game_state.apply_sync_snapshot(state_dict as Dictionary)
	elif msg_type == "event":
		if seq >= 0 and seq <= _last_applied_seq:
			return
		if seq >= 0:
			_last_applied_seq = seq
		var ev_name := str(msg.get("name", ""))
		var data: Dictionary = msg.get("data", {}) if msg.get("data") is Dictionary else {}
		if ev_name == "clue_resolved":
			var res_raw: Variant = data.get("result", null)
			if res_raw is Dictionary:
				game_state.apply_remote_clue_resolved(res_raw as Dictionary)
		elif ev_name == "timer_anchor":
			game_state.apply_remote_timer_anchor(
				float(data.get("remaining", 0.0)),
				float(data.get("total", 25.0)),
				bool(data.get("paused", false)),
				float(data.get("anchor_unix", 0.0)),
			)
		elif ev_name == "floor_ripple":
			_apply_remote_floor_ripple(data)


func _apply_remote_floor_ripple(data: Dictionary) -> void:
	if floor_stage == null or not floor_stage.has_method("trigger_floor_ripple"):
		return
	var pos := Vector3(float(data.get("x", 0.0)), 0.0, float(data.get("z", 0.0)))
	var col := Color.from_string("#" + str(data.get("color", "75efff")), Color(0.46, 0.94, 1.0))
	_suppress_ripple_echo = true
	floor_stage.call("trigger_floor_ripple", pos, col)
	_suppress_ripple_echo = false


func _play_host_sfx(key: String, jitter: float = 0.04, vol_db: float = 0.0) -> void:
	if audio != null:
		audio.play_sfx(key, jitter, vol_db)


static func _serialize_result(res: Dictionary) -> Dictionary:
	return {
		"category": str(res.get("category", "")),
		"value": int(res.get("value", 0)),
		"was_correct": bool(res.get("was_correct", false)),
		"timed_out": bool(res.get("timed_out", false)),
		"is_pass": bool(res.get("is_pass", false)),
		"outcome": str(res.get("outcome", "")),
		"score_delta": int(res.get("score_delta", 0)),
		"team_index": int(res.get("team_index", 0)),
		"team_name": str(res.get("team_name", "")),
		"answer": str(res.get("answer", "")),
		"fact": str(res.get("fact", "")),
		"is_daily_double": bool(res.get("is_daily_double", false)),
		"is_final": bool(res.get("is_final", false)),
	}
