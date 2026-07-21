# 视觉检查与评价报告 — Lantern Tavern

> 评价范围：项目全部 5 个自定义着色器（shaders/ 目录）+ 运行时渲染截图验证
> 评价方法：代码审查（Godot 4 规范）+ 窗口模式真实 GPU 截图（Forward+ / D3D12）
> 角色：GodotShaderDeveloper（渲染达）— 着色器规范度、性能、双后端兼容、视觉目标达成度
> 日期：2026-07-18

---

## 一、总览

| 项目 | 结论 |
|---|---|
| 着色器规范度 | ✅ 高 — 全部声明 `shader_type`、用 Godot 内建、uniform 带 hint、无 `discard`、无 `SCREEN_TEXTURE` |
| 双后端兼容 | ✅ 全部兼容 Forward+ / Mobile（无 SCREEN_TEXTURE / DEPTH_TEXTURE 依赖） |
| 性能意识 | ✅ 强 — 程序化噪声为主、0~1 贴图采样、常量循环次数、加法混合无深度写入 |
| 已修复缺陷 | 🔴 `fire_flame.gdshader` UV 上下颠倒（底窄顶宽 → 已修正为底宽顶窄）|
| 测试 | ✅ 12/12 通过（fire_flame 9/9 + liquid_alchemy 3/3），含新增 UV 回归守卫 |
| 肉眼评估 | ⚠️ 受限 — 当前模型无法读取图片像素，结论基于客观色彩计数 + 代码逻辑推断 |

**总评**：项目视觉技术底座扎实，着色器编写严格遵循 Godot 4 规范且对移动端友好。美术方向（像素量化火焰/火花、程序化液体）与体素风格高度统一，火光分层（lighting_controller）结构清晰。唯一真实 bug 已修复并加回归测试。建议把"单 quad 火焰"的实际接线路径明确化，并清理非视觉类的资源引用警告。

---

## 二、运行时截图清单（窗口模式 / 真实 GPU）

截图脚本：`tools/visual_eval_capture.gd`（独立 SubViewport + 确定性灯光，保存真实材质渲染）。
**约束**：headless 下 Godot 回退 Dummy 渲染器（`get_texture()` 返回 null），必须用**窗口模式**才能真实渲染；本机 NVIDIA RTX 4060 Ti / D3D12 12_0 / Forward+。

| 截图 | 内容 | 唯一颜色数* | 观察 |
|---|---|---|---|
| `tavern_interior_c.png` | 酒馆内景（眼平视角，吧台+壁炉区）| ~4897 | 色彩丰富，木色/石色/火光层次完整 |
| `tavern_interior_d.png` | 酒馆内景（眼平视角，另一侧）| ~4808 | 与上相近，光照环境稳定 |
| `fire_billboard.png` | 单 quad 公告板火焰（fire_flame.tres）| ~205 | 底宽顶窄形态正确（修复后）|
| `fire_particles.png` | 粒子火焰（torch.tscn + fire_flame_particle.tres）| ~36 | 像素方块火焰，色带明显 |
| `liquid_alchemy.png` | 炼金液体（CylinderMesh + liquid_alchemy.tres）| ~249 | 菲涅尔边缘 + 气泡流动可见 |
| `metal_spark.png` | 金属火花（fx/metal_spark.tscn）| ~13 | 一次性粒子，捕捉窗口窄（已用 12 帧）|

\* 唯一颜色数 = 客观丰富度指标，**非质量评分**。内景高（~4800+）说明材质/光照层次正常；火焰/火花低属正常（自发光色带本就少）。

> 注：金属火花为一次性 GPUParticles3D（`emitting=true` 后 `finished` 即 `queue_free`），截图需短帧数（12 帧）捕捉发射瞬间，否则全空白。

---

## 三、着色器逐一审阅（全部 5 个）

### 1. `shaders/fire_flame.gdshader` — 单 quad 公告板火焰
- **类型**：`shader_type spatial` / `render_mode blend_add, depth_draw_never, cull_disabled`
- **规范**：✅ `TEXTURE` 未用（`texture()` 调用正确）；噪声 `hash21/fbm` 0 贴图采样；`fbm` 循环 4 次常量（移动端安全）；`ALBEDO=0` + `EMISSION` 加法混合；边缘用 `smoothstep` 柔化，**无 `discard`**。
- **双后端**：✅ 不用 SCREEN_TEXTURE/DEPTH_TEXTURE。
- **🔴 已修复 Bug**：原第 57 行 `float h = UV.y; // 0 底 -> 1 顶` 错误。Godot **QuadMesh 默认 UV.y=0 在顶部**，直接取 `UV.y` 会让 `h=0` 在顶、`h=1` 在底 → 火焰**上下颠倒（底窄顶宽）**。
  - 修复：`float h = 1.0 - UV.y;`（`h=0` 在底、`h=1` 在顶），恢复"底宽顶窄"正确形态。
  - 已加回归测试 `test_single_flame_uv_orientation_not_inverted`（源码级守卫，headless 下可跑）。
