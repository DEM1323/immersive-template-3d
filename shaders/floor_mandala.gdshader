shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform vec4 base_color : source_color = vec4(0.025, 0.045, 0.10, 0.94);
uniform vec4 ring_color : source_color = vec4(0.30, 0.82, 0.96, 1.0);
uniform vec4 accent_color : source_color = vec4(0.95, 0.78, 0.38, 1.0);
uniform float pulse_speed : hint_range(0.1, 8.0) = 0.9;
uniform float energy_level : hint_range(0.0, 2.0) = 0.85;
uniform float timer_ratio : hint_range(0.0, 1.0) = 1.0;
uniform float show_timer_arc : hint_range(0.0, 1.0) = 0.0;
uniform vec2 ripple_uv = vec2(0.5, 0.5);
uniform float ripple_age = 10.0;
uniform vec3 ripple_color : source_color = vec3(1.0, 0.86, 0.50);

const float FULL_TURN = 6.28318530718;

float ring_line(float r, float radius, float half_width) {
	return 1.0 - smoothstep(half_width * 0.35, half_width, abs(r - radius));
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p);

	// Smooth circular outer edge fade so the sanctuary dais melts into surrounding mist
	float outer_fade = 1.0 - smoothstep(0.43, 0.50, r);
	if (outer_fade < 0.005) {
		discard;
	}

	// Clockwise angle starting at v=0 (Center Wall, -Z -> p = (0, -r)) going toward u=1 (Right Wall, +X)
	// Guard against atan(0, 0) which is undefined in WebGL2 / GLSL ES 3.00
	float cw_angle = (r > 0.0001) ? mod(atan(p.x, -p.y) + FULL_TURN, FULL_TURN) : 0.0;
	float cw_norm = cw_angle / FULL_TURN;

	float t = TIME * pulse_speed;
	float breathe = 0.82 + 0.18 * sin(t * 1.45);
	float energy = max(energy_level, 0.0);

	// Deep celestial sanctuary floor base with soft radial luminosity near center
	vec3 col = base_color.rgb * mix(1.38, 0.72, smoothstep(0.0, 0.46, r));

	// Gentle concentric energy pulse sweeping outward across the astrolabe
	float wave_field = pow(max(sin(r * 24.0 - t * 1.55), 0.0), 5.0);
	float wave_mask = smoothstep(0.04, 0.12, r) * (1.0 - smoothstep(0.36, 0.44, r));
	col += ring_color.rgb * wave_field * wave_mask * 0.12 * energy;

	// Breathing energy core at center (0, 0) - rich translucent medallion so floor text stays crystal-clear
	float core_halo = exp(-r * r * 125.0) * breathe * 0.42;
	float core_center = exp(-r * r * 620.0) * (0.45 + 0.08 * sin(t * 2.4));
	float core_medallion = 1.0 - smoothstep(0.052, 0.072, r);
	float core_ring = ring_line(r, 0.072, 0.0038);
	float core_inner_ring = ring_line(r, 0.048, 0.0024);

	// Primary concentric astrolabe rings
	float r_inner = ring_line(r, 0.165, 0.0034);
	float r_mid_a = ring_line(r, 0.278, 0.0040);
	float r_mid_b = ring_line(r, 0.290, 0.0020);
	float r_outer_a = ring_line(r, 0.402, 0.0042);
	float r_outer_b = ring_line(r, 0.428, 0.0028);

	// Delicate sacred-geometry 4-petal harmonic resonance around the inner sanctuary ring
	float petal_a = ring_line(r, 0.165 + 0.017 * cos(4.0 * cw_angle + t * 0.22), 0.0024);
	float petal_b = ring_line(r, 0.165 + 0.017 * cos(4.0 * cw_angle - t * 0.18 + 0.785398), 0.0020);

	// Counter-rotating segmented celestial arcs
	float rot_cw = cw_angle - t * 0.18;
	float seg_cw = smoothstep(0.18, 0.36, cos(4.0 * rot_cw));
	float arc_inner_rot = ring_line(r, 0.222, 0.0044) * seg_cw;

	float rot_ccw = cw_angle + t * 0.14;
	float seg_ccw = smoothstep(0.28, 0.48, cos(6.0 * rot_ccw));
	float arc_outer_rot = ring_line(r, 0.352, 0.0038) * seg_ccw;

	// Delicate radial compass ticks (72 fine ticks + 12 medium accent ticks + 24 inner ticks)
	float tick72_dist = abs(fract(cw_norm * 72.0 + 0.5) - 0.5) / 72.0 * (FULL_TURN * max(r, 0.01));
	float tick72_band = smoothstep(0.382, 0.386, r) * (1.0 - smoothstep(0.398, 0.402, r));
	float ticks_fine = (1.0 - smoothstep(0.0008, 0.0022, tick72_dist)) * tick72_band;

	float tick12_dist = abs(fract(cw_norm * 12.0 + 0.5) - 0.5) / 12.0 * (FULL_TURN * max(r, 0.01));
	float tick12_band = smoothstep(0.366, 0.370, r) * (1.0 - smoothstep(0.404, 0.410, r));
	float ticks_major = (1.0 - smoothstep(0.0014, 0.0034, tick12_dist)) * tick12_band;

	float tick24_dist = abs(fract(cw_norm * 24.0 + 0.5) - 0.5) / 24.0 * (FULL_TURN * max(r, 0.01));
	float tick24_band = smoothstep(0.148, 0.151, r) * (1.0 - smoothstep(0.161, 0.164, r));
	float ticks_inner = (1.0 - smoothstep(0.0008, 0.0020, tick24_dist)) * tick24_band;

	// 4 prominent cardinal axis rays pointing toward Center (-Z), Right (+X), Back (+Z), Left (-X)
	float d_card = min(abs(p.x), abs(p.y));
	float card_span = smoothstep(0.070, 0.095, r) * (1.0 - smoothstep(0.418, 0.436, r));
	float card_core = (1.0 - smoothstep(0.0012, 0.0038, d_card)) * card_span;
	float card_glow = (1.0 - smoothstep(0.003, 0.016, d_card)) * card_span;

	// Cardinal compass diamond markers near the outer ring (pointing toward the 4 walls)
	float d_card_marker = abs(r - 0.415) + d_card * 1.45;
	float card_diamond = 1.0 - smoothstep(0.006, 0.013, d_card_marker);

	// Subtle intercardinal (diagonal) astrolabe filaments
	float d_diag = abs(abs(p.x) - abs(p.y)) * 0.70710678;
	float diag_span = smoothstep(0.165, 0.185, r) * (1.0 - smoothstep(0.268, 0.282, r));
	float diag_ray = (1.0 - smoothstep(0.0009, 0.0026, d_diag)) * diag_span;

	// Accumulate mandala luminance
	float cyan_geom = core_ring * 0.90
		+ r_inner * 0.78
		+ r_mid_a * 0.92
		+ r_mid_b * 0.42
		+ r_outer_a * 0.88
		+ r_outer_b * 0.48
		+ petal_a * 0.42
		+ arc_inner_rot * 0.85
		+ ticks_fine * 0.48
		+ ticks_inner * 0.38
		+ card_core * 0.95
		+ card_glow * 0.24
		+ diag_ray * 0.34;

	float gold_geom = core_inner_ring * 0.78
		+ petal_b * 0.36
		+ arc_outer_rot * 0.78
		+ ticks_major * 0.82
		+ card_diamond * 1.15;

	col += ring_color.rgb * (cyan_geom * 0.72 + core_halo * 0.35) * energy;
	col += accent_color.rgb * (gold_geom * 0.78 + core_center * 0.35) * energy;
	col += vec3(0.88, 0.96, 1.0) * (card_diamond * 0.25) * energy;
	col = mix(col, base_color.rgb * 1.15 + ring_color.rgb * 0.09, core_medallion * 0.62);

	float glow_alpha = clamp((cyan_geom + gold_geom + core_halo) * 0.14 * energy, 0.0, 0.25);

	// Radial countdown timer arc (draining smoothly from 1.0 -> 0.0 clockwise from Center Wall v=0)
	if (show_timer_arc > 0.01) {
		float tr = clamp(timer_ratio, 0.0, 1.0);
		float timer_band = ring_line(r, 0.320, 0.0135);
		float timer_glow_band = ring_line(r, 0.320, 0.028);

		float drain_edge = 1.0 - tr;
		float arc_active = smoothstep(drain_edge - 0.005, drain_edge + 0.005, cw_norm);
		arc_active = mix(arc_active, 1.0, smoothstep(0.992, 1.0, tr));
		arc_active *= smoothstep(0.0, 0.008, tr);

		float ang_dist = abs(cw_norm - drain_edge);
		ang_dist = min(ang_dist, 1.0 - ang_dist);
		float hs_d = ang_dist * 42.0;
		float head_spark = exp(-(hs_d * hs_d)) * ring_line(r, 0.320, 0.020)
			* smoothstep(0.01, 0.04, tr) * (1.0 - smoothstep(0.96, 1.0, tr));

		vec3 safe_col = mix(ring_color.rgb, accent_color.rgb, 0.28);
		vec3 warn_amber = vec3(1.0, 0.64, 0.18);
		vec3 urgent_crimson = vec3(1.0, 0.20, 0.24);

		float to_amber = 1.0 - smoothstep(0.25, 0.48, tr);
		float to_crimson = 1.0 - smoothstep(0.06, 0.25, tr);
		vec3 timer_col = mix(safe_col, warn_amber, to_amber);
		timer_col = mix(timer_col, urgent_crimson, to_crimson);

		float urgent_pulse = mix(1.0, 0.85 + 0.28 * sin(TIME * 9.5), to_crimson);

		vec3 track_col = mix(base_color.rgb * 1.4, ring_color.rgb * 0.22, 0.5);
		float timer_vis = clamp(show_timer_arc, 0.0, 1.0);
		col = mix(col, max(col, track_col), timer_band * 0.65 * timer_vis);
		col += timer_col * (timer_band * 1.25 + timer_glow_band * 0.38) * arc_active * urgent_pulse * timer_vis;
		col += mix(timer_col, vec3(1.0), 0.55) * head_spark * 1.35 * timer_vis;
		glow_alpha += (timer_band * arc_active + head_spark) * 0.22 * timer_vis;
	}

	// Touch shockwave ripple centered at ripple_uv
	if (ripple_age >= 0.0 && ripple_age < 2.2) {
		float d_rip = length(UV - ripple_uv);
		float rip_r = ripple_age * 0.32;
		float rip_fade = exp(-ripple_age * 1.35) * (1.0 - smoothstep(1.75, 2.2, ripple_age));

		float rip_main = 1.0 - smoothstep(0.0025, 0.016 + ripple_age * 0.010, abs(d_rip - rip_r));
		float rip_soft = 1.0 - smoothstep(0.005, 0.042 + ripple_age * 0.018, abs(d_rip - rip_r));
		float echo_r = max(rip_r - 0.045, 0.0);
		float rip_echo = (1.0 - smoothstep(0.002, 0.012, abs(d_rip - echo_r))) * smoothstep(0.12, 0.22, ripple_age);

		float rip_total = (rip_main * 1.15 + rip_soft * 0.32 + rip_echo * 0.48) * rip_fade;
		col += ripple_color * rip_total;
		col += vec3(1.0) * rip_main * rip_fade * 0.30;
		glow_alpha += rip_total * 0.25;
	}

	float final_alpha = clamp(base_color.a + glow_alpha, 0.0, 1.0) * outer_fade;
	if (final_alpha < 0.005) {
		discard;
	}

	ALBEDO = max(col, vec3(0.0));
	ALPHA = final_alpha;
}
