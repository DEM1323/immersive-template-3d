@tool
extends GlassButton3D
class_name JeopardyTile3D

## Individual floating glass monolith on the 5x5 Jeopardy Board.
## Dissolves into rising luminous motes when answered and leaves an ethereal ghost echo.

signal tile_tapped(cat_idx: int, row_idx: int, tile: JeopardyTile3D)

const TILE_SIZE := Vector3(1.18, 0.36, 0.08)
const TILE_FONT_SIZE := 68
const TILE_TEXT_COLOR := Color(1.0, 0.92, 0.66, 1.0)
const TILE_GOLD := Color(1.0, 0.86, 0.46, 1.0)
const GHOST_TEXT := "•"

## Board column (0 = leftmost category). Play Mode opens pack clue [cat_idx][row_idx].
@export var cat_idx: int = 0
## Board row (0 = top).
@export var row_idx: int = 0
## Dollar value shown on the tile. The loaded question pack supplies the live value in Play Mode.
@export var clue_value: int = 200:
	set(value):
		clue_value = value
		# Skipped while the scene loads so a hand-edited primary_text survives reopening.
		if is_node_ready():
			primary_text = "$%d" % clue_value

var is_cleared: bool = false

var _dissolve_tween: Tween = null
var _burst_particles: CPUParticles3D = null


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	if not tapped.is_connected(_on_self_tapped):
		tapped.connect(_on_self_tapped)


## Styles a brand-new tile (default size, type scale, and idle-float rhythm) and loads its clue.
## Use apply_clue_data() to refresh a tile that was already placed in a scene.
func setup_tile(p_cat: int, p_row: int, p_value: int, p_accent: Color) -> void:
	if owner == null:
		panel_size = TILE_SIZE
		primary_font_size = TILE_FONT_SIZE
		enable_idle_float = true
		float_amplitude = 0.011
		float_speed = snappedf(1.2 + float(p_cat) * 0.11 + float(p_row) * 0.08, 0.01)
	_ensure_built()
	apply_clue_data(p_cat, p_row, p_value, p_accent)


## Updates value, palette, and cleared state while leaving the saved transform, panel_size,
## font size, and float settings exactly as authored in the Godot Editor.
func apply_clue_data(p_cat: int, p_row: int, p_value: int, p_accent: Color) -> void:
	if _dissolve_tween != null and _dissolve_tween.is_valid():
		_dissolve_tween.kill()
	_dissolve_tween = null

	cat_idx = p_cat
	row_idx = p_row
	clue_value = p_value
	is_cleared = false

	var depth_tint := lerpf(0.0, 0.06, float(p_row) / 4.0)
	set_palette(
		Color(0.055 + depth_tint * 0.4, 0.11 + depth_tint * 0.5, 0.25 + depth_tint, 0.88),
		p_accent.lerp(Color(0.45, 0.90, 1.0, 1.0), 0.45),
		TILE_GOLD,
		TILE_TEXT_COLOR,
	)
	_set_shimmer_phase(0.0)  # Board tiles shimmer in unison
	set_texts("$%d" % p_value, "")
	set_dissolve(0.0)
	set_ghost(0.0)
	set_interactable_active(true)
	if not Engine.is_editor_hint():
		_ensure_particles(p_accent)


func _ensure_particles(p_accent: Color) -> void:
	if _burst_particles != null:
		return
	_burst_particles = CPUParticles3D.new()
	_burst_particles.name = "DissolveBurst"
	_burst_particles.emitting = false
	_burst_particles.one_shot = true
	_burst_particles.explosiveness = 0.82
	_burst_particles.amount = 22
	_burst_particles.lifetime = 1.15
	_burst_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_burst_particles.emission_box_extents = Vector3(0.55, 0.16, 0.04)
	_burst_particles.direction = Vector3(0.0, 1.0, 0.35)
	_burst_particles.spread = 38.0
	_burst_particles.initial_velocity_min = 0.45
	_burst_particles.initial_velocity_max = 1.35
	_burst_particles.gravity = Vector3(0.0, 0.35, 0.0)
	_burst_particles.scale_amount_min = 0.25
	_burst_particles.scale_amount_max = 0.72
	_burst_particles.mesh = EphemeralTheme.make_particle_quad_mesh(
		true,
		Color(p_accent.r, p_accent.g, p_accent.b, 0.92),
		0.22,
	)
	add_child(_burst_particles)


func _on_self_tapped(_btn: ImmersiveInteractable3D, _hit_pos: Vector3, _vp: int) -> void:
	if is_cleared:
		return
	tile_tapped.emit(cat_idx, row_idx, self)


func play_dissolve_to_ghost(was_correct: bool) -> void:
	is_cleared = true
	set_interactable_active(false)
	if _burst_particles != null:
		var burst_col := Color(0.38, 0.98, 0.72, 0.92) if was_correct else Color(0.76, 0.52, 0.96, 0.85)
		if _burst_particles.mesh is PrimitiveMesh and _burst_particles.mesh.material is StandardMaterial3D:
			(_burst_particles.mesh.material as StandardMaterial3D).albedo_color = burst_col
		_burst_particles.restart()
		_burst_particles.emitting = true

	if _dissolve_tween != null and _dissolve_tween.is_valid():
		_dissolve_tween.kill()

	_dissolve_tween = create_tween()
	_dissolve_tween.tween_method(set_dissolve, 0.0, 0.85, 0.52).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_dissolve_tween.tween_callback(func() -> void:
		set_dissolve(0.0)
		set_ghost(1.0)
		set_texts(GHOST_TEXT, "")
	)


func set_cleared_immediate() -> void:
	is_cleared = true
	set_interactable_active(false)
	set_dissolve(0.0)
	set_ghost(1.0)
	set_texts(GHOST_TEXT, "")
