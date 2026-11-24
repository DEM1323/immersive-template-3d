extends ImmersiveInteractable3D
class_name GlassButton3D

## Ephemeral luminous glass monolith button/card with crisp Label3D typography,
## shader-driven glow/dissolve effects, and tactile single-touch response.

const GLASS_SHADER_PATH := "res://shaders/glass_tile.gdshader"

@export var panel_size: Vector3 = Vector3(1.2, 0.55, 0.08)
@export var primary_text: String = "Button"
@export var secondary_text: String = ""
@export var primary_font_size: int = 56
@export var secondary_font_size: int = 30
@export var base_color: Color = Color(0.06, 0.13, 0.27, 0.88)
@export var rim_color: Color = Color(0.36, 0.88, 1.0, 1.0)
@export var accent_color: Color = Color(1.0, 0.82, 0.42, 1.0)
@export var text_color: Color = Color(0.96, 0.98, 1.0, 1.0)
@export var secondary_color: Color = Color(0.68, 0.90, 1.0, 0.95)
@export var enable_idle_float: bool = true
@export var float_amplitude: float = 0.012
@export var float_speed: float = 1.35
@export var autowrap_width_px: float = 0.0

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
var _highlight_target: float = 0.0
var _highlight_current: float = 0.0
var _dissolve_amount: float = 0.0
var _ghost_amount: float = 0.0
var _built: bool = false


func _ready() -> void:
	_ensure_built()
	super._ready()
	_float_phase = randf() * TAU
	set_process(true)


func _process(delta: float) -> void:
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

	var desired_highlight := _highlight_target + (0.35 if is_hovering else 0.0)
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
	_built = true

	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "GlassMesh"
	_visual_root.add_child(_mesh_instance)

	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "CollisionShape"
	add_child(_collision_shape)

	_primary_label = Label3D.new()
	_primary_label.name = "PrimaryLabel"
	_primary_label.pixel_size = 0.0032
	_primary_label.font = EphemeralTheme.get_ui_font()
	_primary_label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_primary_label.render_priority = 4
	_primary_label.outline_size = 10
	_primary_label.outline_modulate = Color(0.02, 0.04, 0.09, 0.90)
	_primary_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_primary_label.double_sided = false
	_primary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_primary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_visual_root.add_child(_primary_label)

	_secondary_label = Label3D.new()
	_secondary_label.name = "SecondaryLabel"
	_secondary_label.pixel_size = 0.0030
	_secondary_label.font = EphemeralTheme.get_ui_font()
	_secondary_label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_secondary_label.render_priority = 4
	_secondary_label.outline_size = 8
	_secondary_label.outline_modulate = Color(0.02, 0.04, 0.09, 0.90)
	_secondary_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_secondary_label.double_sided = false
	_secondary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_secondary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_visual_root.add_child(_secondary_label)

	_rebuild_geometry_and_material()
	_refresh_labels()


func configure(
	p_size: Vector3,
	p_primary: String,
	p_secondary: String = "",
	p_font_size: int = 56,
	p_base_color: Color = Color(0.06, 0.13, 0.27, 0.88),
	p_rim_color: Color = Color(0.36, 0.88, 1.0, 1.0),
	p_accent_color: Color = Color(1.0, 0.82, 0.42, 1.0),
) -> void:
	panel_size = p_size
	primary_text = p_primary
	secondary_text = p_secondary
	primary_font_size = p_font_size
	base_color = p_base_color
	rim_color = p_rim_color
	accent_color = p_accent_color
	_ensure_built()
	_rebuild_geometry_and_material()
	_refresh_labels()


func _rebuild_geometry_and_material() -> void:
	var box := BoxMesh.new()
	box.size = panel_size
	_mesh_instance.mesh = box

	var shape := BoxShape3D.new()
	shape.size = Vector3(panel_size.x, panel_size.y, maxf(panel_size.z, 0.12))
	_collision_shape.shape = shape

	if _shader_mat == null:
		if ResourceLoader.exists(GLASS_SHADER_PATH):
			var shader := load(GLASS_SHADER_PATH) as Shader
			if shader != null:
				_shader_mat = ShaderMaterial.new()
				_shader_mat.shader = shader
				_shader_mat.render_priority = 1
				_mesh_instance.material_override = _shader_mat
		if _shader_mat == null:
			var fallback := StandardMaterial3D.new()
			fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fallback.albedo_color = base_color
			_mesh_instance.material_override = fallback

	_apply_shader_colors()


func _apply_shader_colors() -> void:
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("base_color", base_color)
		_shader_mat.set_shader_parameter("rim_color", rim_color)
		_shader_mat.set_shader_parameter("accent_color", accent_color)
		_shader_mat.set_shader_parameter("panel_size_xy", Vector2(panel_size.x, panel_size.y))
		_shader_mat.set_shader_parameter("phase_offset", _float_phase)
		_shader_mat.set_shader_parameter("dissolve_amount", _dissolve_amount)
		_shader_mat.set_shader_parameter("ghost_amount", _ghost_amount)
	elif _mesh_instance != null and _mesh_instance.material_override is StandardMaterial3D:
		(_mesh_instance.material_override as StandardMaterial3D).albedo_color = base_color


func set_render_priorities(panel_priority: int, label_priority: int) -> void:
	_ensure_built()
	if _shader_mat != null:
		_shader_mat.render_priority = panel_priority
	if _primary_label != null:
		_primary_label.render_priority = label_priority
	if _secondary_label != null:
		_secondary_label.render_priority = label_priority


func _refresh_labels() -> void:
	if not _built:
		return
	var z_front: float = panel_size.z * 0.5 + 0.016
	var has_secondary := not secondary_text.strip_edges().is_empty()

	_primary_label.text = primary_text
	_primary_label.font_size = primary_font_size
	_primary_label.modulate = text_color
	var wrap_px := autowrap_width_px
	if wrap_px <= 0.0:
		wrap_px = (panel_size.x * 0.88) / _primary_label.pixel_size
	_primary_label.width = wrap_px
	_primary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if has_secondary:
		_primary_label.position = Vector3(0.0, panel_size.y * 0.14, z_front)
		_secondary_label.visible = true
		_secondary_label.text = secondary_text
		_secondary_label.font_size = secondary_font_size
		_secondary_label.modulate = secondary_color
		_secondary_label.width = (panel_size.x * 0.90) / _secondary_label.pixel_size
		_secondary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_secondary_label.position = Vector3(0.0, -panel_size.y * 0.24, z_front)
	else:
		_primary_label.position = Vector3(0.0, 0.0, z_front)
		_secondary_label.visible = false


func set_texts(p_primary: String, p_secondary: String = "") -> void:
	primary_text = p_primary
	secondary_text = p_secondary
	_ensure_built()
	_refresh_labels()


func set_palette(
	p_base: Color,
	p_rim: Color,
	p_accent: Color = accent_color,
	p_text: Color = text_color,
) -> void:
	base_color = p_base
	rim_color = p_rim
	accent_color = p_accent
	text_color = p_text
	_ensure_built()
	_apply_shader_colors()
	_primary_label.modulate = text_color


func set_highlighted(highlighted: bool, intensity: float = 0.9) -> void:
	_highlight_target = intensity if highlighted else 0.0


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
