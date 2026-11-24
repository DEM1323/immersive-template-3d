extends Node3D
class_name SanctuaryEnvironment

## Animates the 360-degree Ephemeral Sanctuary architecture saved in SanctuaryEnvironment.tscn:
## - Custom celestial aurora sky (GL Compatibility safe)
## - 4 luminous crystalline corner monolith pillars bridging the 4 projector walls seamlessly
## - Floating overhead & corner aurora light ribbons
## - Rising ambient firefly/light-mote particles & room-wide celebratory burst particles
## - Smooth state-reactive color transitions (Board / Clue / Daily Double / Correct / Finale)

const SKY_SHADER_PATH := "res://shaders/ephemeral_sky.gdshader"
const RIBBON_SHADER_PATH := "res://shaders/aurora_ribbon.gdshader"

var game_state: JeopardyGameState

var _world_env: WorldEnvironment
var _sky_mat: ShaderMaterial
var _ribbon_mats: Array[ShaderMaterial] = []
var _accent_mats: Array[StandardMaterial3D] = []
var _ambient_particles: CPUParticles3D
var _celebration_particles: CPUParticles3D
var _corner_light: OmniLight3D

var _target_accent: Color = Color(0.22, 0.82, 0.96)
var _current_accent: Color = Color(0.22, 0.82, 0.96)
var _target_aurora_intensity: float = 0.90
var _current_aurora_intensity: float = 0.90


func initialize(p_state: JeopardyGameState) -> void:
	game_state = p_state
	if not _bind_nodes():
		build_default_nodes(null)
		_bind_nodes()
	_connect_signals()
	set_process(true)


func _process(delta: float) -> void:
	var blend := clampf(delta * 2.4, 0.0, 1.0)
	_current_accent = _current_accent.lerp(_target_accent, blend)
	_current_aurora_intensity = lerpf(_current_aurora_intensity, _target_aurora_intensity, blend)

	if _sky_mat != null:
		_sky_mat.set_shader_parameter("state_accent", Vector3(_current_accent.r, _current_accent.g, _current_accent.b))
		_sky_mat.set_shader_parameter("aurora_intensity", _current_aurora_intensity)

	for mat in _ribbon_mats:
		mat.set_shader_parameter("color_a", Vector3(_current_accent.r, _current_accent.g, _current_accent.b))

	for pmat in _accent_mats:
		pmat.emission = _current_accent

	if _corner_light != null:
		_corner_light.light_color = _current_accent


func _connect_signals() -> void:
	game_state.phase_changed.connect(_on_phase_changed)
	game_state.clue_resolved.connect(_on_clue_resolved)
	game_state.daily_double_triggered.connect(_on_daily_double)
	game_state.pack_changed.connect(_on_pack_changed)
	game_state.game_finished.connect(func(_s) -> void: trigger_celebration(Color(1.0, 0.84, 0.40)))


## Creates every missing sanctuary node. Existing nodes are never touched, so manual edits survive.
## Pass the scene root as owner_root to make the nodes saveable; pass null for a code-only instance.
func build_default_nodes(owner_root: Node) -> void:
	_build_sky_and_lighting(owner_root)
	_build_corner_pillars_and_arches(owner_root)
	_build_aurora_ribbons(owner_root)
	_build_particles(owner_root)


func _bind_nodes() -> bool:
	_world_env = get_node_or_null("SanctuaryWorldEnvironment") as WorldEnvironment
	_corner_light = get_node_or_null("SanctuaryCoreLight") as OmniLight3D
	_ambient_particles = get_node_or_null("AmbientLightMotes") as CPUParticles3D
	_celebration_particles = get_node_or_null("CelebrationBurst") as CPUParticles3D

	_sky_mat = null
	if _world_env != null and _world_env.environment != null and _world_env.environment.sky != null:
		_sky_mat = _world_env.environment.sky.sky_material as ShaderMaterial

	_ribbon_mats.clear()
	_accent_mats.clear()
	for i in range(4):
		var ribbon := get_node_or_null("AuroraRibbon_%d" % i) as MeshInstance3D
		if ribbon != null and ribbon.get_active_material(0) is ShaderMaterial:
			_ribbon_mats.append(ribbon.get_active_material(0) as ShaderMaterial)
		_bind_accent_material(get_node_or_null("CornerPillar_%d/LightVein" % i) as MeshInstance3D)
		_bind_accent_material(get_node_or_null("CorniceBeam_%d" % i) as MeshInstance3D)

	return _world_env != null and _corner_light != null and _celebration_particles != null


