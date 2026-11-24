shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform vec4 base_color : source_color = vec4(0.06, 0.13, 0.27, 0.88);
uniform vec4 rim_color : source_color = vec4(0.36, 0.88, 1.0, 1.0);
uniform vec4 accent_color : source_color = vec4(1.0, 0.82, 0.42, 1.0);
uniform vec2 uv_tile_scale = vec2(3.0, 2.0);
uniform vec2 panel_size_xy = vec2(1.2, 0.4);
uniform float border_width : hint_range(0.005, 0.15) = 0.022;
uniform float border_glow : hint_range(0.0, 3.0) = 1.05;
uniform float press_glow : hint_range(0.0, 1.5) = 0.0;
uniform float highlight_amount : hint_range(0.0, 1.5) = 0.0;
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform float ghost_amount : hint_range(0.0, 1.0) = 0.0;
uniform float shimmer_speed : hint_range(0.0, 3.0) = 0.45;
uniform float phase_offset = 0.0;

// Precision-safe, trig-free 2D hash for GLES3 / WebGL2
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += vec3(dot(p3, p3.yzx + vec3(33.33)));
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);

	float a = hash12(i + vec2(0.0, 0.0));
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));

	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 3-octave value noise (strictly <= 3 octaves for GL Compatibility)
float fbm3(vec2 p) {
	float v = 0.0;
	v += 0.54 * value_noise2(p);
	p = p * 2.04 + vec2(13.7, 7.3);
	v += 0.30 * value_noise2(p);
	p = p * 2.03 + vec2(5.9, 19.1);
	v += 0.16 * value_noise2(p);
	return v;
}

