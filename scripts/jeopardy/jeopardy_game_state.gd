extends Node
class_name JeopardyGameState

## Pure, headless-testable game state machine for Ephemeral Jeopardy.
## Drives all 5 projection surfaces (Center, Left, Right, Back, Floor) via signals.
## In replica mode (left.html, right.html, back.html, floor.html), every mutating action
## forwards a command to the authoritative host (center.html / walls.html) over sync.

enum Phase {
	SETUP,
	BOARD,
	DAILY_DOUBLE_WAGER,
	CLUE_ACTIVE,
	CLUE_RESULT,
	FINAL_WAGER,
	FINAL_CLUE,
	GAME_OVER,
}

enum PlayMode {
	QUIZ,  # Standalone single-touch 4-choice cards (no host needed)
	HOST,  # Live classroom/party host reveal + Correct/Incorrect/Pass
}

const TEAM_PRESETS := [
	{"name": "AURORA", "color": Color(0.28, 0.90, 0.96, 1.0)},
	{"name": "SOLARIS", "color": Color(1.0, 0.78, 0.34, 1.0)},
	{"name": "NEBULA", "color": Color(0.76, 0.46, 1.0, 1.0)},
	{"name": "VERDANT", "color": Color(0.34, 0.95, 0.66, 1.0)},
]

signal phase_changed(new_phase: int, old_phase: int)
signal packs_loaded(packs: Array[JeopardyPack])
signal pack_changed(pack: JeopardyPack)
signal teams_updated(teams: Array[Dictionary], active_team_index: int)
signal play_mode_changed(mode: int)
signal board_reset(pack: JeopardyPack)
signal tile_cleared(cat_idx: int, row_idx: int, was_correct: bool)
signal daily_double_triggered(cat_idx: int, row_idx: int, team_index: int, max_wager: int)
signal wager_updated(current_wager: int, min_wager: int, max_wager: int)
signal clue_started(clue_payload: Dictionary)
signal host_answer_revealed(answer_text: String)
signal clue_resolved(result_payload: Dictionary)
signal timer_updated(remaining: float, total: float, paused: bool)
signal timer_anchor_changed(remaining: float, total: float, paused: bool, anchor_unix: float)
signal timer_urgent_tick(seconds_left: int)
signal history_updated(entries: Array[Dictionary])
signal game_finished(standings: Array[Dictionary])
signal audio_mute_changed(is_muted: bool)
signal remote_command_requested(command: String, payload: Dictionary)

var is_replica: bool = false
var audio_muted: bool = false
var packs: Array[JeopardyPack] = []
var current_pack_index: int = 0
var current_pack: JeopardyPack = null

var phase: int = Phase.SETUP
var play_mode: int = PlayMode.QUIZ
var team_count: int = 2
var teams: Array[Dictionary] = []
var active_team_index: int = 0

# Board tracking
var cleared_tiles: Dictionary = {}  # "cat_row" -> bool
var daily_double_keys: Dictionary = {}  # "cat_row" -> bool
var total_tiles: int = 25
var remaining_tiles: int = 25

# Active clue / wager state
var active_cat_idx: int = -1
var active_row_idx: int = -1
var active_clue: Dictionary = {}
var active_value: int = 0
var active_is_daily_double: bool = false
var active_is_final: bool = false
var host_revealed: bool = false
var current_wager: int = 200
var min_wager: int = 200
var max_wager: int = 1000
var final_wagers: Array[int] = []
var final_wager_team_cursor: int = 0
var final_answer_team_cursor: int = 0

# Timer
var timer_total: float = 25.0
var timer_remaining: float = 25.0
var timer_paused: bool = false
var _last_urgent_second: int = -1

# Chronicle ("Echoes of the Round")
var history: Array[Dictionary] = []
var last_result: Dictionary = {}

# Deterministic RNG option for tests
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	load_packs()
	_rebuild_teams()