func _bind_accent_material(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance == null:
		return
	var mat := mesh_instance.get_active_material(0) as StandardMaterial3D
	if mat != null and not _accent_mats.has(mat):
		_accent_mats.append(mat)


func _adopt(parent: Node, owner_root: Node, node: Node, node_name: String) -> void:
	node.name = node_name
	parent.add_child(node)
	if owner_root != null:
		node.owner = owner_root


func _build_sky_and_lighting(owner_root: Node) -> void:
	if not has_node("SanctuaryWorldEnvironment"):
		var world_env := WorldEnvironment.new()
		world_env.environment = _make_environment()
		_adopt(self, owner_root, world_env, "SanctuaryWorldEnvironment")

	if not has_node("CelestialKeyLight"):
		var dir_light := DirectionalLight3D.new()
		dir_light.rotation_degrees = Vector3(-42.0, 28.0, 0.0)
		dir_light.light_color = Color(0.75, 0.88, 1.0)
		dir_light.light_energy = 0.65
		dir_light.shadow_enabled = false
		_adopt(self, owner_root, dir_light, "CelestialKeyLight")

	if not has_node("SanctuaryCoreLight"):
		var core_light := OmniLight3D.new()
		core_light.position = Vector3(0.0, 3.2, 0.0)
		core_light.light_color = _current_accent
		core_light.light_energy = 1.6
		core_light.omni_range = 14.0
		core_light.shadow_enabled = false
		_adopt(self, owner_root, core_light, "SanctuaryCoreLight")


func _make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.30, 0.48)
	env.ambient_light_energy = 0.65
	env.glow_enabled = true
	env.glow_intensity = 0.42
	env.glow_strength = 0.72
	env.glow_bloom = 0.10
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.09, 0.20)
	env.fog_density = 0.018

	var sky := Sky.new()
	if ResourceLoader.exists(SKY_SHADER_PATH):
		var sky_shader := load(SKY_SHADER_PATH) as Shader
		if sky_shader != null:
			var sky_mat := ShaderMaterial.new()
			sky_mat.shader = sky_shader
			sky.sky_material = sky_mat
	if sky.sky_material == null:
		var proc := ProceduralSkyMaterial.new()
		proc.sky_top_color = Color(0.02, 0.03, 0.09)
		proc.sky_horizon_color = Color(0.08, 0.16, 0.30)
		proc.ground_bottom_color = Color(0.02, 0.03, 0.08)
		proc.ground_horizon_color = Color(0.06, 0.11, 0.22)
		sky.sky_material = proc

	env.sky = sky
	return env


