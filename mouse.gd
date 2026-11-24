extends Control
class_name MultitouchMouse

## Projects single-touch (or optional multi-touch) screen input across the 5 aligned
## projector SubViewportContainers into 3D world raycasts and emits InteractionBus events.

@export var viewport_count: int = 5
@export var single_touch_only: bool = true
@export var tap_cooldown_sec: float = 0.14
@export var ray_distance: float = 100.0
@export var show_touch_ripple: bool = true
@export var show_debug_touch_box: bool = false
@export var ripple_color: Color = Color(0.45, 0.92, 1.0, 0.9)

@onready var hbox: HBoxContainer = $".."

# { touch_index: { "orb": ColorRect, "last_collider": Object, "viewport_index": int } }
var active_touches: Dictionary = {}
var _active_single_touch_index: int = -1
var _last_tap_msec: int = 0
var _ripples: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if has_node("ColorRect"):
		$ColorRect.visible = false
	set_process(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_reset_all_touches()


func _reset_all_touches() -> void:
	var indices := active_touches.keys()
	for touch_index in indices:
		_cancel_touch(int(touch_index), Vector2.ZERO)
	_active_single_touch_index = -1


func _process(delta: float) -> void:
	if _ripples.is_empty():
		return
	var write_idx := 0
	for i in range(_ripples.size()):
		var ripple: Dictionary = _ripples[i]
		ripple["age"] = float(ripple["age"]) + delta
		if float(ripple["age"]) < float(ripple["duration"]):
			_ripples[write_idx] = ripple
			write_idx += 1
	_ripples.resize(write_idx)
	queue_redraw()


func _draw() -> void:
	if not show_touch_ripple or _ripples.is_empty():
		return
	for ripple in _ripples:
		var pos: Vector2 = ripple["pos"]
		var age: float = float(ripple["age"])
		var duration: float = float(ripple["duration"])
		var t: float = clampf(age / duration, 0.0, 1.0)
		var ease_t: float = 1.0 - pow(1.0 - t, 3.0)
		var alpha: float = (1.0 - t) * (1.0 - t)
		var base_col: Color = ripple["color"]

		# Outer expanding luminous ring
		var radius: float = lerpf(10.0, 58.0, ease_t)
		var ring_col := Color(base_col.r, base_col.g, base_col.b, alpha * 0.85)
		draw_arc(pos, radius, 0.0, TAU, 36, ring_col, lerpf(3.2, 1.0, t), true)

		# Secondary softer halo ring
		var inner_radius: float = lerpf(4.0, 32.0, ease_t)
		var inner_col := Color(1.0, 0.94, 0.78, alpha * 0.55)
		draw_arc(pos, inner_radius, 0.0, TAU, 28, inner_col, 1.6, true)

		# Brief bright center spark
		if t < 0.35:
			var spark_alpha: float = (1.0 - t / 0.35) * 0.7
			draw_circle(pos, lerpf(6.0, 1.5, t / 0.35), Color(1.0, 0.98, 0.9, spark_alpha))


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.canceled:
			_cancel_touch(touch_event.index, touch_event.position)
			return
		if touch_event.pressed:
			if single_touch_only and _active_single_touch_index != -1 and _active_single_touch_index != touch_event.index:
				return
			_active_single_touch_index = touch_event.index
			_start_touch(touch_event.index, touch_event.position)
			_process_raycast(touch_event.index, touch_event.position, true, false)
		else:
			if single_touch_only and _active_single_touch_index != touch_event.index:
				return
			_process_raycast(touch_event.index, touch_event.position, false, true)
			_end_touch(touch_event.index)
			if _active_single_touch_index == touch_event.index:
				_active_single_touch_index = -1

	elif event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if single_touch_only and _active_single_touch_index != drag_event.index:
			return
		if not active_touches.has(drag_event.index):
			return
		_update_touch_visual(drag_event.index, drag_event.position)
		_process_raycast(drag_event.index, drag_event.position, false, false)


func spawn_screen_ripple(screen_pos: Vector2, color: Color = ripple_color, duration: float = 0.55) -> void:
	if not show_touch_ripple:
		return
	var local_pos := screen_pos - global_position
	_ripples.append({
		"pos": local_pos,
		"age": 0.0,
		"duration": duration,
		"color": color,
	})
	queue_redraw()


func _start_touch(touch_index: int, screen_pos: Vector2) -> void:
	var new_orb: ColorRect = null
	if show_debug_touch_box:
		new_orb = ColorRect.new()
		new_orb.size = Vector2(18, 18)
		new_orb.color = Color(0.3, 1.0, 0.7, 0.75)
		new_orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(new_orb)
		new_orb.global_position = screen_pos - (new_orb.size / 2.0)

	active_touches[touch_index] = {
		"orb": new_orb,
		"last_collider": null,
		"viewport_index": 0,
	}
	spawn_screen_ripple(screen_pos)


func _update_touch_visual(touch_index: int, screen_pos: Vector2) -> void:
	if not active_touches.has(touch_index):
		return
	var orb: ColorRect = active_touches[touch_index]["orb"]
	if is_instance_valid(orb):
		orb.global_position = screen_pos - (orb.size / 2.0)


func _cancel_touch(touch_index: int, screen_pos: Vector2) -> void:
	if active_touches.has(touch_index):
		var last_collider: Object = active_touches[touch_index]["last_collider"]
		if is_instance_valid(last_collider):
			InteractionBus.ray_click_release.emit(last_collider)
			InteractionBus.ray_exit.emit(last_collider)
		_end_touch(touch_index)
	if _active_single_touch_index == touch_index:
		_active_single_touch_index = -1


func _end_touch(touch_index: int) -> void:
	if not active_touches.has(touch_index):
		return
	var orb: ColorRect = active_touches[touch_index]["orb"]
	if is_instance_valid(orb):
		orb.queue_free()
	active_touches.erase(touch_index)


func _resolve_viewport_container(screen_pos: Vector2) -> Dictionary:
	var containers: Array[SubViewportContainer] = []
	for child in hbox.get_children():
		if child is SubViewportContainer:
			containers.append(child as SubViewportContainer)

	# Primary lookup: exact visible container rect match (handles arbitrary scaling & F3 solo preview)
	for i in range(containers.size()):
		var container := containers[i]
		if not container.visible:
			continue
		var rect := container.get_global_rect()
		if rect.size.x > 0.0 and rect.size.y > 0.0 and rect.has_point(screen_pos):
			return {"index": i, "container": container, "rect": rect}

	# Fallback: clamped proportional slice across visible containers
	var visible_indices: Array[int] = []
	for i in range(containers.size()):
		if containers[i].visible:
			visible_indices.append(i)
	if visible_indices.is_empty():
		return {}

	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var slice_w: float = maxf(view_size.x / float(visible_indices.size()), 1.0)
	var local_slot: int = clampi(int(screen_pos.x / slice_w), 0, visible_indices.size() - 1)
	var mapped_idx: int = visible_indices[local_slot]
	var mapped_container := containers[mapped_idx]
	return {
		"index": mapped_idx,
		"container": mapped_container,
		"rect": mapped_container.get_global_rect(),
	}


func _process_raycast(
	touch_index: int,
	screen_pos: Vector2,
	just_pressed: bool,
	just_released: bool,
) -> void:
	if not active_touches.has(touch_index):
		return

	var resolved := _resolve_viewport_container(screen_pos)
	if resolved.is_empty():
		return

	var vp_index: int = resolved["index"]
	var container: SubViewportContainer = resolved["container"]
	var rect: Rect2 = resolved["rect"]
	var subviewport: SubViewport = container.get_node_or_null("SubViewport") as SubViewport
	if subviewport == null:
		return
	var camera: Camera3D = subviewport.get_camera_3d()
	if camera == null:
		return

	var local_pos := (screen_pos - rect.position).clamp(Vector2.ZERO, rect.size)
	# Scale local coordinates into SubViewport pixel coordinates if stretch_shrink or sizing differs
	if rect.size.x > 0.0 and rect.size.y > 0.0:
		var sv_size := Vector2(subviewport.size)
		local_pos = Vector2(
			local_pos.x * (sv_size.x / rect.size.x),
			local_pos.y * (sv_size.y / rect.size.y),
		)

	var ray_origin := camera.project_ray_origin(local_pos)
	var ray_dir := camera.project_ray_normal(local_pos)
	var ray_end := ray_origin + ray_dir * ray_distance
	var ray_pos := [ray_origin, ray_dir, ray_end]

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var space_state := subviewport.world_3d.direct_space_state
	var result := space_state.intersect_ray(query)

	var current_collider: Object = null
	var hit_pos := ray_origin + ray_dir * 4.0
	var hit_normal := -ray_dir
	if not result.is_empty():
		current_collider = result.get("collider", null)
		hit_pos = result.get("position", hit_pos)
		hit_normal = result.get("normal", hit_normal)
		InteractionBus.ray_hover.emit(current_collider, ray_pos)

	var touch_data: Dictionary = active_touches[touch_index]
	var last_collider: Object = touch_data["last_collider"]
	if not is_instance_valid(last_collider):
		last_collider = null

	# Fix collider enter/exit transitions (including A -> B direct drag)
	if last_collider != current_collider:
		if last_collider != null:
			InteractionBus.ray_exit.emit(last_collider)
		if current_collider != null and not just_released:
			InteractionBus.ray_enter.emit(current_collider)

	if just_pressed:
		InteractionBus.touch_began.emit(screen_pos, vp_index, current_collider, hit_pos, hit_normal)
		InteractionBus.touch_ripple.emit(hit_pos, hit_normal, vp_index, ripple_color)
		if current_collider != null:
			InteractionBus.ray_click.emit(current_collider)
			var now_msec := Time.get_ticks_msec()
			if float(now_msec - _last_tap_msec) / 1000.0 >= tap_cooldown_sec:
				_last_tap_msec = now_msec
				InteractionBus.single_touch_tap.emit(current_collider, hit_pos, hit_normal, vp_index)
	elif just_released:
		InteractionBus.touch_ended.emit(screen_pos, vp_index, current_collider, hit_pos, hit_normal)
		if current_collider != null:
			InteractionBus.ray_click_release.emit(current_collider)
		elif last_collider != null:
			InteractionBus.ray_click_release.emit(last_collider)
		# Always emit exit on touch release so hover state never sticks on touch devices
		if current_collider != null:
			InteractionBus.ray_exit.emit(current_collider)
		touch_data["last_collider"] = null
		return
	else:
		InteractionBus.touch_moved.emit(screen_pos, vp_index, current_collider, hit_pos, hit_normal)

	touch_data["last_collider"] = current_collider
	touch_data["viewport_index"] = vp_index