func _process(delta: float) -> void:
	if phase != Phase.CLUE_ACTIVE and phase != Phase.FINAL_CLUE:
		return
	if timer_paused or timer_total <= 0.0:
		return
	if is_replica:
		timer_remaining = maxf(timer_remaining - delta, 0.0)
		timer_updated.emit(timer_remaining, timer_total, timer_paused)
		return
	tick_timer(delta)


func set_random_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func load_packs() -> void:
	packs = JeopardyPack.load_all_packs()
	if packs.is_empty():
		push_warning("JeopardyGameState: no JSON packs found; building emergency fallback pack")
		packs.append(_build_fallback_pack())
	current_pack_index = clampi(current_pack_index, 0, packs.size() - 1)
	current_pack = packs[current_pack_index]
	packs_loaded.emit(packs)
	pack_changed.emit(current_pack)


func select_pack(index: int) -> void:
	if is_replica:
		remote_command_requested.emit("select_pack", {"index": index})
		return
	if packs.is_empty():
		return
	current_pack_index = posmod(index, packs.size())
	current_pack = packs[current_pack_index]
	pack_changed.emit(current_pack)
	if phase != Phase.SETUP:
		start_new_game()


func cycle_pack() -> void:
	if is_replica:
		remote_command_requested.emit("cycle_pack", {})
		return
	select_pack(current_pack_index + 1)


func set_team_count(count: int) -> void:
	if is_replica:
		remote_command_requested.emit("set_team_count", {"count": count})
		return
	team_count = clampi(count, 1, 4)
	_rebuild_teams()


func set_play_mode(mode: int) -> void:
	if is_replica:
		remote_command_requested.emit("set_play_mode", {"mode": mode})
		return
	play_mode = mode
	play_mode_changed.emit(play_mode)


func toggle_play_mode() -> void:
	if is_replica:
		remote_command_requested.emit("toggle_play_mode", {})
		return
	set_play_mode(PlayMode.HOST if play_mode == PlayMode.QUIZ else PlayMode.QUIZ)


func toggle_audio_mute() -> void:
	if is_replica:
		remote_command_requested.emit("toggle_mute", {})
		return
	set_audio_muted(not audio_muted)


func set_audio_muted(muted: bool) -> void:
	audio_muted = muted
	audio_mute_changed.emit(audio_muted)


func set_active_team(index: int) -> void:
	if index < 0 or index >= teams.size():
		return
	if is_replica:
		remote_command_requested.emit("buzz_team", {"team_index": index})
		return
	active_team_index = index
	teams_updated.emit(teams, active_team_index)


func cycle_active_team() -> void:
	if teams.is_empty():
		return
	if is_replica:
		remote_command_requested.emit("cycle_active_team", {})
		return
	set_active_team((active_team_index + 1) % teams.size())


func _rebuild_teams() -> void:
	teams = []
	for i in range(team_count):
		var preset: Dictionary = TEAM_PRESETS[i]
		teams.append({
			"index": i,
			"name": preset["name"] if team_count > 1 else "EXPLORER",
			"color": preset["color"],
			"score": 0,
			"correct": 0,
			"wrong": 0,
			"streak": 0,
			"best_streak": 0,
		})
	active_team_index = 0
	teams_updated.emit(teams, active_team_index)


func return_to_setup() -> void:
	if is_replica:
		remote_command_requested.emit("return_to_setup", {})
		return
	timer_paused = false
	_set_phase(Phase.SETUP)


