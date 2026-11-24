@tool
extends ImmersiveInteractable3D
class_name GlassButton3D

## Ephemeral luminous glass monolith button/card with crisp Label3D typography,
## shader-driven glow/dissolve effects, and tactile single-touch response.
##
## Every visual @export is live in the Godot Editor viewport. The generated internals
## (VisualRoot, GlassMesh, PrimaryLabel, SecondaryLabel, CollisionShape) never get an `owner`,
## so they are rebuilt on load and never serialized into (or duplicated inside) a scene.

const GLASS_SHADER_PATH := "res://shaders/glass_tile.gdshader"
const LABEL_OUTLINE_COLOR := Color(0.02, 0.04, 0.09, 0.90)
const MIN_EXTENT := 0.01

@export var panel_size: Vector3 = Vector3(1.2, 0.55, 0.08):
	set(value):
		panel_size = value
		_refresh_geometry()
		_refresh_labels()
@export_multiline var primary_text: String = "Button":
	set(value):
		primary_text = value
		_refresh_labels()
@export_multiline var secondary_text: String = "":
	set(value):
		secondary_text = value
		_refresh_labels()
@export var primary_font_size: int = 56:
	set(value):
		primary_font_size = value
		_refresh_labels()
@export var secondary_font_size: int = 30:
	set(value):
		secondary_font_size = value
		_refresh_labels()
@export var base_color: Color = Color(0.06, 0.13, 0.27, 0.88):
	set(value):
		base_color = value
		_apply_shader_colors()
@export var rim_color: Color = Color(0.36, 0.88, 1.0, 1.0):
	set(value):
		rim_color = value
		_apply_shader_colors()
@export var accent_color: Color = Color(1.0, 0.82, 0.42, 1.0):
	set(value):
		accent_color = value
		_apply_shader_colors()
@export var text_color: Color = Color(0.96, 0.98, 1.0, 1.0):
	set(value):
		text_color = value
		_refresh_labels()
@export var secondary_color: Color = Color(0.68, 0.90, 1.0, 0.95):
	set(value):
		secondary_color = value
		_refresh_labels()
## Resting glow. Gameplay may override it through set_highlighted().
@export_range(0.0, 1.5, 0.01) var highlight_amount: float = 0.0:
	set(value):
		highlight_amount = value
		_apply_editor_highlight()
@export var enable_idle_float: bool = true
@export var float_amplitude: float = 0.012
@export var float_speed: float = 1.35
## Primary text wrap width in font pixels; 0 derives it from panel_size.
@export var autowrap_width_px: float = 0.0:
	set(value):
		autowrap_width_px = value
		_refresh_labels()
@export var panel_render_priority: int = 1:
	set(value):
		panel_render_priority = value
		_apply_render_priorities()
@export var label_render_priority: int = 4:
	set(value):
		label_render_priority = value
		_apply_render_priorities()

var metadata: Dictionary = {}

var _visual_root: Node3D
var _mesh_instance: MeshInstance3D
var _collision_shape: CollisionShape3D
var _primary_label: Label3D
var _secondary_label: Label3D
var _shader_mat: ShaderMaterial
var _float_phase: float = 0.0
var _press_kick: float = 0.0
var _press_glow: float = 0.0
var _highlight_current: float = 0.0
var _dissolve_amount: float = 0.0
var _ghost_amount: float = 0.0
var _built: bool = false
var _batching: bool = false