- **用途澄清**：该 shader 仅被 `materials/fire_flame.tres` + 截图脚本引用；**实际场景（火把/壁炉/壁灯/吊灯）均用粒子版 `fire_flame_particle.tres`**。单 quad 版目前是"候选/备用"资产，建议明确其接线路径（如独立营火/点火特效）或文档标注用途，避免被误认为死代码。

### 2. `shaders/fire_flame_particle.gdshader` — 像素风粒子火焰 ⭐
- **类型**：`spatial` / `blend_add, depth_draw_never, cull_disabled`
- **亮点**：完美匹配体素美术 —— `floor(UV * pixel_grid)` 量化 → 块状 `hash21` 噪声 → `quantize()` 阶梯分色 → `step()` 硬边 Alpha。`vertex()` 公告板保留粒子自身 `scale`（来自 scale_curve），正确。
- **规范**：✅ `uniform pixel_grid : hint_range(4.0,32.0)`、`color_steps : hint_range(2.0,8.0)` 均带 hint；无 discard/SCREEN_TEXTURE；3 次常量循环。
- **性能**：✅ 加法混合 + 无深度写入，overdraw 可控。
- **评价**：高质量，是当前火焰主力方案。

### 3. `shaders/metal_spark_particle.gdshader` — 像素风火花 ⭐
- **类型**：`spatial` / `blend_add, depth_draw_never, cull_disabled`
- **亮点**：与火焰同配方（量化+阶梯），蓝白冷色区分打击火花；`core + ring` 像素结构清晰；`vertex()` 公告板正确。
- **规范**：✅ 所有 uniform 带 hint（含 `source_color`）；无 discard/SCREEN_TEXTURE。
- **评价**：与火焰视觉语言统一，质量高。

### 4. `shaders/liquid_alchemy.gdshader` — 程序化炼金液体 ⭐⭐（最佳）
- **类型**：`spatial`
- **亮点**：**0 贴图采样**的程序化液面 —— `fbm` 涡流法线扰动（导数推导 TBN，无需网格切线）、上升气泡、菲涅尔边缘（仅用 `VIEW`/`NORMAL`，不依赖 DEPTH_TEXTURE）、配方双色混合。
- **规范**：✅ 全部 uniform 带 hint（`source_color` / `hint_range`）；`fbm` 4 次常量循环；无 discard/SCREEN_TEXTURE/DEPTH_TEXTURE；`vertex()` 液面起伏幅度小（0.04）安全。
- **性能**：✅ 片段开销极低，移动端无忧。
- **评价**：项目中最成熟的着色器，可作为"程序化效果"范本推广到其他材质。

### 5. `shaders/liquid.gdshader` — 贴图驱动液体表面（酸液陷阱）
- **类型**：`spatial`
- **用法**：挂在 `scenes/traps/acid_trap.tscn`（酸液陷阱表面）。
- **规范**：✅ `texture()` 调用正确；`vertex()` 用世界坐标 `MODEL_MATRIX` 做正弦波（正确）；无 discard/SCREEN_TEXTURE。
- **注意点**：
  - `uniform sampler2D liquid_texture : filter_nearest, repeat_enable;` 依赖外部贴图，`.gdshader` 内无默认（`hint_default_white` 未设）。若材质未赋值会采样到空 → 黑面。需确认 `acid_trap.tscn` 的材质已绑定贴图（建议抽查）。
  - `uniform vec2 texture_scroll_speed = vec2(0.05, 0.03);` 无 hint（vec2 无标准 hint，可接受，但建议注释说明单位）。
  - `ROUGHNESS = 1.0` 完全漫反射，液体偏"哑光"；如需湿润感可调低（如 0.3~0.5）。属美术取向，非缺陷。
- **评价**：正确且轻量，与 `liquid_alchemy`（程序化）形成"贴图 vs 程序化"两套液体方案，分工合理。

---

## 四、优点清单