func start_new_game() -> void:
	if is_replica:
		remote_command_requested.emit("start_new_game", {})
		return
	if current_pack == null:
		load_packs()
	_rebuild_teams()
	cleared_tiles.clear()
	daily_double_keys.clear()
	history.clear()
	last_result.clear()
	active_cat_idx = -1
	active_row_idx = -1
	active_clue = {}
	active_value = 0
	active_is_daily_double = false
	active_is_final = false
	host_revealed = false

	var cols := current_pack.get_category_count()
	var rows := current_pack.get_row_count()
	total_tiles = cols * rows
	remaining_tiles = total_tiles

	# Place 2 hidden Daily Doubles in middle/lower rows (rows 1..4) in distinct categories
	var candidate_keys: Array[String] = []
	for c in range(cols):
		for r in range(1, rows):
			candidate_keys.append(_tile_key(c, r))
	if not candidate_keys.is_empty():
		var first_idx := _rng.randi_range(0, candidate_keys.size() - 1)
		daily_double_keys[candidate_keys[first_idx]] = true
		var first_cat := int(candidate_keys[first_idx].split("_")[0])
		var second_pool: Array[String] = []
		for k in candidate_keys:
			if int(k.split("_")[0]) != first_cat:
				second_pool.append(k)
		if not second_pool.is_empty():
			var second_idx := _rng.randi_range(0, second_pool.size() - 1)
			daily_double_keys[second_pool[second_idx]] = true

	board_reset.emit(current_pack)
	history_updated.emit(history)
	_set_phase(Phase.BOARD)


func is_tile_cleared(cat_idx: int, row_idx: int) -> bool:
	return cleared_tiles.has(_tile_key(cat_idx, row_idx))


func is_tile_daily_double(cat_idx: int, row_idx: int) -> bool:
	return daily_double_keys.has(_tile_key(cat_idx, row_idx))


func select_tile(cat_idx: int, row_idx: int) -> bool:
	if is_replica:
		remote_command_requested.emit("select_tile", {"cat_idx": cat_idx, "row_idx": row_idx})
		return true
	if phase != Phase.BOARD or current_pack == null:
		return false
	var key := _tile_key(cat_idx, row_idx)
	if cleared_tiles.has(key):
		return false
	var clue := current_pack.get_clue(cat_idx, row_idx)
	if clue.is_empty():
		return false

	active_cat_idx = cat_idx
	active_row_idx = row_idx
	active_clue = clue
	active_value = int(clue.get("value", 200))
	active_is_final = false
	active_is_daily_double = daily_double_keys.has(key)
	host_revealed = false

	if active_is_daily_double:
		var team_score := int(teams[active_team_index]["score"])
		min_wager = 200
		max_wager = max(team_score, current_pack.get_max_clue_value())
		current_wager = clampi(int(round(float(max_wager) * 0.5 / 100.0)) * 100, min_wager, max_wager)
		_set_phase(Phase.DAILY_DOUBLE_WAGER)
		daily_double_triggered.emit(cat_idx, row_idx, active_team_index, max_wager)
		wager_updated.emit(current_wager, min_wager, max_wager)
		return true

	_begin_active_clue(active_value)
	return true


func adjust_wager(delta_amount: int) -> void:
	if is_replica:
		remote_command_requested.emit("adjust_wager", {"delta": delta_amount})
		return
	if phase != Phase.DAILY_DOUBLE_WAGER and phase != Phase.FINAL_WAGER:
		return
	current_wager = clampi(current_wager + delta_amount, min_wager, max_wager)
	wager_updated.emit(current_wager, min_wager, max_wager)


func set_wager_fraction(fraction: float) -> void:
	if is_replica:
		remote_command_requested.emit("set_wager_fraction", {"fraction": fraction})
		return
	if phase != Phase.DAILY_DOUBLE_WAGER and phase != Phase.FINAL_WAGER:
		return
	var raw := int(round(float(max_wager) * clampf(fraction, 0.0, 1.0) / 100.0)) * 100
	if fraction >= 0.99:
		raw = max_wager
	current_wager = clampi(raw, min_wager, max_wager)
	wager_updated.emit(current_wager, min_wager, max_wager)


func lock_wager() -> void:
	if is_replica:
		remote_command_requested.emit("lock_wager", {})
		return
	if phase == Phase.DAILY_DOUBLE_WAGER:
		active_value = current_wager
		_begin_active_clue(active_value)
	elif phase == Phase.FINAL_WAGER:
		final_wagers[final_wager_team_cursor] = current_wager
		final_wager_team_cursor += 1
		if final_wager_team_cursor < teams.size():
			_prepare_final_wager_for_team(final_wager_team_cursor)
		else:
			final_answer_team_cursor = 0
			_begin_final_clue_for_team(0)


