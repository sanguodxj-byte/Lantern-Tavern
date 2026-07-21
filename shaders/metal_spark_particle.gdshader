shader_type spatial;
// 像素风格火花【粒子】Shader：贴在 GPUParticles3D 的 QuadMesh 上。
// 将连续的金属火花量化为块状像素，匹配体素美术风格（与 fire_flame_particle 同配方）。
// 核心：UV 网格化 → 块状噪声 → 阶梯色彩 → 硬边缘 Alpha。
// 双后端兼容：不用 SCREEN_TEXTURE / DEPTH_TEXTURE / discard。

render_mode blend_add, depth_draw_never, cull_disabled;

uniform float speed : hint_range(0.0, 3.0) = 2.0;
// pixel_grid: 每个 quad 划分的像素格数（越大越细腻但仍是块状）
uniform float pixel_grid : hint_range(4.0, 32.0) = 8.0;
// color_steps: 颜色量化阶梯数（越少色带越明显）
uniform float color_steps : hint_range(2.0, 8.0) = 4.0;
uniform vec3 color_core : source_color = vec3(0.92, 0.96, 1.0);
uniform vec3 color_mid : source_color = vec3(0.3, 0.6, 1.0);
uniform vec3 color_edge : source_color = vec3(0.1, 0.25, 0.85);
uniform float intensity : hint_range(0.2, 3.0) = 1.7;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float quantize(float v, float steps) {
	return floor(v * steps + 0.5) / steps;
}

void vertex() {
	// 公告板：每个粒子 quad 始终面向相机，保留粒子自身缩放（来自 scale_curve）。
	vec4 center = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	mat3 m3 = mat3(MODELVIEW_MATRIX);
	vec2 scale = vec2(length(m3[0]), length(m3[1]));
	vec2 offset = VERTEX.xy * scale;
	POSITION = PROJECTION_MATRIX * vec4(center.xy + offset, center.z, 1.0);
}

void fragment() {
	// ── UV 像素化：量化到 pixel_grid 格子 ──
	vec2 puv = floor(UV * pixel_grid) / pixel_grid;
	vec2 c = puv - vec2(0.5);
	float r = length(c) * 2.0;

	// 火花形状：明亮核心 + 环状像素点（不做平滑）
	float core = step(r, 0.4);
	float ring = step(0.35, r) * step(r, 0.75) * (0.4 + 0.6 * hash21(floor(puv * vec2(6.0, 6.0))));
	float body = max(core, ring * 0.7);

	// 阶梯闪烁
	float flick = quantize(0.8 + 0.2 * hash21(vec2(floor(TIME * 1.4), 1.7)), color_steps);
	body *= flick;

	// 阶梯分色：边缘蓝 → 中段亮蓝 → 核心白
	float t = quantize(clamp(body, 0.0, 1.0), color_steps);
	vec3 col = mix(color_edge, color_mid, step(0.3, t));
	col = mix(col, color_core, step(0.7, t));

	ALBEDO = vec3(0.0);
	EMISSION = col * intensity * (0.7 + 0.6 * t);
	// 像素化 Alpha：硬边缘，阶梯过渡
	ALPHA = step(0.2, body);
	ALPHA = clamp(ALPHA, 0.0, 1.0);
}
