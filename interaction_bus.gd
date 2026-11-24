extends Node
# Global singleton signal bus for 3D projector-room interaction.
# Preserves all original template signals and extends them for clean single-touch spatial events.

# --- Original Template Signals (DO NOT REMOVE) ---
signal ray_enter(collider)
signal ray_exit(collider)
signal ray_click(collider)
signal ray_click_release(collider)

# Deprecated, use "is_hovering" bool in _process(delta) within interactable objects instead
signal ray_hover(collider, ray: Array)

# --- Extended Single-Touch Spatial Signals ---
signal touch_began(
	screen_pos: Vector2,
	viewport_index: int,
	collider: Object,
	hit_pos: Vector3,
	hit_normal: Vector3,
)
signal touch_moved(
	screen_pos: Vector2,
	viewport_index: int,
	collider: Object,
	hit_pos: Vector3,
	hit_normal: Vector3,
)
signal touch_ended(
	screen_pos: Vector2,
	viewport_index: int,
	collider: Object,
	hit_pos: Vector3,
	hit_normal: Vector3,
)
signal single_touch_tap(
	collider: Object,
	hit_pos: Vector3,
	hit_normal: Vector3,
	viewport_index: int,
)
signal touch_ripple(
	world_pos: Vector3,
	world_normal: Vector3,
	viewport_index: int,
	color: Color,
)