func _begin_active_clue(value: int) -> void:
	active_value = value
	host_revealed = false
	timer_total = current_pack.timer_seconds
	timer_remaining = timer_total
	timer_paused = false
	_last_urgent_second = -1

	var cat_name := str(current_pack.categories[active_cat_idx].get("name", ""))
	_set_phase(Phase.CLUE_ACTIVE)
	clue_started.emit({
		"category": cat_name,
		"value": active_value,
		"clue": str(active_clue.get("clue", "")),
		"choices": active_clue.get("choices", []),
		"answer": str(active_clue.get("answer", "")),
		"fact": str(active_clue.get("fact", "")),
		"is_daily_double": active_is_daily_double,
		"is_final": false,
		"team_index": active_team_index,
		"timer_total": timer_total,
	})
	timer_updated.emit(timer_remaining, timer_total, timer_paused)
	timer_anchor_changed.emit(timer_remaining, timer_total, timer_paused, Time.get_unix_time_from_system())


func toggle_timer_pause() -> void:
	if is_replica:
		remote_command_requested.emit("toggle_timer_pause", {})
		return
	if phase != Phase.CLUE_ACTIVE and phase != Phase.FINAL_CLUE:
		return
	timer_paused = not timer_paused
	timer_updated.emit(timer_remaining, timer_total, timer_paused)
	timer_anchor_changed.emit(timer_remaining, timer_total, timer_paused, Time.get_unix_time_from_system())


func extend_timer(extra_seconds: float = 10.0) -> void:
	if is_replica:
		remote_command_requested.emit("extend_timer", {"seconds": extra_seconds})
		return
	if phase != Phase.CLUE_ACTIVE and phase != Phase.FINAL_CLUE:
		return
	timer_remaining = minf(timer_remaining + extra_seconds, timer_total + 30.0)
	timer_total = maxf(timer_total, timer_remaining)
	timer_updated.emit(timer_remaining, timer_total, timer_paused)
	timer_anchor_changed.emit(timer_remaining, timer_total, timer_paused, Time.get_unix_time_from_system())


func tick_timer(delta: float) -> void:
	if phase != Phase.CLUE_ACTIVE and phase != Phase.FINAL_CLUE:
		return
	timer_remaining = maxf(timer_remaining - delta, 0.0)
	timer_updated.emit(timer_remaining, timer_total, timer_paused)

	var sec_ceil := int(ceil(timer_remaining))
	if sec_ceil > 0 and sec_ceil <= 5 and sec_ceil != _last_urgent_second:
		_last_urgent_second = sec_ceil
		timer_urgent_tick.emit(sec_ceil)

	if timer_remaining <= 0.0:
		submit_time_up()


func submit_choice(choice_index: int) -> bool:
	if is_replica:
		remote_command_requested.emit("submit_choice", {"choice_index": choice_index})
		return true
	if phase != Phase.CLUE_ACTIVE and phase != Phase.FINAL_CLUE:
		return false
	var correct_idx := int(active_clue.get("correct_index", 0))
	var was_correct := choice_index == correct_idx
	_resolve_clue(was_correct, false, false, choice_index)
	return was_correct


func reveal_host_answer() -> void:
	if is_replica:
		remote_command_requested.emit("reveal_host_answer", {})
		return
	if phase != Phase.CLUE_ACTIVE and phase != Phase.FINAL_CLUE:
		return
	host_revealed = true
	host_answer_revealed.emit(str(active_clue.get("answer", "")))


func submit_host_judgment(was_correct: bool, is_pass: bool = false) -> void:
	if is_replica:
		remote_command_requested.emit("submit_host_judgment", {"was_correct": was_correct, "is_pass": is_pass})
		return
	if phase != Phase.CLUE_ACTIVE and phase != Phase.FINAL_CLUE:
		return
	_resolve_clue(was_correct, false, is_pass, -1)