func _ready() -> void:
	_ensure_built()
	super._ready()
	if Engine.is_editor_hint():
		# Viewport clicks on the generated mesh/labels select this button instead of an internal child.
		if not has_meta(&"_edit_group_"):
			set_meta(&"_edit_group_", true)
		set_process(false)
		return
	_float_phase = randf() * TAU
	set_process(true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _built or not is_visible_in_tree():
		return

	if _press_kick > 0.001:
		_press_kick = lerpf(_press_kick, 0.0, clampf(delta * 12.0, 0.0, 1.0))
	else:
		_press_kick = 0.0

	if _press_glow > 0.001:
		_press_glow = lerpf(_press_glow, 0.0, clampf(delta * 6.0, 0.0, 1.0))
	else:
		_press_glow = 0.0

	var desired_highlight := highlight_amount + (0.35 if is_hovering else 0.0)
	_highlight_current = lerpf(_highlight_current, desired_highlight, clampf(delta * 10.0, 0.0, 1.0))

	if _shader_mat != null:
		_shader_mat.set_shader_parameter("press_glow", _press_glow)
		_shader_mat.set_shader_parameter("highlight_amount", _highlight_current)

	var y_offset := 0.0
	if enable_idle_float and _ghost_amount < 0.5:
		var t := float(Time.get_ticks_msec()) * 0.001
		y_offset = sin(t * float_speed + _float_phase) * float_amplitude

	_visual_root.position = Vector3(0.0, y_offset, -_press_kick * 0.08)


func _ensure_built() -> void:
	if _built:
		return

	_visual_root = get_node_or_null(^"VisualRoot") as Node3D
	if _visual_root == null:
		_visual_root = Node3D.new()
		_visual_root.name = "VisualRoot"
		add_child(_visual_root)

	_mesh_instance = _visual_root.get_node_or_null(^"GlassMesh") as MeshInstance3D
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "GlassMesh"
		_visual_root.add_child(_mesh_instance)

	_collision_shape = get_node_or_null(^"CollisionShape") as CollisionShape3D
	if _collision_shape == null:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "CollisionShape"
		add_child(_collision_shape)

	_primary_label = _ensure_label("PrimaryLabel", 0.0032, 10)
	_secondary_label = _ensure_label("SecondaryLabel", 0.0030, 8)

	# Always fresh resources: a duplicated button must never share its source's mesh/shape/material.
	_mesh_instance.mesh = BoxMesh.new()
	_collision_shape.shape = BoxShape3D.new()
	_mesh_instance.material_override = _make_glass_material()

	_built = true
	_refresh_geometry()
	_apply_shader_colors()
	_apply_render_priorities()
	_apply_editor_highlight()
	_refresh_labels()


func _ensure_label(label_name: String, px_size: float, outline_px: int) -> Label3D:
	var label := _visual_root.get_node_or_null(NodePath(label_name)) as Label3D
	if label == null:
		label = Label3D.new()
		label.name = label_name
		_visual_root.add_child(label)
	label.pixel_size = px_size
	label.font = EphemeralTheme.get_ui_font()
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	label.outline_size = outline_px
	label.outline_modulate = LABEL_OUTLINE_COLOR
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _make_glass_material() -> Material:
	_shader_mat = null
	if ResourceLoader.exists(GLASS_SHADER_PATH):
		var shader := load(GLASS_SHADER_PATH) as Shader
		if shader != null:
			_shader_mat = ShaderMaterial.new()
			_shader_mat.shader = shader
			return _shader_mat
	var fallback := StandardMaterial3D.new()
	fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fallback.albedo_color = base_color
	return fallback


func configure(
	p_size: Vector3,
	p_primary: String,
	p_secondary: String = "",
	p_font_size: int = 56,
	p_base_color: Color = Color(0.06, 0.13, 0.27, 0.88),
	p_rim_color: Color = Color(0.36, 0.88, 1.0, 1.0),
	p_accent_color: Color = Color(1.0, 0.82, 0.42, 1.0),
) -> void:
	_batching = true
	panel_size = p_size
	primary_text = p_primary
	secondary_text = p_secondary
	primary_font_size = p_font_size
	base_color = p_base_color
	rim_color = p_rim_color
	accent_color = p_accent_color
	_batching = false
	_ensure_built()
	_refresh_geometry()
	_apply_shader_colors()
	_refresh_labels()


func _can_refresh() -> bool:
	return _built and not _batching


func _refresh_geometry() -> void:
	if not _can_refresh():
		return
	var size := panel_size.max(Vector3.ONE * MIN_EXTENT)
	(_mesh_instance.mesh as BoxMesh).size = size
	(_collision_shape.shape as BoxShape3D).size = Vector3(size.x, size.y, maxf(size.z, 0.12))
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("panel_size_xy", Vector2(size.x, size.y))


func _apply_shader_colors() -> void:
	if not _can_refresh():
		return
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("base_color", base_color)
		_shader_mat.set_shader_parameter("rim_color", rim_color)
		_shader_mat.set_shader_parameter("accent_color", accent_color)
		_shader_mat.set_shader_parameter("dissolve_amount", _dissolve_amount)
		_shader_mat.set_shader_parameter("ghost_amount", _ghost_amount)
	elif _mesh_instance.material_override is StandardMaterial3D:
		(_mesh_instance.material_override as StandardMaterial3D).albedo_color = base_color


func _apply_editor_highlight() -> void:
	# In Play Mode _process() eases toward highlight_amount instead.
	if Engine.is_editor_hint() and _can_refresh() and _shader_mat != null:
		_shader_mat.set_shader_parameter("highlight_amount", highlight_amount)


func _apply_render_priorities() -> void:
	if not _can_refresh():
		return
	if _shader_mat != null:
		_shader_mat.render_priority = panel_render_priority
	_primary_label.render_priority = label_render_priority
	_secondary_label.render_priority = label_render_priority


func set_render_priorities(panel_priority: int, label_priority: int) -> void:
	panel_render_priority = panel_priority
	label_render_priority = label_priority


func _refresh_labels() -> void:
	if not _can_refresh():
		return
	var z_front: float = panel_size.z * 0.5 + 0.016
	var has_secondary := not secondary_text.strip_edges().is_empty()

	_primary_label.text = primary_text
	_primary_label.font_size = maxi(primary_font_size, 1)
	_primary_label.modulate = text_color
	var wrap_px := autowrap_width_px
	if wrap_px <= 0.0:
		wrap_px = (maxf(panel_size.x, MIN_EXTENT) * 0.88) / _primary_label.pixel_size
	_primary_label.width = wrap_px
	_primary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if has_secondary:
		_primary_label.position = Vector3(0.0, panel_size.y * 0.14, z_front)
		_secondary_label.visible = true
		_secondary_label.text = secondary_text
		_secondary_label.font_size = maxi(secondary_font_size, 1)
		_secondary_label.modulate = secondary_color
		_secondary_label.width = (maxf(panel_size.x, MIN_EXTENT) * 0.90) / _secondary_label.pixel_size
		_secondary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_secondary_label.position = Vector3(0.0, -panel_size.y * 0.24, z_front)
	else:
		_primary_label.position = Vector3(0.0, 0.0, z_front)
		_secondary_label.visible = false


func set_texts(p_primary: String, p_secondary: String = "") -> void:
	_batching = true
	primary_text = p_primary
	secondary_text = p_secondary
	_batching = false
	_ensure_built()
	_refresh_labels()


func set_palette(
	p_base: Color,
	p_rim: Color,
	p_accent: Color = accent_color,
	p_text: Color = text_color,
) -> void:
	_batching = true
	base_color = p_base
	rim_color = p_rim
	accent_color = p_accent
	text_color = p_text
	_batching = false
	_ensure_built()
	_apply_shader_colors()
	_set_shimmer_phase(_float_phase)
	_primary_label.modulate = text_color


func _set_shimmer_phase(phase: float) -> void:
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("phase_offset", phase)


func set_highlighted(highlighted: bool, intensity: float = 0.9) -> void:
	highlight_amount = intensity if highlighted else 0.0


func set_dissolve(amount: float) -> void:
	_dissolve_amount = clampf(amount, 0.0, 1.0)
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("dissolve_amount", _dissolve_amount)
	if _primary_label != null:
		var lbl_alpha := clampf(1.0 - _dissolve_amount * 1.4, 0.0, 1.0)
		_primary_label.modulate.a = lbl_alpha
		_secondary_label.modulate.a = lbl_alpha


func set_ghost(amount: float) -> void:
	_ghost_amount = clampf(amount, 0.0, 1.0)
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("ghost_amount", _ghost_amount)
	if _primary_label != null:
		var lbl_alpha := lerpf(1.0, 0.20, _ghost_amount)
		_primary_label.modulate.a = lbl_alpha
		_secondary_label.modulate.a = lbl_alpha


func flash_press(strength: float = 1.15) -> void:
	_press_kick = 1.0
	_press_glow = strength


func _on_tapped_visual() -> void:
	flash_press(1.2)
