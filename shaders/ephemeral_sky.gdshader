shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.02, 0.03, 0.085);
uniform vec3 horizon_color : source_color = vec3(0.07, 0.13, 0.27);
uniform vec3 aurora_primary : source_color = vec3(0.18, 0.85, 0.90);
uniform vec3 aurora_secondary : source_color = vec3(0.62, 0.34, 0.95);
uniform vec3 state_accent : source_color = vec3(0.20, 0.80, 0.95);
uniform float accent_mix : hint_range(0.0, 1.0) = 0.25;
uniform float aurora_intensity : hint_range(0.0, 2.5) = 0.90;
uniform float star_density : hint_range(0.0, 1.0) = 0.65;

const float FULL_TURN = 6.28318530718;

// Precision-safe, trig-free hashes for GLES3 / WebGL2
float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += vec3(dot(p3, p3.yzx + vec3(33.33)));
	return fract((p3.x + p3.y) * p3.z);
}

vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += vec3(dot(p3, p3.yxz + vec3(33.33)));
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// Smooth 3D value noise (seam-free across the full 360-degree sphere)
float value_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);

	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);

	float nxy0 = mix(nx00, nx10, u.y);
	float nxy1 = mix(nx01, nx11, u.y);

	return mix(nxy0, nxy1, u.z);
}

// 2-octave 3D fbm (lightweight for GL Compatibility)
float fbm3_2(vec3 p) {
	float v = 0.0;
	v += 0.65 * value_noise3(p);
	v += 0.35 * value_noise3(p * 2.07 + vec3(11.3, 5.7, 17.1));
	return v;
}

// Pole-pinch-free and seam-free cube-projected star layer
vec3 star_layer(vec3 dir, float scale, float density_threshold, float time_val, float seed_offset) {
	vec3 ad = abs(dir);
	vec2 face_uv;
	float face_id;

	if (ad.x >= ad.y && ad.x >= ad.z) {
		face_uv = dir.yz / max(ad.x, 0.0001);
		face_id = dir.x > 0.0 ? 1.0 : 2.0;
	} else if (ad.y >= ad.x && ad.y >= ad.z) {
		face_uv = dir.xz / max(ad.y, 0.0001);
		face_id = dir.y > 0.0 ? 3.0 : 4.0;
	} else {
		face_uv = dir.xy / max(ad.z, 0.0001);
		face_id = dir.z > 0.0 ? 5.0 : 6.0;
	}

	vec2 grid = (face_uv * 0.5 + vec2(0.5)) * scale;
	vec2 cell_id = floor(grid);
	vec2 cell_f = fract(grid);

	vec3 rnd = hash33(vec3(cell_id, face_id * 19.7 + seed_offset));
	if (rnd.z > density_threshold) {
		return vec3(0.0);
	}

	// Keep star centers safely inside each cell so cube boundaries never clip
	vec2 star_pos = vec2(0.20) + rnd.xy * 0.60;
	float d = length(cell_f - star_pos);

	float mag = hash13(vec3(cell_id + vec2(13.1), face_id + seed_offset * 3.1));
	float radius = mix(0.045, 0.115, mag * mag);
	float core = 1.0 - smoothstep(0.0, radius, d);
	float halo = (1.0 - smoothstep(0.0, radius * 2.4, d)) * 0.28;

	float twinkle_speed = 1.1 + rnd.x * 2.6;
	float twinkle = 0.62 + 0.38 * sin(time_val * twinkle_speed + rnd.y * FULL_TURN);

	// Subtle star temperature tint: icy blue-white -> pearl -> soft gold
	vec3 star_tint = mix(vec3(0.76, 0.88, 1.0), vec3(1.0, 0.94, 0.82), rnd.x);
	float brightness = mix(0.32, 1.15, pow(max(mag, 0.0001), 2.2)) * twinkle;

	return star_tint * (core * core + halo) * brightness;
}