func submit_time_up() -> void:
	if phase != Phase.CLUE_ACTIVE and phase != Phase.FINAL_CLUE:
		return
	_resolve_clue(false, true, false, -1)


func _resolve_clue(was_correct: bool, timed_out: bool, is_pass: bool, chosen_index: int) -> void:
	var team: Dictionary = teams[active_team_index]
	var wager_used := active_value
	if active_is_final and active_team_index < final_wagers.size():
		wager_used = final_wagers[active_team_index]

	var score_delta := 0
	if was_correct:
		score_delta = wager_used
		team["score"] = int(team["score"]) + score_delta
		team["correct"] = int(team["correct"]) + 1
		team["streak"] = int(team["streak"]) + 1
		team["best_streak"] = max(int(team["best_streak"]), int(team["streak"]))
	elif is_pass:
		score_delta = 0
		team["streak"] = 0
	elif not timed_out or active_is_daily_double or active_is_final:
		score_delta = -wager_used
		team["score"] = int(team["score"]) + score_delta
		team["wrong"] = int(team["wrong"]) + 1
		team["streak"] = 0
	else:
		team["streak"] = 0

	teams[active_team_index] = team

	var category_name := ""
	if active_is_final:
		category_name = str(active_clue.get("category", "FINAL JEOPARDY"))
	else:
		category_name = str(current_pack.categories[active_cat_idx].get("name", ""))
		var key := _tile_key(active_cat_idx, active_row_idx)
		if not cleared_tiles.has(key):
			cleared_tiles[key] = true
			remaining_tiles = max(0, remaining_tiles - 1)
			tile_cleared.emit(active_cat_idx, active_row_idx, was_correct)

	var outcome_label := "CORRECT"
	if not was_correct:
		if is_pass:
			outcome_label = "PASSED"
		elif timed_out:
			outcome_label = "TIME UP"
		else:
			outcome_label = "INCORRECT"

	last_result = {
		"category": category_name,
		"value": wager_used,
		"was_correct": was_correct,
		"timed_out": timed_out,
		"is_pass": is_pass,
		"outcome": outcome_label,
		"score_delta": score_delta,
		"team_index": active_team_index,
		"team_name": str(team["name"]),
		"team_color": team["color"],
		"chosen_index": chosen_index,
		"correct_index": int(active_clue.get("correct_index", 0)),
		"answer": str(active_clue.get("answer", "")),
		"fact": str(active_clue.get("fact", "")),
		"is_daily_double": active_is_daily_double,
		"is_final": active_is_final,
	}

	history.push_front({
		"category": category_name,
		"value": wager_used,
		"answer": str(active_clue.get("answer", "")),
		"outcome": outcome_label,
		"was_correct": was_correct,
		"team_name": str(team["name"]),
	})
	if history.size() > 8:
		history.resize(8)

	# On incorrect/timeout/pass in multiplayer board rounds, rotate turn cleanly
	if not was_correct and not active_is_final and teams.size() > 1:
		active_team_index = (active_team_index + 1) % teams.size()

	teams_updated.emit(teams, active_team_index)
	history_updated.emit(history)
	_set_phase(Phase.CLUE_RESULT)
	clue_resolved.emit(last_result)


func continue_after_result() -> void:
	if is_replica:
		remote_command_requested.emit("continue_after_result", {})
		return
	if phase != Phase.CLUE_RESULT:
		return
	if active_is_final:
		final_answer_team_cursor += 1
		if final_answer_team_cursor < teams.size():
			_begin_final_clue_for_team(final_answer_team_cursor)
		else:
			_finish_game()
		return
	if remaining_tiles <= 0:
		begin_final_jeopardy()
	else:
		_set_phase(Phase.BOARD)


