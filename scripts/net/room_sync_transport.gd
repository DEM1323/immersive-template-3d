extends Node
class_name RoomSyncTransport

## Hybrid zero-config sync transport for split Walls + Floor browser deployments.
## Simultaneously runs:
##   1. Same-origin BroadcastChannel (zero server when both windows share a browser profile)
##   2. Same-origin WebSocket (/ws) via WebSocketPeer (works across isolated browser profiles,
##      embedded kiosk WebViews, different browsers on the same PC, or separate PCs on LAN)
## Deduplicates messages received on both transports via monotonically increasing msg_id.

signal message_received(payload: Dictionary)
signal message_sent_json(json_text: String)
signal peer_connected(transport_name: String)
signal status_changed(status_text: String)

const MAX_SEEN_IDS := 256

var room_id: String = RoomRole.DEFAULT_ROOM
var role_name: String = "all"
var ws_url: String = ""
var sender_id: String = ""
var enable_network: bool = true

var _seq_out: int = 0
var _seen_ids: Dictionary = {}
var _seen_order: Array[String] = []

# Web BroadcastChannel handles (kept in member vars so JS GC never frees the callback)
var _bc: Variant = null
var _bc_callback: Variant = null
var _bc_active: bool = false

# WebSocketPeer state
var _ws: WebSocketPeer = null
var _ws_connected: bool = false
var _ws_reconnect_timer: float = 0.0
var _ws_backoff: float = 1.5


func configure(p_role_name: String, p_room_id: String, p_ws_url: String, p_enable_network: bool = true) -> void:
	role_name = p_role_name
	room_id = p_room_id
	ws_url = p_ws_url
	enable_network = p_enable_network
	if sender_id.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		sender_id = "%s-%08x" % [role_name, rng.randi()]


func start() -> void:
	if not enable_network:
		status_changed.emit("LOCAL TEST")
		return
	_setup_broadcast_channel()
	if not ws_url.is_empty():
		_connect_websocket()
	_emit_status()
	set_process(true)


func stop() -> void:
	if _ws != null:
		_ws.close()
		_ws = null
	_ws_connected = false
	if _bc != null:
		_bc.close()
		_bc = null
	_bc_callback = null
	_bc_active = false
	set_process(false)


func _exit_tree() -> void:
	stop()


func _process(delta: float) -> void:
	if not enable_network or ws_url.is_empty():
		return
	if _ws == null:
		_ws_reconnect_timer -= delta
		if _ws_reconnect_timer <= 0.0:
			_connect_websocket()
		return

	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _ws_connected:
			_ws_connected = true
			_ws_backoff = 1.5
			_emit_status()
			peer_connected.emit("websocket")
		while _ws.get_available_packet_count() > 0:
			var raw := _ws.get_packet().get_string_from_utf8()
			_handle_raw_json(raw)
	elif state == WebSocketPeer.STATE_CLOSED:
		if _ws_connected:
			_ws_connected = false
			_emit_status()
		_ws = null
		_ws_reconnect_timer = _ws_backoff
		_ws_backoff = minf(_ws_backoff * 1.5, 5.0)


func send_message(payload: Dictionary) -> void:
	_seq_out += 1
	var envelope := payload.duplicate(true)
	envelope["v"] = 1
	envelope["room"] = room_id
	envelope["from"] = sender_id
	envelope["role"] = role_name
	envelope["msg_id"] = "%s:%d" % [sender_id, _seq_out]
	var json_text := JSON.stringify(envelope)
	message_sent_json.emit(json_text)

	if _bc != null and _bc_active:
		_bc.postMessage(json_text)
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(json_text)


func inject_raw_for_test(json_text: String) -> void:
	_handle_raw_json(json_text)


func inject_message_for_test(payload: Dictionary) -> void:
	_handle_raw_json(JSON.stringify(payload))


func get_status_summary() -> String:
	var parts: Array[String] = []
	if _bc_active:
		parts.append("BC")
	if _ws_connected:
		parts.append("WS")
	elif not ws_url.is_empty():
		parts.append("WS:wait")
	return "+".join(parts) if not parts.is_empty() else "OFFLINE"


func _setup_broadcast_channel() -> void:
	if not OS.has_feature("web"):
		return
	var has_bc: Variant = JavaScriptBridge.eval("typeof BroadcastChannel !== 'undefined'", true)
	if has_bc != true:
		return
	var channel_name := "%s:%s" % [RoomRole.DEFAULT_CHANNEL, room_id]
	_bc = JavaScriptBridge.create_object("BroadcastChannel", channel_name)
	if _bc == null:
		return
	_bc_callback = JavaScriptBridge.create_callback(_on_bc_message)
	_bc.onmessage = _bc_callback
	_bc_active = true
	peer_connected.emit("broadcast_channel")


func _on_bc_message(args: Array) -> void:
	if args.is_empty():
		return
	var ev: Variant = args[0]
	if ev == null:
		return
	_handle_raw_json(str(ev.data))


func _connect_websocket() -> void:
	if ws_url.is_empty():
		return
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(ws_url)
	if err != OK:
		_ws = null
		_ws_reconnect_timer = _ws_backoff
		_ws_backoff = minf(_ws_backoff * 1.5, 5.0)


func _handle_raw_json(json_text: String) -> void:
	if json_text.is_empty():
		return
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return
	var msg := parsed as Dictionary
	if str(msg.get("room", room_id)) != room_id:
		return
	if str(msg.get("from", "")) == sender_id:
		return

	var msg_id := str(msg.get("msg_id", ""))
	if not msg_id.is_empty():
		if _seen_ids.has(msg_id):
			return
		_record_seen_id(msg_id)

	message_received.emit(msg)


func _record_seen_id(msg_id: String) -> void:
	_seen_ids[msg_id] = true
	_seen_order.append(msg_id)
	while _seen_order.size() > MAX_SEEN_IDS:
		var oldest: String = _seen_order.pop_front()
		_seen_ids.erase(oldest)


func _emit_status() -> void:
	status_changed.emit(get_status_summary())
