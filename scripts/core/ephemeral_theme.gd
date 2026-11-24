extends RefCounted
class_name EphemeralTheme

## Centralized cached typography (SIL OFL Cinzel + Outfit FontVariations)
## and luminous additive particle QuadMeshes for GL Compatibility.

const DISPLAY_FONT_PATH := "res://assets/fonts/display_font.ttf"
const UI_FONT_PATH := "res://assets/fonts/ui_font.ttf"
const GLOW_MOTE_PATH := "res://assets/textures/glow_mote.png"
const STAR_SPARK_PATH := "res://assets/textures/star_spark.png"

static var _display_font: Font = null
static var _ui_font: Font = null
static var _fonts_initialized: bool = false


static func get_display_font() -> Font:
	_ensure_fonts()
	return _display_font


static func get_ui_font() -> Font:
	_ensure_fonts()
	return _ui_font


static func _ensure_fonts() -> void:
	if _fonts_initialized:
		return
	_fonts_initialized = true

	var ts := TextServerManager.get_primary_interface()
	var wght_tag: Variant = ts.name_to_tag("wght") if ts != null else "wght"

	if ResourceLoader.exists(DISPLAY_FONT_PATH):
		var base_disp := load(DISPLAY_FONT_PATH) as Font
		if base_disp != null:
			var disp_var := FontVariation.new()
			disp_var.base_font = base_disp
			disp_var.variation_opentype = {wght_tag: 750}
			disp_var.variation_embolden = 0.08
			_display_font = disp_var

	if ResourceLoader.exists(UI_FONT_PATH):
		var base_ui := load(UI_FONT_PATH) as Font
		if base_ui != null:
			var ui_var := FontVariation.new()
			ui_var.base_font = base_ui
			ui_var.variation_opentype = {wght_tag: 700}
			ui_var.variation_embolden = 0.10
			_ui_font = ui_var


static func format_money(amount: int) -> String:
	return "-$%d" % abs(amount) if amount < 0 else "$%d" % amount


static func make_particle_quad_mesh(
	use_star_spark: bool,
	tint: Color,
	quad_size: float = 0.24,
	p_render_priority: int = -3,
) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.no_depth_test = false
	mat.render_priority = p_render_priority
	mat.albedo_color = tint

	var tex_path := STAR_SPARK_PATH if use_star_spark else GLOW_MOTE_PATH
	if ResourceLoader.exists(tex_path):
		var tex := load(tex_path) as Texture2D
		if tex != null:
			mat.albedo_texture = tex

	quad.material = mat
	return quad