func begin_final_jeopardy() -> void:
	if is_replica:
		remote_command_requested.emit("begin_final_jeopardy", {})
		return
	if current_pack == null or current_pack.final_jeopardy.is_empty():
		_finish_game()
		return
	active_is_final = true
	active_is_daily_double = false
	active_cat_idx = -1
	active_row_idx = -1
	active_clue = current_pack.final_jeopardy
	final_wagers = []
	for _i in range(teams.size()):
		final_wagers.append(0)
	final_wager_team_cursor = 0
	final_answer_team_cursor = 0
	_set_phase(Phase.FINAL_WAGER)
	_prepare_final_wager_for_team(0)


func _prepare_final_wager_for_team(team_idx: int) -> void:
	set_active_team(team_idx)
	var score := int(teams[team_idx]["score"])
	min_wager = 0
	max_wager = max(score, 1000)
	current_wager = clampi(int(round(float(max_wager) * 0.5 / 100.0)) * 100, min_wager, max_wager)
	wager_updated.emit(current_wager, min_wager, max_wager)


func _begin_final_clue_for_team(team_idx: int) -> void:
	set_active_team(team_idx)
	active_value = final_wagers[team_idx] if team_idx < final_wagers.size() else 500
	host_revealed = false
	timer_total = 30.0
	timer_remaining = timer_total
	timer_paused = false
	_last_urgent_second = -1
	_set_phase(Phase.FINAL_CLUE)
	clue_started.emit({
		"category": str(active_clue.get("category", "FINAL JEOPARDY")),
		"value": active_value,
		"clue": str(active_clue.get("clue", "")),
		"choices": active_clue.get("choices", []),
		"answer": str(active_clue.get("answer", "")),
		"fact": str(active_clue.get("fact", "")),
		"is_daily_double": false,
		"is_final": true,
		"team_index": active_team_index,
		"timer_total": timer_total,
	})
	timer_updated.emit(timer_remaining, timer_total, timer_paused)
	timer_anchor_changed.emit(timer_remaining, timer_total, timer_paused, Time.get_unix_time_from_system())


func _finish_game() -> void:
	_set_phase(Phase.GAME_OVER)
	game_finished.emit(get_standings())


# ------------------------------------------------------------------------------
# SYNC SNAPSHOT SERIALIZATION & HYDRATION (ALL 5 SURFACES)
# ------------------------------------------------------------------------------
func export_sync_snapshot() -> Dictionary:
	var ser_teams: Array[Dictionary] = []
	for t in teams:
		var col: Color = t["color"]
		ser_teams.append({
			"index": int(t["index"]),
			"name": str(t["name"]),
			"color": col.to_html(false),
			"score": int(t["score"]),
			"correct": int(t["correct"]),
			"wrong": int(t["wrong"]),
			"streak": int(t["streak"]),
			"best_streak": int(t["best_streak"]),
		})

	var ser_history: Array[Dictionary] = []
	for item in history:
		ser_history.append(item.duplicate())

	var ser_result := {}
	if not last_result.is_empty():
		ser_result = {
			"category": str(last_result.get("category", "")),
			"value": int(last_result.get("value", 0)),
			"was_correct": bool(last_result.get("was_correct", false)),
			"timed_out": bool(last_result.get("timed_out", false)),
			"is_pass": bool(last_result.get("is_pass", false)),
			"outcome": str(last_result.get("outcome", "")),
			"score_delta": int(last_result.get("score_delta", 0)),
			"team_index": int(last_result.get("team_index", 0)),
			"team_name": str(last_result.get("team_name", "")),
			"answer": str(last_result.get("answer", "")),
			"fact": str(last_result.get("fact", "")),
			"is_daily_double": bool(last_result.get("is_daily_double", false)),
			"is_final": bool(last_result.get("is_final", false)),
		}

	return {
		"phase": phase,
		"play_mode": play_mode,
		"audio_muted": audio_muted,
		"pack_index": current_pack_index,
		"teams": ser_teams,
		"active_team_index": active_team_index,
		"remaining_tiles": remaining_tiles,
		"total_tiles": total_tiles,
		"cleared_keys": cleared_tiles.keys(),
		"active_cat_idx": active_cat_idx,
		"active_row_idx": active_row_idx,
		"active_value": active_value,
		"active_is_daily_double": active_is_daily_double,
		"active_is_final": active_is_final,
		"host_revealed": host_revealed,
		"current_wager": current_wager,
		"min_wager": min_wager,
		"max_wager": max_wager,
		"final_wager_team_cursor": final_wager_team_cursor,
		"final_answer_team_cursor": final_answer_team_cursor,
		"timer_remaining": timer_remaining,
		"timer_total": timer_total,
		"timer_paused": timer_paused,
		"timer_anchor_unix": Time.get_unix_time_from_system(),
		"history": ser_history,
		"last_result": ser_result,
	}


