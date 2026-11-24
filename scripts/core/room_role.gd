extends RefCounted
class_name RoomRole

## Resolves whether this instance runs all 5 cameras, the 4 wall projectors only
## (Left/Center/Right/Back), or the Floor projector only.

enum Role {
	ALL_5,
	WALLS_4,
	FLOOR_ONLY,
}

const DEFAULT_CHANNEL := "immersive_ephemeral_jeopardy_v1"
const DEFAULT_ROOM := "default"


static func detect_role(override_role: int = -1) -> int:
	if override_role in [Role.ALL_5, Role.WALLS_4, Role.FLOOR_ONLY]:
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

	# 2. Command-line / GODOT_CONFIG.args (--role=walls | --role=floor | --role=all)
	for arg in OS.get_cmdline_user_args():
		var parsed := _parse_role_arg(arg)
		if parsed != -1:
			return parsed
	for arg in OS.get_cmdline_args():
		var parsed := _parse_role_arg(arg)
		if parsed != -1:
			return parsed

	# 3. Export feature tag fallback
	if OS.has_feature("floor_only"):
		return Role.FLOOR_ONLY
	if OS.has_feature("walls_only"):
		return Role.WALLS_4

	return Role.ALL_5


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


static func detect_ws_url() -> String:
	# Explicit ?ws= query override on Web, or automatic same-origin ws(s)://<host>/ws only
	# when served from a local/LAN host (static public hosts like *.github.io have no /ws relay).
	if OS.has_feature("web"):
		var explicit := _read_web_string(
			"(function(){try{return new URLSearchParams(window.location.search).get('ws')||'';}"
			+ "catch(e){return '';}})()"
		)
		var protocol := _read_web_string("(function(){try{return window.location.protocol||'';}catch(e){return '';}})()")
		var host := _read_web_string("(function(){try{return window.location.host||'';}catch(e){return '';}})()")
		return resolve_ws_url(explicit, protocol, host)

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ws="):
			return resolve_ws_url(arg.substr(5), "", "")

	return ""


## Pure helper: decides which WebSocket relay URL (if any) to use.
## - explicit_param "none"/"off"/"false" (any case) disables WebSocket sync.
## - Any other non-empty explicit_param is returned verbatim (e.g. a wss:// relay).
## - Otherwise auto-connect to same-origin ws(s)://<host>/ws only for local/LAN hosts.
static func resolve_ws_url(explicit_param: String, protocol: String, host: String) -> String:
	var explicit := explicit_param.strip_edges()
	if explicit.to_lower() in ["none", "off", "false"]:
		return ""
	if not explicit.is_empty():
		return explicit

	var clean_host := host.strip_edges()
	if clean_host.is_empty() or not is_local_hostname(_hostname_from_host(clean_host)):
		return ""
	var scheme := "wss:" if protocol.strip_edges().to_lower() == "https:" else "ws:"
	return "%s//%s/ws" % [scheme, clean_host]


static func is_local_hostname(hostname: String) -> bool:
	var h := hostname.strip_edges().to_lower()
	if h.is_empty():
		return false
	if h in ["localhost", "127.0.0.1", "[::1]", "::1"]:
		return true
	if h.ends_with(".local") or h.ends_with(".localhost"):
		return true
	var parts := h.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if not part.is_valid_int():
			return false
	var a := int(parts[0])
	var b := int(parts[1])
	if a == 127 or a == 10:
		return true
	if a == 192 and b == 168:
		return true
	return a == 172 and b >= 16 and b <= 31


static func _hostname_from_host(host: String) -> String:
	# Strip an optional :port suffix, keeping bracketed IPv6 literals like [::1]:8080 intact.
	if host.begins_with("["):
		var close := host.find("]")
		return host if close == -1 else host.substr(0, close + 1)
	var colon := host.find(":")
	if colon != -1 and host.count(":") == 1:
		return host.substr(0, colon)
	return host


static func role_to_string(role: int) -> String:
	match role:
		Role.WALLS_4:
			return "walls"
		Role.FLOOR_ONLY:
			return "floor"
		_:
			return "all"


static func parse_role_string(raw: String) -> int:
	match raw.strip_edges().to_lower():
		"walls", "walls_4", "4walls", "host":
			return Role.WALLS_4
		"floor", "floor_only", "client":
			return Role.FLOOR_ONLY
		"all", "all_5", "5walls":
			return Role.ALL_5
		_:
			return -1


static func _parse_role_arg(arg: String) -> int:
	if arg.begins_with("--role="):
		return parse_role_string(arg.substr(7))
	return -1


static func _read_web_string(js_expr: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var result: Variant = JavaScriptBridge.eval(js_expr, true)
	return "" if result == null else str(result)