func _build_corner_pillars_and_arches(owner_root: Node) -> void:
	# 4 slender crystalline columns placed cleanly at the 4 diagonal corners (outside interactive wall bounds!)
	var corners: Array[Vector3] = [
		Vector3(-4.25, 1.85, -4.25),
		Vector3(4.25, 1.85, -4.25),
		Vector3(4.25, 1.85, 4.25),
		Vector3(-4.25, 1.85, 4.25),
	]

	for i in range(corners.size()):
		var pillar_root := get_node_or_null("CornerPillar_%d" % i) as Node3D
		if pillar_root == null:
			pillar_root = Node3D.new()
			pillar_root.position = corners[i]
			pillar_root.rotation.y = PI * 0.25 + float(i) * PI * 0.5
			_adopt(self, owner_root, pillar_root, "CornerPillar_%d" % i)

		if not pillar_root.has_node("PillarBody"):
			var body_mesh := BoxMesh.new()
			body_mesh.size = Vector3(0.24, 5.2, 0.24)
			var body_mat := StandardMaterial3D.new()
			body_mat.albedo_color = Color(0.06, 0.11, 0.22, 0.92)
			body_mat.metallic = 0.35
			body_mat.roughness = 0.22
			body_mat.emission_enabled = true
			body_mat.emission = Color(0.10, 0.30, 0.45)
			body_mat.emission_energy_multiplier = 0.65
			body_mesh.material = body_mat
			var body_inst := MeshInstance3D.new()
			body_inst.mesh = body_mesh
			_adopt(pillar_root, owner_root, body_inst, "PillarBody")

		# Slender luminous light-vein running vertically inside each corner pillar
		var vein := pillar_root.get_node_or_null("LightVein") as MeshInstance3D
		if vein == null:
			var vein_mesh := BoxMesh.new()
			vein_mesh.size = Vector3(0.05, 5.1, 0.27)
			vein_mesh.material = _make_accent_material()
			vein = MeshInstance3D.new()
			vein.mesh = vein_mesh
			_adopt(pillar_root, owner_root, vein, "LightVein")

		# Floating overhead crystalline cornice bar connecting pillars at y = 3.65m
		if not has_node("CorniceBeam_%d" % i):
			var beam_mesh := BoxMesh.new()
			beam_mesh.size = Vector3(8.5, 0.06, 0.08)
			var beam := MeshInstance3D.new()
			beam.mesh = beam_mesh
			beam.material_override = vein.get_active_material(0)
			var next_corner: Vector3 = corners[(i + 1) % corners.size()]
			var mid: Vector3 = (corners[i] + next_corner) * 0.5
			beam.position = Vector3(mid.x, 3.65, mid.z)
			if absf(corners[i].x - next_corner.x) < 0.1:
				beam.rotation.y = PI * 0.5
			_adopt(self, owner_root, beam, "CorniceBeam_%d" % i)


func _make_accent_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _current_accent
	mat.emission_enabled = true
	mat.emission = _current_accent
	mat.emission_energy_multiplier = 1.8
	return mat


func _build_aurora_ribbons(owner_root: Node) -> void:
	if not ResourceLoader.exists(RIBBON_SHADER_PATH):
		return
	var ribbon_shader := load(RIBBON_SHADER_PATH) as Shader
	if ribbon_shader == null:
		return

	# 4 sweeping translucent aurora curtains floating behind each wall stage (at distance 5.6m)
	var configs := [
		{"pos": Vector3(0.0, 2.75, -5.6), "rot_y": 0.0},
		{"pos": Vector3(-5.6, 2.75, 0.0), "rot_y": PI * 0.5},
		{"pos": Vector3(5.6, 2.75, 0.0), "rot_y": -PI * 0.5},
		{"pos": Vector3(0.0, 2.75, 5.6), "rot_y": PI},
	]
	for i in range(configs.size()):
		if has_node("AuroraRibbon_%d" % i):
			continue
		var cfg: Dictionary = configs[i]
		var plane := PlaneMesh.new()
		plane.size = Vector2(9.2, 3.2)
		plane.subdivide_width = 18
		plane.subdivide_depth = 6

		var mat := ShaderMaterial.new()
		mat.shader = ribbon_shader
		mat.render_priority = -6
		# Color (not Vector3): source_color uniforms only serialize into a .tscn as Color.
		mat.set_shader_parameter("color_a", Color(0.18, 0.84, 0.95))
		mat.set_shader_parameter("color_b", Color(0.66, 0.34, 0.98))
		mat.set_shader_parameter("speed", 0.36 + float(i) * 0.05)
		mat.set_shader_parameter("opacity", 0.32)

		var inst := MeshInstance3D.new()
		inst.mesh = plane
		inst.material_override = mat
		inst.position = cfg["pos"]
		inst.rotation = Vector3(PI * 0.5, float(cfg["rot_y"]), 0.0)
		_adopt(self, owner_root, inst, "AuroraRibbon_%d" % i)


