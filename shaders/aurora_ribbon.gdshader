shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec3 color_a : source_color = vec3(0.18, 0.84, 0.95);
uniform vec3 color_b : source_color = vec3(0.68, 0.34, 0.98);
uniform float speed : hint_range(0.05, 3.0) = 0.45;
uniform float opacity : hint_range(0.0, 1.0) = 0.35;
uniform float wave_strength : hint_range(0.0, 0.5) = 0.14;

const float FULL_TURN = 6.28318530718;

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

// 2-octave flowing silk noise (fast and GL Compatibility safe)
float fbm2(vec2 p) {
	float v = 0.64 * value_noise2(p);
	v += 0.36 * value_noise2(p * 2.08 + vec2(7.3, 13.1));
	return v;
}

void vertex() {
	float t = TIME * speed;

	// Organic multi-harmonic billowing along surface normal + gentle vertical float
	float sway_primary = sin(UV.x * FULL_TURN * 1.45 + t * 1.25 + UV.y * 2.1);
	float sway_secondary = cos(UV.x * FULL_TURN * 2.65 - t * 0.88 + UV.y * 3.6) * 0.42;
	float lift = sin(UV.x * FULL_TURN * 1.0 - t * 0.72) * 0.28;

	// Smoothly taper displacement near ribbon tips while keeping organic motion
	float end_env = 0.35 + 0.65 * sin(clamp(UV.x, 0.0, 1.0) * 3.14159265);
	vec3 nrm = normalize(NORMAL + vec3(0.0, 0.00001, 0.0));

	VERTEX += nrm * (sway_primary + sway_secondary) * wave_strength * end_env;
	VERTEX.y += lift * wave_strength * 0.45 * end_env;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;

	// Soft feathering strictly to 0.0 at all 4 UV borders (u=0, u=1, v=0, v=1)
	float fade_u = smoothstep(0.0, 0.20, uv.x) * (1.0 - smoothstep(0.80, 1.0, uv.x));
	float fade_v = smoothstep(0.0, 0.24, uv.y) * (1.0 - smoothstep(0.76, 1.0, uv.y));
	float edge_mask = fade_u * fade_v;

	// Flowing layered vertical and diagonal aurora silk streaks
	float warp = sin(uv.x * 5.2 + t * 0.65) * 0.24 + cos(uv.x * 9.0 - t * 0.48) * 0.11;
	vec2 flow_a = vec2(uv.x * 4.4 - t * 0.26, uv.y * 2.1 + warp);
	vec2 flow_b = vec2(uv.x * 7.2 + t * 0.19 + uv.y * 1.15, uv.y * 3.0 - t * 0.12);

	float silk_a = fbm2(flow_a);
	float silk_b = fbm2(flow_b);

	// Sweeping vertical aurora curtain folds
	float curtain_fold = sin(uv.x * 11.0 + t * 0.90 + silk_a * 3.2) * 0.5 + 0.5;
	curtain_fold = pow(clamp(curtain_fold, 0.0, 1.0), 1.65);

	// Fine luminous vertical shimmer rays
	float rays = sin(uv.x * 28.0 - t * 1.15 + silk_b * 4.0) * 0.5 + 0.5;
	rays = pow(clamp(rays, 0.0, 1.0), 2.3);

	// Diagonal ethereal shear streaks
	float diag_streak = sin((uv.x * 8.5 + uv.y * 4.8) - t * 0.82 + silk_a * 2.4) * 0.5 + 0.5;
	diag_streak = diag_streak * diag_streak;

	// Luminous vertical ribbon core (NaN-safe squared Gaussian)
	float cp_d = (uv.y - 0.56) * 3.1;
	float core_profile = 0.58 + 0.58 * exp(-(cp_d * cp_d));
	float density = ((0.35 + 0.65 * silk_a) * (0.45 + 0.55 * curtain_fold) + rays * 0.36 * silk_b + diag_streak * 0.26) * core_profile;

	// Smooth color blend between color_a and color_b across height & wisps
	float col_t = clamp(
		0.14 + (1.0 - uv.y) * 0.60 + (silk_b - 0.5) * 0.34 + 0.16 * sin(uv.x * 4.5 - t * 0.52),
		0.0,
		1.0
	);
	vec3 col = mix(color_a, color_b, col_t);
	col += mix(color_a, vec3(1.0), 0.38) * rays * 0.24 * silk_a;

	float final_alpha = clamp(density * edge_mask * opacity, 0.0, 1.0);

	ALBEDO = max(col * (0.88 + 0.32 * density), vec3(0.0));
	ALPHA = final_alpha;
}
