shader_type spatial;
// 酿造 / 炼金液体表面 Shader — 桌面 Forward+ 与移动 Mobile 双兼容
// 不使用 SCREEN_TEXTURE / DEPTH_TEXTURE / discard，移动端安全。
// 特性：程序化 FBM 涡流法线扰动、上升气泡、配方色、菲涅尔边缘。
// 0 贴图采样，片段着色器开销极低。
// 用法：贴在容器液面的平面 / 圆盘 Mesh 上，让法线朝向 +Y（即平面绕 X 轴 -90° 平放）。

uniform vec4 color_base : source_color = vec4(0.12, 0.55, 0.32, 1.0);
uniform vec4 color_secondary : source_color = vec4(0.70, 0.95, 0.60, 1.0);
uniform float wave_speed : hint_range(0.0, 2.0) = 0.4;
uniform float wave_scale : hint_range(0.5, 8.0) = 3.0;
uniform float bubble_strength : hint_range(0.0, 1.0) = 0.6;
uniform float bubble_speed : hint_range(0.0, 3.0) = 1.2;
uniform float fresnel_power : hint_range(0.5, 5.0) = 2.5;
uniform float roughness : hint_range(0.0, 1.0) = 0.18;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

// --- 程序化噪声（无贴图采样，移动端友好）---
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 固定 4 个倍频，循环次数为常量，移动端安全
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * value_noise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	// 轻微液面起伏：沿局部法线位移，节点经旋转后即为世界 +Y 方向
	float w = fbm(VERTEX.xz * wave_scale * 0.5 + TIME * wave_speed * 0.1);
	VERTEX += NORMAL * (w - 0.5) * 0.04;
}

void fragment() {
	vec2 flow = vec2(TIME * wave_speed * 0.12, TIME * wave_speed * 0.09);
	vec2 uv = UV * wave_scale;

	float n = fbm(uv + flow);

	// 在切线空间用法线贴图扰动液面（无需网格切线，Godot 由导数推导 TBN）
	float eps = 0.02;
	float nx = fbm(uv + vec2(eps, 0.0) + flow) - n;
	float ny = fbm(uv + vec2(0.0, eps) + flow) - n;
	NORMAL_MAP = normalize(vec3(-nx * 4.0, -ny * 4.0, 1.0));

	// 菲涅尔边缘：仅用 VIEW 与 NORMAL，移动端安全（不依赖 DEPTH_TEXTURE）
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);

	// 上升气泡：网格单元内随机亮点，随时间向上滚动
	vec2 bUV = UV * vec2(wave_scale, wave_scale * 2.0);
	bUV.y -= TIME * bubble_speed;
	vec2 cell = fract(bUV) - 0.5;
	float cellRnd = hash21(floor(bUV));
	float d = length(cell);
	float bubble = smoothstep(0.32, 0.26, d) * step(0.55, cellRnd);

	vec3 col = mix(color_base.rgb, color_secondary.rgb, n * 0.6 + fres * 0.4);
	col = mix(col, color_secondary.rgb, fres * 0.7);

	ALBEDO = col;
	EMISSION = color_secondary.rgb * bubble * bubble_strength + color_secondary.rgb * fres * 0.25;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = 0.6;
	ALPHA = 1.0;
}