func apply_sync_snapshot(snap: Dictionary) -> void:
	var old_phase := phase
	var old_mode := play_mode
	var old_muted := audio_muted

	var new_pack_idx := int(snap.get("pack_index", current_pack_index))
	if not packs.is_empty() and new_pack_idx >= 0 and new_pack_idx < packs.size() and new_pack_idx != current_pack_index:
		current_pack_index = new_pack_idx
		current_pack = packs[current_pack_index]
		pack_changed.emit(current_pack)

	play_mode = int(snap.get("play_mode", play_mode))
	if play_mode != old_mode:
		play_mode_changed.emit(play_mode)

	audio_muted = bool(snap.get("audio_muted", audio_muted))
	if audio_muted != old_muted:
		audio_mute_changed.emit(audio_muted)

	remaining_tiles = int(snap.get("remaining_tiles", remaining_tiles))
	total_tiles = int(snap.get("total_tiles", total_tiles))
	active_cat_idx = int(snap.get("active_cat_idx", -1))
	active_row_idx = int(snap.get("active_row_idx", -1))
	active_value = int(snap.get("active_value", active_value))
	active_is_daily_double = bool(snap.get("active_is_daily_double", false))
	active_is_final = bool(snap.get("active_is_final", false))
	host_revealed = bool(snap.get("host_revealed", false))
	current_wager = int(snap.get("current_wager", current_wager))
	min_wager = int(snap.get("min_wager", min_wager))
	max_wager = int(snap.get("max_wager", max_wager))
	final_wager_team_cursor = int(snap.get("final_wager_team_cursor", 0))
	final_answer_team_cursor = int(snap.get("final_answer_team_cursor", 0))

	# Reconstruct cleared_tiles & active_clue from shared pack
	cleared_tiles.clear()
	var raw_keys: Variant = snap.get("cleared_keys", [])
	if raw_keys is Array:
		for k in raw_keys as Array:
			cleared_tiles[str(k)] = true

	if current_pack != null:
		if active_is_final:
			active_clue = current_pack.final_jeopardy
		elif active_cat_idx >= 0 and active_row_idx >= 0:
			active_clue = current_pack.get_clue(active_cat_idx, active_row_idx)
		else:
			active_clue = {}

	var raw_teams: Variant = snap.get("teams", [])
	if raw_teams is Array and not (raw_teams as Array).is_empty():
		var rebuilt: Array[Dictionary] = []
		for item in raw_teams as Array:
			if item is Dictionary:
				var d := item as Dictionary
				var col_str := str(d.get("color", "47e6f5"))
				if not col_str.begins_with("#"):
					col_str = "#" + col_str
				rebuilt.append({
					"index": int(d.get("index", rebuilt.size())),
					"name": str(d.get("name", "TEAM")),
					"color": Color.from_string(col_str, Color(0.28, 0.90, 0.96)),
					"score": int(d.get("score", 0)),
					"correct": int(d.get("correct", 0)),
					"wrong": int(d.get("wrong", 0)),
					"streak": int(d.get("streak", 0)),
					"best_streak": int(d.get("best_streak", 0)),
				})
		teams = rebuilt
		team_count = teams.size()

	active_team_index = clampi(int(snap.get("active_team_index", 0)), 0, max(teams.size() - 1, 0))
	teams_updated.emit(teams, active_team_index)

	var raw_history: Variant = snap.get("history", null)
	if raw_history is Array:
		history = []
		for h in raw_history as Array:
			if h is Dictionary:
				history.append((h as Dictionary).duplicate())
		history_updated.emit(history)

	var raw_result: Variant = snap.get("last_result", null)
	if raw_result is Dictionary and not (raw_result as Dictionary).is_empty():
		last_result = (raw_result as Dictionary).duplicate()

	var new_phase := int(snap.get("phase", phase))
	phase = new_phase
	if new_phase != old_phase:
		phase_changed.emit(new_phase, old_phase)

	if phase == Phase.DAILY_DOUBLE_WAGER or phase == Phase.FINAL_WAGER:
		wager_updated.emit(current_wager, min_wager, max_wager)

	apply_remote_timer_anchor(
		float(snap.get("timer_remaining", timer_remaining)),
		float(snap.get("timer_total", timer_total)),
		bool(snap.get("timer_paused", timer_paused)),
		float(snap.get("timer_anchor_unix", 0.0)),
	)


