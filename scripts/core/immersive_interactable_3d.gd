extends StaticBody3D
class_name ImmersiveInteractable3D

## Reusable 3D single-touch interactable base class for 5-wall projector environments.
## Automatically disables its physics collision layer whenever hidden in the scene tree
## so inactive panels can never capture stray raycasts.

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
	collision_mask = 0
	_connect_bus()
	_sync_collision_state()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE:
		_sync_collision_state()


func _connect_bus() -> void:
	if not InteractionBus.single_touch_tap.is_connected(_on_bus_single_touch_tap):
		InteractionBus.single_touch_tap.connect(_on_bus_single_touch_tap)
	if not InteractionBus.ray_enter.is_connected(_on_bus_ray_enter):
		InteractionBus.ray_enter.connect(_on_bus_ray_enter)
	if not InteractionBus.ray_exit.is_connected(_on_bus_ray_exit):
		InteractionBus.ray_exit.connect(_on_bus_ray_exit)
	if not InteractionBus.ray_click.is_connected(_on_bus_ray_click):
		InteractionBus.ray_click.connect(_on_bus_ray_click)
	if not InteractionBus.ray_click_release.is_connected(_on_bus_ray_click_release):
		InteractionBus.ray_click_release.connect(_on_bus_ray_click_release)


func _sync_collision_state() -> void:
	var can_hit := interaction_enabled and is_inside_tree() and is_visible_in_tree()
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
	if not interaction_enabled or not is_visible_in_tree():
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
