extends RefCounted
class_name RoomRole

## Resolves which projector camera(s) this instance renders and whether it runs as
## standalone, authoritative host, or synced replica.
##
## Per-projector URLs:
##   left.html   -> LEFT_ONLY   (replica, renders Left Wall -X)
##   center.html -> CENTER_ONLY (authoritative host, renders Center Wall -Z, owns audio)
##   right.html  -> RIGHT_ONLY  (replica, renders Right Wall +X)
##   back.html   -> BACK_ONLY   (replica, renders Back Wall +Z)
##   floor.html  -> FLOOR_ONLY  (replica, renders Floor -Y)
## Combined URLs:
##   walls.html  -> WALLS_4     (authoritative host, renders Left/Center/Right/Back)
##   index.html  -> ALL_5       (standalone, renders all 5 cameras)

enum Role {
	ALL_5,
	WALLS_4,
	FLOOR_ONLY,
	LEFT_ONLY,
	CENTER_ONLY,
	RIGHT_ONLY,
	BACK_ONLY,
}

const DEFAULT_CHANNEL := "immersive_ephemeral_jeopardy_v1"
const DEFAULT_ROOM := "default"


static func detect_role(override_role: int = -1) -> int:
	if override_role in [
		Role.ALL_5,
		Role.WALLS_4,
		Role.FLOOR_ONLY,
		Role.LEFT_ONLY,
		Role.CENTER_ONLY,
		Role.RIGHT_ONLY,
		Role.BACK_ONLY,
	]:
		return override_role

	# 1. Web browser URL ?role= or window.__IMMERSIVE_ROLE__ global
	if OS.has_feature("web"):
		var web_role := _read_web_string(
			"(function(){try{var p=new URLSearchParams(window.location.search).get('role');"
			+ "return p||window.__IMMERSIVE_ROLE__||'';}catch(e){return '';}})()"
		)
		var parsed := parse_role_string(web_role)
		if parsed != -1:
			return parsed

	# 2. Command-line / GODOT_CONFIG.args (--role=left|center|right|back|floor|walls|all)
	for arg in OS.get_cmdline_user_args():
		var parsed := _parse_role_arg(arg)
		if parsed != -1:
			return parsed
	for arg in OS.get_cmdline_args():
		var parsed := _parse_role_arg(arg)
		if parsed != -1:
			return parsed

	# 3. Export feature tag fallback
	if OS.has_feature("left_only"):
		return Role.LEFT_ONLY
	if OS.has_feature("center_only"):
		return Role.CENTER_ONLY
	if OS.has_feature("right_only"):
		return Role.RIGHT_ONLY
	if OS.has_feature("back_only"):
		return Role.BACK_ONLY
	if OS.has_feature("floor_only"):
		return Role.FLOOR_ONLY
	if OS.has_feature("walls_only"):
		return Role.WALLS_4

	return Role.ALL_5


static func is_sync_enabled(role: int) -> bool:
	return role != Role.ALL_5


static func is_authoritative_host(role: int) -> bool:
	return role == Role.ALL_5 or role == Role.WALLS_4 or role == Role.CENTER_ONLY


static func detect_room_id() -> String:
	if OS.has_feature("web"):
		var web_room := _read_web_string(
			"(function(){try{return new URLSearchParams(window.location.search).get('room')||'';}"
			+ "catch(e){return '';}})()"
		).strip_edges()
		if not web_room.is_empty():
			return web_room

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--room="):
			var val := arg.substr(7).strip_edges()
			if not val.is_empty():
				return val

	return DEFAULT_ROOM


static func resolve_ws_url(explicit_param: String, protocol: String, host: String) -> String:
	var explicit := explicit_param.strip_edges()
	if not explicit.is_empty():
		var lowered := explicit.to_lower()
		if lowered in ["none", "off", "false"]:
			return ""
		return explicit

	var trimmed_host := host.strip_edges()
	if trimmed_host.is_empty():
		return ""

	var hostname := _extract_hostname(trimmed_host)
	if not _is_local_or_lan_host(hostname):
		return ""

	var ws_proto := "wss:" if protocol.strip_edges().to_lower() == "https:" else "ws:"
	return "%s//%s/ws" % [ws_proto, trimmed_host]


static func detect_ws_url() -> String:
	if OS.has_feature("web"):
		var explicit := _read_web_string(
			"(function(){try{return new URLSearchParams(window.location.search).get('ws')||'';}"
			+ "catch(e){return '';}})()"
		)
		var protocol := _read_web_string(
			"(function(){try{return window.location.protocol||'';}catch(e){return '';}})()"
		)
		var host := _read_web_string(
			"(function(){try{return window.location.host||'';}catch(e){return '';}})()"
		)
		return resolve_ws_url(explicit, protocol, host)

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ws="):
			return resolve_ws_url(arg.substr(5), "", "")

	return ""


static func role_to_string(role: int) -> String:
	match role:
		Role.LEFT_ONLY:
			return "left"
		Role.CENTER_ONLY:
			return "center"
		Role.RIGHT_ONLY:
			return "right"
		Role.BACK_ONLY:
			return "back"
		Role.FLOOR_ONLY:
			return "floor"
		Role.WALLS_4:
			return "walls"
		_:
			return "all"


static func parse_role_string(raw: String) -> int:
	match raw.strip_edges().to_lower():
		"left", "left_only":
			return Role.LEFT_ONLY
		"center", "center_only", "main":
			return Role.CENTER_ONLY
		"right", "right_only":
			return Role.RIGHT_ONLY
		"back", "back_only":
			return Role.BACK_ONLY
		"floor", "floor_only", "client":
			return Role.FLOOR_ONLY
		"walls", "walls_4", "4walls", "host":
			return Role.WALLS_4
		"all", "all_5", "5walls":
			return Role.ALL_5
		_:
			return -1


static func _parse_role_arg(arg: String) -> int:
	if arg.begins_with("--role="):
		return parse_role_string(arg.substr(7))
	return -1


static func _extract_hostname(host_with_port: String) -> String:
	var h := host_with_port.strip_edges().to_lower()
	if h.begins_with("["):
		var close_idx := h.find("]")
		if close_idx != -1:
			return h.substr(1, close_idx - 1)
		return h
	var colon_idx := h.rfind(":")
	if colon_idx != -1 and h.find(":") == colon_idx:
		return h.substr(0, colon_idx)
	return h


static func _is_local_or_lan_host(hostname: String) -> bool:
	if hostname.is_empty():
		return false
	if hostname == "localhost" or hostname == "::1" or hostname.ends_with(".local"):
		return true

	var octets := hostname.split(".")
	if octets.size() != 4:
		return false
	var nums: Array[int] = []
	for part in octets:
		if part.is_empty() or not part.is_valid_int():
			return false
		var val := int(part)
		if val < 0 or val > 255:
			return false
		nums.append(val)

	if nums[0] == 127 or nums[0] == 10:
		return true
	if nums[0] == 192 and nums[1] == 168:
		return true
	if nums[0] == 172 and nums[1] >= 16 and nums[1] <= 31:
		return true
	return false


static func _read_web_string(js_expr: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var result: Variant = JavaScriptBridge.eval(js_expr, true)
	return "" if result == null else str(result)