// Seam-free 360-degree aurora curtain using integer azimuth harmonics + 3D noise
vec3 evaluate_aurora(vec3 dir, float azim, float elev, float t, vec3 col_low, vec3 col_high) {
	// Strictly integer multiples of azim guarantee identical value & slope at -PI and +PI
	float wave_a = sin(2.0 * azim + t * 0.16) * 0.11
		+ cos(3.0 * azim - t * 0.11) * 0.075
		+ sin(5.0 * azim + t * 0.21) * 0.035;

	float wave_b = cos(2.0 * azim - t * 0.13 + 1.4) * 0.10
		+ sin(4.0 * azim + t * 0.17) * 0.06
		+ cos(6.0 * azim - t * 0.19) * 0.025;

	// Seam-free 3D turbulence sampled directly on unit direction
	float turb_a = fbm3_2(vec3(dir.x * 2.4, dir.y * 1.6, dir.z * 2.4) + vec3(t * 0.05, -t * 0.03, t * 0.04));
	float turb_b = fbm3_2(vec3(dir.x * 3.6, dir.y * 2.1, dir.z * 3.6) - vec3(t * 0.04, t * 0.025, -t * 0.05));

	// Ribbon 1: main sweeping luminous curtain
	float center_a = 0.24 + wave_a + (turb_a - 0.5) * 0.14;
	float rel_a = elev - center_a;
	float vert_a = smoothstep(-0.07, 0.015, rel_a) * (1.0 - smoothstep(0.03, 0.34, rel_a));
	float rays_a = 0.55 + 0.45 * sin(10.0 * azim + turb_a * 4.5 + t * 0.35);
	float fine_a = 0.65 + 0.35 * cos(18.0 * azim - turb_a * 3.2 - t * 0.25);
	float band_a = vert_a * rays_a * fine_a * (0.45 + 0.55 * turb_a);

	// Ribbon 2: higher violet-amethyst secondary drift
	float center_b = 0.40 + wave_b + (turb_b - 0.5) * 0.16;
	float rel_b = elev - center_b;
	float vert_b = smoothstep(-0.08, 0.02, rel_b) * (1.0 - smoothstep(0.04, 0.36, rel_b));
	float rays_b = 0.55 + 0.45 * sin(13.0 * azim - turb_b * 4.0 - t * 0.28);
	float band_b = vert_b * rays_b * (0.42 + 0.58 * turb_b);

	// Height-graded curtain colors (cyan/teal at lower base, violet/orchid rising upward)
	float grad_a = smoothstep(-0.02, 0.24, rel_a);
	float grad_b = smoothstep(-0.03, 0.26, rel_b);

	vec3 ribbon_col_a = mix(col_low, col_high, grad_a * 0.78);
	vec3 ribbon_col_b = mix(mix(col_low, col_high, 0.42), col_high, grad_b);

	// Subtle shimmer boost right along the curtain lower crest (NaN-safe squared Gaussian)
	float crest_d = rel_a * 19.0;
	float crest_a = exp(-(crest_d * crest_d)) * rays_a * 0.48;
	ribbon_col_a += col_low * crest_a;

	// Fade cleanly near horizon and right at the zenith cap
	float sky_mask = smoothstep(0.01, 0.14, elev) * (1.0 - smoothstep(0.76, 0.98, elev));
	return (ribbon_col_a * band_a + ribbon_col_b * band_b * 0.78) * sky_mask;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float elev = dir.y;
	// Guard against atan(0, 0) at exact zenith/nadir poles (undefined in GLSL ES 3.00 / WebGL2)
	float azim = (abs(dir.x) + abs(dir.z) > 0.0001) ? atan(dir.z, dir.x) : 0.0;
	float t = TIME;

	// Blend game-state accent softly into horizon & aurora palette
	vec3 tinted_horizon = mix(horizon_color, mix(horizon_color, state_accent, 0.55), accent_mix);
	vec3 col_aurora_a = mix(aurora_primary, state_accent, accent_mix * 0.45);
	vec3 col_aurora_b = mix(aurora_secondary, mix(aurora_secondary, state_accent, 0.5), accent_mix * 0.35);

	// Upper twilight sky gradient: luminous atmospheric horizon -> serene deep indigo zenith
	float upper_t = pow(clamp(max(elev, 0.0), 0.0, 1.0), 0.52);
	vec3 upper_sky = mix(tinted_horizon, zenith_color, upper_t);

	// Below-horizon calm deep-indigo sanctuary abyss with soft reflection glow
	float lower_t = pow(clamp(max(-elev, 0.0), 0.0, 1.0), 0.58);
	vec3 nadir_color = zenith_color * vec3(0.52, 0.58, 0.72);
	vec3 lower_sky = mix(tinted_horizon * 0.82, nadir_color, lower_t);

	vec3 col = mix(lower_sky, upper_sky, smoothstep(-0.04, 0.04, elev));

	// Soft luminous atmospheric mist belt hugging the 360-degree horizon
	float horizon_mist = exp(-abs(elev) * 9.0);
	float mist_shimmer = 0.88 + 0.12 * sin(3.0 * azim + t * 0.12);
	vec3 mist_tint = mix(horizon_color * 1.25, state_accent * 0.78, accent_mix * 0.65);
	col += mist_tint * horizon_mist * 0.34 * mist_shimmer;

	// Subtle cosmic nebula veil in upper dome
	float upper_mask = smoothstep(-0.02, 0.22, elev);
	float nebula = fbm3_2(dir * 2.8 + vec3(0.0, t * 0.012, 0.0));
	float nebula_band = smoothstep(0.42, 0.85, nebula) * upper_mask * (1.0 - smoothstep(0.65, 0.98, elev));
	col += mix(col_aurora_b, state_accent, 0.35) * nebula_band * (0.07 + 0.05 * accent_mix);

	// Layered 360-degree undulating aurora ribbons
	vec3 aurora = evaluate_aurora(dir, azim, max(elev, 0.0), t, col_aurora_a, col_aurora_b);
	float aurora_luma = dot(aurora, vec3(0.299, 0.587, 0.114));
	col += aurora * aurora_intensity * 0.92;

	// Calm faint aurora reflection whisper below the horizon
	if (elev < 0.04) {
		float refl_elev = max(-elev, 0.0);
		float refl_mask = (1.0 - smoothstep(0.0, 0.42, refl_elev)) * (1.0 - smoothstep(-0.02, 0.04, elev));
		float refl_wave = 0.5 + 0.5 * sin(2.0 * azim + t * 0.16);
		col += mix(col_aurora_a, col_aurora_b, 0.5) * refl_mask * refl_wave * aurora_intensity * 0.09;
	}

	// Twinkling celestial starfield in upper hemisphere
	if (elev > 0.01 && star_density > 0.001) {
		float star_fade = smoothstep(0.02, 0.26, elev);
		float aurora_occlude = 1.0 / (1.0 + aurora_luma * aurora_intensity * 2.2);
		vec3 stars_bright = star_layer(dir, 36.0, star_density * 0.24, t, 1.0);
		vec3 stars_dust = star_layer(dir, 78.0, star_density * 0.34, t * 0.85, 7.3) * 0.58;
		col += (stars_bright + stars_dust) * star_fade * aurora_occlude;
	}

	COLOR = max(col, vec3(0.0));
}