func _build_particles(owner_root: Node) -> void:
	# Gentle ascending ambient light motes across the whole 360 sanctuary
	if not has_node("AmbientLightMotes"):
		var motes := CPUParticles3D.new()
		motes.position = Vector3(0.0, 0.4, 0.0)
		motes.amount = 90
		motes.lifetime = 8.5
		motes.preprocess = 4.0
		motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		motes.emission_box_extents = Vector3(4.8, 0.6, 4.8)
		motes.direction = Vector3(0.0, 1.0, 0.0)
		motes.spread = 22.0
		motes.gravity = Vector3(0.0, 0.04, 0.0)
		motes.initial_velocity_min = 0.20
		motes.initial_velocity_max = 0.55
		motes.scale_amount_min = 0.25
		motes.scale_amount_max = 0.70
		motes.mesh = EphemeralTheme.make_particle_quad_mesh(
			false,
			Color(0.68, 0.94, 1.0, 0.65),
			0.22,
		)
		_adopt(self, owner_root, motes, "AmbientLightMotes")

	# Room-wide celebratory burst particles
	if not has_node("CelebrationBurst"):
		var burst := CPUParticles3D.new()
		burst.position = Vector3(0.0, 0.6, 0.0)
		burst.emitting = false
		burst.one_shot = true
		burst.explosiveness = 0.72
		burst.amount = 110
		burst.lifetime = 2.6
		burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		burst.emission_ring_radius = 3.2
		burst.emission_ring_inner_radius = 1.4
		burst.emission_ring_height = 0.4
		burst.direction = Vector3(0.0, 1.0, 0.0)
		burst.spread = 32.0
		burst.initial_velocity_min = 1.2
		burst.initial_velocity_max = 2.8
		burst.gravity = Vector3(0.0, -0.35, 0.0)
		burst.scale_amount_min = 0.35
		burst.scale_amount_max = 0.95
		burst.mesh = EphemeralTheme.make_particle_quad_mesh(
			true,
			Color(1.0, 0.86, 0.42, 0.92),
			0.28,
		)
		_adopt(self, owner_root, burst, "CelebrationBurst")


func trigger_celebration(color: Color) -> void:
	if _celebration_particles == null:
		return
	if _celebration_particles.mesh is PrimitiveMesh and _celebration_particles.mesh.material is StandardMaterial3D:
		(_celebration_particles.mesh.material as StandardMaterial3D).albedo_color = color
	_celebration_particles.restart()
	_celebration_particles.emitting = true


func _on_pack_changed(pack: JeopardyPack) -> void:
	if pack != null:
		_target_accent = pack.accent_color


func _on_phase_changed(new_phase: int, _old_phase: int) -> void:
	var progress := game_state.get_ephemeral_progress()
	match new_phase:
		JeopardyGameState.Phase.SETUP:
			var setup_accent := Color(0.24, 0.84, 0.96)
			if game_state.current_pack != null:
				setup_accent = game_state.current_pack.accent_color
			_target_accent = setup_accent
			_target_aurora_intensity = 0.95
		JeopardyGameState.Phase.BOARD:
			var base_accent := Color(0.24, 0.84, 0.96)
			if game_state.current_pack != null:
				base_accent = game_state.current_pack.accent_color
			# Subtle shift toward warm twilight gold as more tiles dissolve
			_target_accent = base_accent.lerp(Color(1.0, 0.78, 0.38), progress * 0.45)
			_target_aurora_intensity = 0.85 + progress * 0.45
		JeopardyGameState.Phase.DAILY_DOUBLE_WAGER:
			_target_accent = Color(0.95, 0.42, 0.98)
			_target_aurora_intensity = 1.75
		JeopardyGameState.Phase.CLUE_ACTIVE:
			_target_accent = Color(0.22, 0.88, 0.92)
			_target_aurora_intensity = 1.05
		JeopardyGameState.Phase.FINAL_WAGER, JeopardyGameState.Phase.FINAL_CLUE:
			_target_accent = Color(1.0, 0.76, 0.32)
			_target_aurora_intensity = 1.55
		JeopardyGameState.Phase.GAME_OVER:
			_target_accent = Color(1.0, 0.84, 0.42)
			_target_aurora_intensity = 1.85


func _on_daily_double(_cat: int, _row: int, _team: int, _max_w: int) -> void:
	trigger_celebration(Color(0.95, 0.46, 1.0, 0.95))


func _on_clue_resolved(res: Dictionary) -> void:
	if bool(res.get("was_correct", false)):
		_target_accent = Color(0.32, 0.96, 0.72)
		_target_aurora_intensity = 1.55
		trigger_celebration(Color(0.38, 0.98, 0.74, 0.95))
	else:
		_target_accent = Color(0.92, 0.38, 0.56)
		_target_aurora_intensity = 0.75