func apply_remote_timer_anchor(rem: float, total: float, paused: bool, anchor_unix: float) -> void:
	timer_total = maxf(total, 0.01)
	timer_paused = paused
	var adjusted := rem
	if not paused and anchor_unix > 0.0 and (phase == Phase.CLUE_ACTIVE or phase == Phase.FINAL_CLUE):
		var elapsed := clampf(Time.get_unix_time_from_system() - anchor_unix, 0.0, timer_total)
		adjusted = maxf(rem - elapsed, 0.0)
	timer_remaining = clampf(adjusted, 0.0, timer_total)
	if phase == Phase.CLUE_ACTIVE or phase == Phase.FINAL_CLUE:
		timer_updated.emit(timer_remaining, timer_total, timer_paused)


func apply_remote_clue_resolved(res: Dictionary) -> void:
	last_result = res.duplicate(true)
	clue_resolved.emit(last_result)


func get_standings() -> Array[Dictionary]:
	var sorted: Array[Dictionary] = []
	for t in teams:
		sorted.append(t.duplicate())
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) > int(b["score"])
	)
	return sorted


func get_ephemeral_progress() -> float:
	if total_tiles <= 0:
		return 0.0
	return clampf(1.0 - float(remaining_tiles) / float(total_tiles), 0.0, 1.0)


func _set_phase(new_phase: int) -> void:
	var old_phase := phase
	phase = new_phase
	phase_changed.emit(new_phase, old_phase)


static func _tile_key(cat_idx: int, row_idx: int) -> String:
	return "%d_%d" % [cat_idx, row_idx]


static func _build_fallback_pack() -> JeopardyPack:
	var cats := []
	for c in range(5):
		var clues := []
		for r in range(5):
			var val := (r + 1) * 200
			clues.append({
				"value": val,
				"clue": "Placeholder ephemeral clue %d-%d." % [c + 1, r + 1],
				"choices": ["Alpha", "Beta", "Gamma", "Delta"],
				"correct_index": r % 4,
				"answer": "What is %s?" % ["Alpha", "Beta", "Gamma", "Delta"][r % 4],
				"fact": "Drop JSON files into data/packs/ to customize.",
			})
		cats.append({"name": "CATEGORY %d" % (c + 1), "short_name": "CAT %d" % (c + 1), "clues": clues})
	return JeopardyPack.from_dictionary({
		"id": "fallback",
		"title": "Ephemeral Demo",
		"subtitle": "Fallback question pack",
		"accent_color": "#5ce1e6",
		"timer_seconds": 25,
		"categories": cats,
		"final_jeopardy": {
			"category": "THE LAST ECHO",
			"clue": "This force keeps planets orbiting the Sun.",
			"choices": ["Magnetism", "Gravity", "Friction", "Inertia"],
			"correct_index": 1,
			"answer": "What is Gravity?",
			"fact": "Spacetime curvature guides celestial motion.",
		},
	})
