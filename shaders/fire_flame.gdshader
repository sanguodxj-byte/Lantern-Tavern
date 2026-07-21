shader_type spatial;
// 程序化火焰 Shader（单 quad 相机朝向公告板），替换开源 GPUParticles3D 火焰方案。
// 桌面 Forward+ + 移动 Mobile 双兼容：不使用 SCREEN_TEXTURE / DEPTH_TEXTURE / discard。
// 单 draw call、单 quad，overdraw 远低于 36~56 个粒子 quad 的加法混合堆叠。
// 用法：MeshInstance3D 挂一个 QuadMesh（面朝 +Z），材质用本 ShaderMaterial；
//      节点位置设在火焰底部，QuadMesh 尺寸即火焰尺寸（高度方向 UV.y=0 为底、1 为顶）。

render_mode blend_add, depth_draw_never, cull_disabled;

uniform float speed : hint_range(0.0, 3.0) = 1.2;
uniform float turbulence : hint_range(0.0, 2.0) = 1.0;
uniform vec3 color_core : source_color = vec3(1.0, 0.9, 0.55);
uniform vec3 color_mid : source_color = vec3(1.0, 0.45, 0.1);
uniform vec3 color_edge : source_color = vec3(0.7, 0.08, 0.02);
uniform float intensity : hint_range(0.2, 3.0) = 1.6;
uniform float ember_strength : hint_range(0.0, 1.0) = 0.5;

// --- 程序化噪声（0 贴图采样，移动端友好）---
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 固定 4 倍频，循环次数常量，移动端安全
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	// 公告板：把 quad 放到节点原点处的相机平面，始终面向相机。
	// VERTEX.xy 是 QuadMesh 的局部角点（±尺寸/2），直接加进视图空间即可。
	vec4 pos = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	pos.xy += VERTEX.xy;
	POSITION = PROJECTION_MATRIX * pos;
}

void fragment() {
	float h = 1.0 - UV.y;       // 0 顶 -> 1 底 (Godot QuadMesh 默认 UV.y=0 在顶部,因此取反后 h=0 为底、1 为顶,符合底宽顶窄的火焰形态)
	float w = UV.x - 0.5;    // 居中宽度

	// 火焰形态：底宽顶窄
	float wMax = mix(0.5, 0.06, h);
	float hprof = smoothstep(wMax, 0.0, abs(w));
	float vfall = smoothstep(1.0, 0.05, h);

	// 上升噪声扰动（减 TIME 使噪声向上流动）
	float n = fbm(vec2(w * 3.0, h * 3.0 - TIME * speed));
	float n2 = fbm(vec2(w * 7.0 + TIME * 0.3, h * 5.0 - TIME * speed * 1.6));
	float turb = mix(n, n2, 0.5) * turbulence;

	float body = hprof * vfall * (0.55 + 0.7 * turb);

	// 整体闪烁
	float flick = 0.85 + 0.15 * fbm(vec2(TIME * 0.7, 1.3));
	body *= flick;

	// 颜色按强度分层：边缘红 -> 中段橙 -> 核心黄白
	float t = clamp(body, 0.0, 1.0);
	vec3 col = mix(color_edge, color_mid, smoothstep(0.15, 0.5, t));
	col = mix(col, color_core, smoothstep(0.5, 0.95, t));

	// 上升余烬：网格单元内随机亮点，随时间上滚
	vec2 eUV = UV * vec2(7.0, 4.0);
	eUV.y -= TIME * 1.1;
	vec2 ecell = fract(eUV) - 0.5;
	float rnd = hash21(floor(eUV));
	float ed = length(ecell);
	float ember = smoothstep(0.1, 0.04, ed) * step(0.82, rnd) * smoothstep(0.1, 0.6, h);

	vec3 fire_col = col * intensity * (0.8 + 0.6 * t);
	fire_col += color_core * ember * ember_strength * 2.0;

	ALBEDO = vec3(0.0);
	EMISSION = fire_col;
	// 加法混合下 ALPHA 调制贡献强度；边缘柔化避免硬切（不用 discard）
	ALPHA = smoothstep(0.04, 0.22, body) + ember * ember_strength;
	ALPHA = clamp(ALPHA, 0.0, 1.0);
}