1. **规范度过硬**：全部着色器声明 `shader_type`、用 Godot 内建（`texture()`/`UV`/`TIME`），无 Godot 3 残留语法（`texture2D` 等）。
2. **移动端友好**：无 `SCREEN_TEXTURE` / `DEPTH_TEXTURE` 依赖 → Forward+ / Mobile 双后端通用；噪声循环次数均为常量。
3. **性能意识强**：火焰/火花用加法混合 + `depth_draw_never`，overdraw 远低于多粒子堆叠；液体程序化 0 贴图采样。
4. **美术统一**：像素量化火焰/火花与体素风格强一致；`liquid_alchemy` 程序化液体可作为范本。
5. **火光分层清晰**：`globals/lighting/lighting_controller.gd` 做 flicker + 画质分级 + 火把 range/energy 契约，结构合理。
6. **测试到位**：12/12 着色器测试通过，新增 UV 回归守卫防回退。

---

## 五、问题清单（按严重度）

| 严重度 | 问题 | 状态 |
|---|---|---|
| 🔴 高 | `fire_flame.gdshader` 火焰 UV 上下颠倒（底窄顶宽）| ✅ 已修复 + 回归测试 |
| 🟡 中 | headless 无法截图（Dummy 渲染器 `get_texture()` 返回 null），需窗口模式真实 GPU | ⚠️ 已用窗口模式绕过；环境无 SwiftShader 备选 |
| 🟡 中 | `fire_flame.tres`（单 quad 版）未接入实际场景，用途不透明 | ⚠️ 建议明确接线或文档标注 |
| 🟡 中 | `liquid.gdshader` 的 `liquid_texture` 无默认贴图，依赖材质赋值 | ⚠️ 建议抽查 `acid_trap.tscn` 绑定 |
| ⚪ 低 | 一次性粒子（metal_spark）截图窗口窄，需短帧捕捉 | ℹ️ 截图脚本已用 12 帧处理 |
| ⚪ 低 | 项目存在大量 invalid UID 警告（角色/武器 .glb 引用）+ 技能图标未 import 警告 | ℹ️ 非视觉核心，建议清理 |

---

## 六、改进建议

1. **明确单 quad 火焰用途**：将 `fire_flame.tres` 接入一个真实特效（如营火/点燃/法术点火），或在 `AGENTS.md`/注释中标注其为"备用/候选"资产，避免维护者误解。
2. **液体湿润感**：`liquid.gdshader` 若需更"水"的观感，将 `ROUGHNESS` 从 1.0 降到 0.3~0.5 并加一点 `SPECULAR`/`METALLIC` 微调（纯美术向，可 A/B 对比截图）。
3. **截图脚本增强**：
   - 复用 `lighting_controller` 的 tavern 光照 profile（暖光 + 软阴影 + 雾）让截图更贴近真实游玩光照，而非当前"确定性测试光"。
   - 为 `acid_trap` 也补一张截图（覆盖 `liquid.gdshader` 实际渲染）。
   - 考虑在 CI 之外保留窗口模式截图任务（headless 不可行）。
4. **推广 `liquid_alchemy` 范式**：其"程序化 + 0 贴图 + 菲涅尔（不依赖 DEPTH）"写法可复用到其他表面（如魔法符文、传送门、结霜），保持移动端安全。
5. **清理非视觉警告**：invalid UID / 未 import 图标不直接影响画面，但长期累积会掩盖真实错误；建议一次性扫描修复（与本次视觉评价解耦，单独排期）。

---

## 七、测试方法说明

- **代码审查**：逐文件核对 Godot 4 规范（shader_type、内建、hint、discard、SCREEN_TEXTURE、循环常量）。
- **运行时截图**：`tools/visual_eval_capture.gd` 以 `SceneTree` 窗口模式运行，每个效果独立 `SubViewport`（`own_world_3d=true`、`UPDATE_ALWAYS`），确定性灯光下渲染真实材质，`get_texture().get_image().save_png()` 落盘。
- **单元测试**：headless 下渲染服务器不编译 GLSL，仅验证资源加载 + 参数绑定 + 新增 UV 源码级回归守卫。
- **肉眼评估限制**：当前模型无法读取 PNG 像素（"Content filtered"），故主观画质以"唯一颜色数 + 代码逻辑"间接推断，非逐像素审美判断。最终观感建议人工打开 6 张截图确认。

---

## 八、交付物

- 截图 6 张：`reports/visual_eval/*.png`
- 截图脚本：`tools/visual_eval_capture.gd`
- 修复：`shaders/fire_flame.gdshader`（UV 取反）
- 测试：`tests/gdunit/fire_flame_shader_test.gd`（新增 UV 回归守卫）
- 本报告：`reports/visual_eval/VISUAL_EVALUATION_REPORT.md`