void fragment() {
	// Remap Godot BoxMesh 3x2 face-atlas UVs cleanly into per-face [0, 1] x [0, 1]
	vec2 uv = fract(UV * uv_tile_scale);
	float t = TIME;

	// Compute uniform world-meter edge distances so borders have identical crisp width on all 4 sides
	vec2 p_size = max(panel_size_xy, vec2(0.2, 0.2));
	vec2 edge_uv = min(uv, vec2(1.0) - uv);
	vec2 edge_m = edge_uv * p_size;
	float d_edge = min(edge_m.x, edge_m.y);
	float max_edge = max(edge_m.x, edge_m.y);
	float v_top = 1.0 - uv.y;

	// Frosted glass body: slightly deeper at bottom, airier near top for crisp Label3D legibility
	float frost = value_noise2(uv * p_size * 5.0 + vec2(phase_offset * 3.1, 0.0));
	vec3 glass_body = base_color.rgb * mix(0.84, 1.18, v_top);
	float top_air = pow(clamp(v_top, 0.0, 1.0), 2.4);
	glass_body += rim_color.rgb * (0.04 * top_air + 0.015 * (frost - 0.5));
	float r_center = length((uv - vec2(0.5)) * vec2(1.15, 1.0));
	glass_body *= mix(0.95, 1.05, smoothstep(0.18, 0.65, r_center));

	// Fresnel edge iridescence (clamped base for GLES3 pow safety)
	float ndotv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float fresnel = pow(max(1.0 - ndotv, 0.0), 2.8);
	float irid_phase = sin(uv.x * 4.2 - uv.y * 3.1 + t * 0.55 + phase_offset) * 0.5 + 0.5;
	vec3 irid_col = mix(rim_color.rgb, accent_color.rgb, 0.22 + 0.42 * irid_phase);

	// Crisp symmetric outer rim + soft inner halo + hairline inner bezel + crystalline corner clasps
	float bw = max(border_width, 0.008);
	float outer_rim = 1.0 - smoothstep(bw * 0.25, bw, d_edge);
	float rim_halo = (1.0 - smoothstep(bw * 0.5, bw * 3.2, d_edge)) * 0.26;

	float bezel_pos = bw * 2.1;
	float bezel_thick = max(bw * 0.22, 0.003);
	float inner_bezel = (1.0 - smoothstep(0.0, bezel_thick, abs(d_edge - bezel_pos))) * 0.30;

	float corner_len = clamp(min(p_size.x, p_size.y) * 0.22, bw * 2.2, 0.14);
	float corner_zone = 1.0 - smoothstep(corner_len * 0.65, corner_len, max_edge);
	float corner_clasp = corner_zone * (1.0 - smoothstep(bw * 0.35, bw * 1.45, d_edge));

	// Slow diagonal crystalline glass-sheen sweep
	float diag = uv.x * 0.72 + uv.y * 0.48;
	float sweep_cycle = fract((t * shimmer_speed + phase_offset) * 0.15);
	float sweep_pos = sweep_cycle * 2.2 - 0.5;
	float sw_d = (diag - sweep_pos) * 5.8;
	float ss_d = (diag - (sweep_pos + 0.042)) * 20.0;
	float sheen_wide = exp(-(sw_d * sw_d));
	float sheen_sharp = exp(-(ss_d * ss_d));
	float sheen = (sheen_wide * 0.06 + sheen_sharp * 0.11) * (1.0 - ghost_amount * 0.55);

	// Highlight state: warm golden-cyan breathing aura
	float hi = clamp(highlight_amount, 0.0, 1.5);
	float hi_pulse = 0.88 + 0.12 * sin(t * 3.2 + phase_offset);
	float hi_norm = clamp(hi / 1.5, 0.0, 1.0);
	vec3 active_rim_col = mix(rim_color.rgb, mix(rim_color.rgb, accent_color.rgb, 0.72), clamp(hi * 0.72, 0.0, 1.0));
	vec3 corner_col = mix(mix(rim_color.rgb, vec3(1.0), 0.28), accent_color.rgb, clamp(0.32 + hi * 0.58, 0.0, 1.0));

	// Press feedback: expanding radial inner flash + luminous rim surge
	float pg = clamp(press_glow, 0.0, 1.5);
	float press_ring_r = mix(0.08, 0.58, clamp(pg / 1.5, 0.0, 1.0));
	float pr_d = (r_center - press_ring_r) * 7.5;
	float press_wave = exp(-(pr_d * pr_d)) * pg;
	float press_fill = (1.0 - smoothstep(0.05, 0.72, r_center)) * pg * 0.34;
	vec3 press_tint = mix(rim_color.rgb, accent_color.rgb, 0.42) + vec3(0.22);

	// Compose solid frosted glass monolith color (balanced to avoid over-bloom)
	float effective_border_glow = border_glow * (0.85 + hi * 0.38 * hi_pulse + pg * 0.65);
	vec3 solid_col = glass_body;
	solid_col += mix(rim_color.rgb, vec3(1.0), 0.38) * sheen;
	solid_col += irid_col * fresnel * (0.36 + hi * 0.22);
	solid_col += active_rim_col * rim_halo * effective_border_glow * (0.48 + hi * 0.42 * hi_pulse);
	solid_col += active_rim_col * inner_bezel * (0.45 + hi * 0.35);
	solid_col += active_rim_col * outer_rim * effective_border_glow * 0.82;
	solid_col += corner_col * corner_clasp * (0.55 + hi * 0.45 + pg * 0.40);
	solid_col += accent_color.rgb * (0.08 * hi * hi_pulse * (0.45 + 0.55 * rim_halo));
	solid_col += press_tint * (press_wave * 0.55 + press_fill);

	float solid_alpha = clamp(
		base_color.a + outer_rim * 0.12 + corner_clasp * 0.10 + hi_norm * 0.06 + pg * 0.08,
		0.0,
		1.0
	);

	// Ghost "memory echo" state: dreamy faint interior (~0.08 alpha) + delicate shimmering thin rim
	float thin_rim = 1.0 - smoothstep(bw * 0.14, bw * 0.65, d_edge);
	float ghost_shimmer = 0.58 + 0.42 * sin((uv.x - uv.y) * 5.2 + t * 1.45 + phase_offset);
	vec3 ghost_col = mix(base_color.rgb * 0.65, rim_color.rgb * 0.42, 0.45);
	ghost_col += mix(rim_color.rgb, irid_col, 0.4) * (thin_rim * (0.72 * ghost_shimmer) + fresnel * 0.28);
	ghost_col += corner_col * corner_clasp * 0.28 * ghost_shimmer;
	float ghost_alpha = clamp(0.08 + thin_rim * 0.36 * ghost_shimmer + corner_clasp * 0.14 + fresnel * 0.06, 0.0, 0.62);

	float g = clamp(ghost_amount, 0.0, 1.0);
	vec3 final_col = mix(solid_col, ghost_col, g);
	float final_alpha = mix(solid_alpha, ghost_alpha, g);

	// Procedural dissolve with luminous accent burn frontier
	if (dissolve_amount > 0.001) {
		float n = fbm3(uv * vec2(5.2, 3.8) + vec2(phase_offset * 1.73, phase_offset * 0.91));
		float dissolve_field = clamp(n * 0.80 + v_top * 0.20, 0.0, 1.0);

		float band_w = 0.13;
		float thresh = dissolve_amount * (1.0 + band_w * 2.0) - band_w;
		float keep_mask = smoothstep(thresh, thresh + band_w, dissolve_field);

		float frontier = 1.0 - smoothstep(0.0, band_w * 1.15, abs(dissolve_field - (thresh + band_w * 0.45)));
		float active_dissolve = smoothstep(0.0, 0.05, dissolve_amount) * (1.0 - smoothstep(0.94, 1.0, dissolve_amount));
		float burn = frontier * active_dissolve;

		vec3 burn_col = mix(accent_color.rgb, vec3(1.0, 0.96, 0.86), burn * 0.45) * 1.95;
		final_col = mix(final_col, burn_col, clamp(burn * 1.15, 0.0, 1.0));
		final_alpha = clamp(final_alpha * keep_mask + burn * 0.85 * (1.0 - smoothstep(0.92, 1.0, dissolve_amount)), 0.0, 1.0);
	}

	if (final_alpha < 0.01) {
		discard;
	}

	ALBEDO = max(final_col, vec3(0.0));
	ALPHA = final_alpha;
}
