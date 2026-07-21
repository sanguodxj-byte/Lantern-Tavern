shader_type spatial;
// 像素风格火焰【粒子】Shader：贴在 GPUParticles3D 的 QuadMesh 上。
// 将连续的火焰效果量化为块状像素，匹配体素美术风格。
// 核心改造：UV 网格化 → 块状噪声 → 阶梯色彩 → 硬边缘 Alpha。
// 桌面 Forward+ + 移动 Mobile 双兼容：不用 SCREEN_TEXTURE / DEPTH_TEXTURE / discard。

render_mode blend_add, depth_draw_never, cull_disabled;

uniform float speed : hint_range(0.0, 3.0) = 1.5;
uniform float turbulence : hint_range(0.0, 2.0) = 1.0;
uniform vec3 color_core : source_color = vec3(1.0, 0.9, 0.55);
uniform vec3 color_mid : source_color = vec3(1.0, 0.45, 0.1);
uniform vec3 color_edge : source_color = vec3(0.7, 0.08, 0.02);
uniform float intensity : hint_range(0.2, 3.0) = 1.8;
uniform float ember_strength : hint_range(0.0, 1.0) = 0.4;

// ── 像素化参数 ──
// pixel_grid: 每个 quad 划分为多少格像素（越大越细腻但仍是块状）
uniform float pixel_grid : hint_range(4.0, 32.0) = 10.0;
// color_steps: 颜色量化阶梯数（越少色带越明显）
uniform float color_steps : hint_range(2.0, 8.0) = 4.0;

// --- 块状噪声（不做插值，纯格子哈希，产生像素方块感）---
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 块状 FBM：每层不做双线性插值，直接取格子值
float block_fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * hash21(floor(p));
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

// 量化到阶梯
float quantize(float v, float steps) {
	return floor(v * steps + 0.5) / steps;
}

void vertex() {
	// 公告板：每个粒子 quad 始终面向相机，并保留粒子自身缩放（来自 scale_curve）。
	vec4 center = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	mat3 m3 = mat3(MODELVIEW_MATRIX);
	vec2 scale = vec2(length(m3[0]), length(m3[1]));
	vec2 offset = VERTEX.xy * scale;
	POSITION = PROJECTION_MATRIX * vec4(center.xy + offset, center.z, 1.0);
}

void fragment() {
	// ── UV 像素化：将连续 UV 量化到 pixel_grid 格子 ──
	vec2 puv = floor(UV * pixel_grid) / pixel_grid;

	// 径向衰减（块状：用量化后的坐标计算）
	float cx = puv.x - 0.5;
	float cy = puv.y - 0.5;
	float r = length(vec2(cx, cy)) * 2.0;
	// 阶梯化径向衰减：硬边缘代替 smoothstep
	float puff = step(r, 0.9) * (0.3 + 0.7 * step(r, 0.5));

	// 块状上升噪声：用量化坐标驱动，产生方块纹理
	float n = block_fbm(puv * 3.0 + vec2(0.0, -floor(TIME * speed * 2.0) * 0.5));
	float n2 = block_fbm(puv * 6.0 + vec2(floor(TIME * 0.4), -floor(TIME * speed * 3.0) * 0.5));
	float turb = mix(n, n2, 0.5) * turbulence;

	float body = puff * (0.6 + 0.6 * turb);

	// 整体闪烁（阶梯化）
	float flick = quantize(0.85 + 0.15 * hash21(vec2(floor(TIME * 0.9), 2.1)), color_steps);
	body *= flick;

	// ── 颜色按阶梯分层：边缘红 → 中段橙 → 核心黄白 ──
	float t = quantize(clamp(body, 0.0, 1.0), color_steps);
	vec3 col = mix(color_edge, color_mid, step(0.25, t));
	col = mix(col, color_core, step(0.6, t));

	// 上升余烬（块状）
	vec2 eUV = floor(puv * vec2(5.0, 5.0));
	eUV.y -= floor(TIME * 1.2);
	float rnd = hash21(eUV);
	// 余烬只在某些格子出现，且偏上方
	float ember = step(0.85, rnd) * step(0.3, puv.y) * step(puv.y, 0.9);

	vec3 fire_col = col * intensity * (0.8 + 0.6 * t);
	fire_col += color_core * ember * ember_strength * 2.0;

	ALBEDO = vec3(0.0);
	EMISSION = fire_col;
	// 像素化 Alpha：硬边缘，阶梯过渡
	ALPHA = step(0.15, body) + ember * ember_strength;
	ALPHA = clamp(ALPHA, 0.0, 1.0);
}
