@tool
extends StaticBody3D
class_name ImmersiveInteractable3D

## Reusable 3D single-touch interactable base class for 5-wall projector environments.
## Automatically disables its physics collision layer whenever hidden in the scene tree
## so inactive panels can never capture stray raycasts.
## Runs as a @tool so subclasses can preview live in the Godot Editor; every input, physics-layer,
## and InteractionBus side effect is skipped there so nothing leaks into the saved scene.

const BUS_PATH := ^"/root/InteractionBus"

signal tapped(interactable: ImmersiveInteractable3D, hit_pos: Vector3, viewport_index: int)
signal pressed_changed(is_pressed: bool)
signal hover_changed(is_hovered: bool)

@export var interaction_enabled: bool = true:
	set(value):
		interaction_enabled = value
		_sync_collision_state()

@export var active_collision_layer: int = 1
@export var local_cooldown_sec: float = 0.16

var is_hovering: bool = false
var is_pressed: bool = false
var last_hit_pos: Vector3 = Vector3.ZERO
var last_viewport_index: int = -1

var _last_tap_msec: int = -10000


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	collision_mask = 0
	_connect_bus()
	_sync_collision_state()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE:
		_sync_collision_state()


func _connect_bus() -> void:
	if Engine.is_editor_hint():
		return
	# Resolved by path (not by autoload identifier) so this @tool script always compiles in the editor.
	var bus := get_node_or_null(BUS_PATH)
	if bus == null:
		return
	var handlers := {
		&"single_touch_tap": _on_bus_single_touch_tap,
		&"ray_enter": _on_bus_ray_enter,
		&"ray_exit": _on_bus_ray_exit,
		&"ray_click": _on_bus_ray_click,
		&"ray_click_release": _on_bus_ray_click_release,
	}
	for bus_signal: StringName in handlers:
		var handler: Callable = handlers[bus_signal]
		if not bus.is_connected(bus_signal, handler):
			bus.connect(bus_signal, handler)


func _sync_collision_state() -> void:
	# The editor must never serialize a runtime-computed layer, and a node outside the tree
	# cannot be hit anyway (ENTER_TREE re-syncs it before the first physics query).
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	var can_hit := interaction_enabled and is_visible_in_tree()
	collision_layer = active_collision_layer if can_hit else 0
	if not can_hit:
		if is_pressed:
			is_pressed = false
			pressed_changed.emit(false)
		if is_hovering:
			is_hovering = false
			hover_changed.emit(false)


func set_interactable_active(active: bool) -> void:
	interaction_enabled = active


func trigger_tap(hit_pos: Vector3 = global_position, viewport_index: int = -1) -> void:
	if Engine.is_editor_hint() or not interaction_enabled or not is_visible_in_tree():
		return
	var now_msec := Time.get_ticks_msec()
	if float(now_msec - _last_tap_msec) / 1000.0 < local_cooldown_sec:
		return
	_last_tap_msec = now_msec
	last_hit_pos = hit_pos
	last_viewport_index = viewport_index
	_on_tapped_visual()
	tapped.emit(self, hit_pos, viewport_index)


func _on_bus_single_touch_tap(
	collider: Object,
	hit_pos: Vector3,
	_hit_normal: Vector3,
	viewport_index: int,
) -> void:
	if collider == self:
		trigger_tap(hit_pos, viewport_index)


func _on_bus_ray_enter(collider: Object) -> void:
	if collider == self and interaction_enabled and is_visible_in_tree():
		is_hovering = true
		hover_changed.emit(true)


func _on_bus_ray_exit(collider: Object) -> void:
	if collider == self and is_hovering:
		is_hovering = false
		hover_changed.emit(false)


func _on_bus_ray_click(collider: Object) -> void:
	if collider == self and interaction_enabled and is_visible_in_tree():
		is_pressed = true
		pressed_changed.emit(true)


func _on_bus_ray_click_release(collider: Object) -> void:
	if collider == self and is_pressed:
		is_pressed = false
		pressed_changed.emit(false)


## Override in subclasses for tactile press visuals.
func _on_tapped_visual() -> void:
	pass
