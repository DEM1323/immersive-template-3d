extends Node3D
class_name Player

## Physical 5-Projector Immersive Room Rig.
## Cameras are aligned to Left (-X), Center (-Z), Right (+X), Back (+Z), and Floor (-Y)
## from world origin (0, 1.5, 0) with 90-degree horizontal FOV (KEEP_WIDTH).
## NEVER move, tilt, or shake these cameras during gameplay.

enum DisplayMode {
	ALL_5,
	WALLS_4,
	FLOOR_ONLY,
}

# gdlint:disable=class-variable-name
@export var CameraLeft: Camera3D
@export var CameraCenter: Camera3D
@export var CameraRight: Camera3D
@export var CameraBack: Camera3D
@export var CameraFloor: Camera3D
@export var ViewportLeft: SubViewportContainer
@export var ViewportCenter: SubViewportContainer
@export var ViewportRight: SubViewportContainer
@export var ViewportBack: SubViewportContainer
@export var ViewportFloor: SubViewportContainer
@export var Viewports: int = 5
# gdlint:enable=class-variable-name
@export var show_calibration_labels: bool = false
@export var show_debug_hud: bool = false

@onready var hbox: HBoxContainer = $Transform/HBoxContainer
@onready var controller: MultitouchMouse = $Transform/HBoxContainer/Control

var display_mode: int = DisplayMode.ALL_5
var sync_status_text: String = ""

# -1 = show all active slots for current display_mode; 0..4 = desktop single-wall preview only
var _preview_wall_index: int = -1


func _ready() -> void:
	init_viewports()
	_apply_overlay_visibility()
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _process(_delta: float) -> void:
	if not show_debug_hud:
		return
	var fps_lbl: Label = $Transform/FPS
	var mode_text := get_display_mode_name()
	if _preview_wall_index != -1:
		mode_text = get_wall_name(_preview_wall_index)
	var suffix := "" if sync_status_text.is_empty() else " | SYNC:%s" % sync_status_text
	fps_lbl.text = "FPS: %d | %s%s" % [Engine.get_frames_per_second(), mode_text, suffix]


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_F1:
			show_calibration_labels = not show_calibration_labels
			_apply_overlay_visibility()
		KEY_F2:
			show_debug_hud = not show_debug_hud
			_apply_overlay_visibility()
		KEY_F3:
			_cycle_preview_wall()
		KEY_0:
			if _preview_wall_index != -1:
				_preview_wall_index = -1
				_refresh_viewport_sizes()


func _cycle_preview_wall() -> void:
	var active := get_active_viewport_indices()
	if active.size() <= 1:
		_preview_wall_index = -1
		_refresh_viewport_sizes()
		return
	if _preview_wall_index == -1:
		_preview_wall_index = active[0]
	else:
		var pos := active.find(_preview_wall_index)
		_preview_wall_index = -1 if (pos == -1 or pos >= active.size() - 1) else active[pos + 1]
	_refresh_viewport_sizes()


func _on_viewport_size_changed() -> void:
	_refresh_viewport_sizes()


# Helper function to initialize viewports. Preserves physical projector alignment.
func init_viewports() -> void:
	_refresh_viewport_sizes()

	var main_world := get_viewport().world_3d
	for container in hbox.get_children():
		if container.is_class("SubViewportContainer"):
			var sv := container.get_node_or_null("SubViewport")
			if sv == null:
				push_warning("No SubViewport found in " + str(container))
				continue
			sv.world_3d = main_world
			sv.msaa_3d = Viewport.MSAA_2X


func set_display_mode(mode: int) -> void:
	display_mode = mode
	_preview_wall_index = -1
	if is_inside_tree():
		_refresh_viewport_sizes()


func get_active_viewport_indices() -> Array[int]:
	match display_mode:
		DisplayMode.WALLS_4:
			return [0, 1, 2, 3]
		DisplayMode.FLOOR_ONLY:
			return [4]
		_:
			return [0, 1, 2, 3, 4]


func get_display_mode_name() -> String:
	match display_mode:
		DisplayMode.WALLS_4:
			return "4-WALLS"
		DisplayMode.FLOOR_ONLY:
			return "FLOOR"
		_:
			return "5-WALL"


func _refresh_viewport_sizes() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var w: int = max(int(view.x), 1)
	var h: int = max(int(view.y), 1)

	var containers := get_subviewport_containers()
	var shown_indices: Array[int] = []
	if _preview_wall_index != -1:
		shown_indices = [_preview_wall_index]
	else:
		shown_indices = get_active_viewport_indices()

	var count: int = maxi(shown_indices.size(), 1)
	controller.viewport_count = count

	var slice_w: int = int(floor(float(w) / float(count)))
	var remainder: int = w - slice_w * count

	var slot_cursor := 0
	for i in range(containers.size()):
		var container := containers[i]
		var is_shown := i in shown_indices
		container.visible = is_shown
		if is_shown:
			var extra := 1 if slot_cursor < remainder else 0
			container.custom_minimum_size = Vector2(slice_w + extra, h)
			slot_cursor += 1

	hbox.position = Vector2.ZERO
	hbox.size = Vector2(w, h)
	var size_lbl: Label = $Transform/Size
	if _preview_wall_index == -1:
		size_lbl.text = "Size: %d, %d (x%d %s)" % [slice_w, h, count, get_display_mode_name()]
	else:
		size_lbl.text = "Preview [%s]: %d, %d" % [get_wall_name(_preview_wall_index), w, h]


func _apply_overlay_visibility() -> void:
	var cameras := get_cameras()
	for cam in cameras:
		if cam == null:
			continue
		for child in cam.get_children():
			if child is Label3D:
				child.visible = show_calibration_labels

	if has_node("Transform/Size"):
		$Transform/Size.visible = show_debug_hud
	if has_node("Transform/FPS"):
		$Transform/FPS.visible = show_debug_hud


func get_cameras() -> Array[Camera3D]:
	return [CameraLeft, CameraCenter, CameraRight, CameraBack, CameraFloor]


func get_subviewport_containers() -> Array[SubViewportContainer]:
	return [ViewportLeft, ViewportCenter, ViewportRight, ViewportBack, ViewportFloor]


func get_wall_name(index: int) -> String:
	match index:
		0:
			return "LEFT"
		1:
			return "CENTER"
		2:
			return "RIGHT"
		3:
			return "BACK"
		4:
			return "FLOOR"
		_:
			return "ALL"


func set_preview_wall(index: int) -> void:
	if index == -1:
		_preview_wall_index = -1
	else:
		_preview_wall_index = clampi(index, 0, Viewports - 1)
	_refresh_viewport_sizes()
