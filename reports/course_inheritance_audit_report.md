# 课程继承（goblins-den-course）残留审计与清理报告

> 上游：`https://github.com/nicolasbize/goblins-den-course`（作者 Nicolas Bize，Godot 4 3D roguelike 教学项目）
> 本项目 **Lantern Tavern** 起始于该课程模板，后被大幅扩展为地牢酒馆经营游戏。
> 审计日期：2026-07-17

## 一、核心结论

**课程内容已"熔进"本项目的活跃架构，绝大多数不是孤立死文件，而是"存活代码的命名与结构"。**
因此"清除全部继承、保证无残留"在字面意义上无法实现——除非重写整个游戏地基（autoload 单例、敌人体系、装备、陷阱、关卡基类）。

真正可安全删除的**死残留极少**，已全部清理（见第三节）。剩余痕迹分为"署名/许可"与"活跃派生代码"两类，需产品/法律层面决策（见第四节）。

## 二、继承痕迹全景（取证结果）

课程与本项目的顶层结构几乎一一对应：`assets/ data/ fx/ globals/ materials/ scenes/ shaders/ + default_bus_layout.tres / export_presets.cfg / icon.svg / mit-license.md / project.godot / .gitattributes / .gitignore`。

| 类别 | 内容 | 现状 |
|---|---|---|
| A 署名/法律 | `mit-license.md`：`Copyright (c) 2026 Nicolas Bize` | 课程原封 MIT。代码内**已无** `Nicolas/Bize/goblins-den/episode/course` 等字样 |
| B 纯死残留 | 悬空 uid、空目录、goblin 占位材质 | **已清理**（第三节） |
| C 活跃派生代码 | 5 autoload + world/door/base_level + goblin 敌人体系 + equipment + traps | **切勿删**（第四节）|

## 三、已执行的安全清理（零风险，已验证无回归）

| 删除项 | 类型 | 证据 |
|---|---|---|
| `scenes/collectibles/`（含悬空 `dropped_key.gd.uid`） | 课程 dropped_key 遗留 | 脚本已删，全仓零引用，uid `cehnbftnswiu7` 无引用 |
| `scenes/rooms/`（空目录） | base_room 系统删除后的空壳 | 目录内无文件 |
| `materials/goblin_mat.tres` / `goblin_ear_mat.tres` / `goblin_tooth_mat.tres` | 课程 goblin 占位材质 | 全仓（含 `.import`/`assets/`）零引用；goblin 敌人实际用体素调色板 |
| 16 个悬空 `.gd.uid`（`.gd` 已不存在） | 历次删除遗留孤儿 | 含课程 `dropped_key_test.gd.uid` + 我方 `script_entry_probe`/`verify_tavern_scene`/`generate_pixel_icons`/`_seed_probe` 等 + diag/inspect 系列 |

**验证**：headless 加载 `tavern.tscn`/`world.tscn`/`procedural_dungeon.tscn`/`goblin.tscn`/`troll.tscn`/`door.tscn` 全 `OK`；无 `Resource file not found`/`SCRIPT ERROR`；全仓复检无死残留引用；`docs/gdscript_codemap.json` 重生成（482 个 `.gd`）已无 `dropped_key`/`goblin_mat`。

## 四、剩余痕迹——需你决策（不擅自处理）

### A. 署名 / 许可证
- `mit-license.md` 保留了 Nicolas Bize 的版权声明。
- **法律提示**：只要项目仍在使用课程派生代码，MIT 协议要求保留原版权声明；若移除声明同时仍分发派生代码，可能构成协议违约。是否改动属你的法律决定。

### C. 活跃的课程派生"命名/结构"（删=重写，重命名=大规模重构）
这些是当前游戏在跑的核心，**不能删**；若要"去品牌化"只能**重命名**，代价与风险如下：

| 痕迹 | 位置 | 影响面 |
|---|---|---|
| 5 个 autoload：`GameState`/`GameEvents`/`HitStopServer`/`FxHelper`/`AudioManager` | `globals/core/*`（已大幅重写，保留课程 API 名） | 全仓数百处调用 + `project.godot` 用 `uid://` 注册；重命名极高风险 |
| `goblin` 敌人 + 8 个继承它的敌人（zombie/troll/slime/skeleton/rat/kobold/necrolord/dragon） | `scenes/characters/enemies/goblin.tscn` | `dungeon_spawner.gd` 预载 + 8 敌人 `ext_resource` 继承 |
| `world` / `door` / `base_level` 场景与类名 | `scenes/world`、`scenes/door`、`scenes/levels` | 主菜单/酒馆/HUD/procedural_dungeon 多处引用/继承 |
| `snare_trap`（未接入生成器，但有测试） | `scenes/traps/snare_trap.*` | 仅 `trap_variety_test.gd` 测试 + `dungeon_lighting_helper` 名匹配；**边界死代码**，删除需改测试 |
| `equipment` / 其余 `traps`（acid/spikes/flame_vent） | `scenes/equipment`、`scenes/traps` | 被 projectile/item_spawner/builder 大量引用，活跃 |

## 五、建议

1. **署名**：若坚持去除课程署名，建议咨询是否需先充分改写派生代码以主张独立著作权，再处理许可证；否则保留声明最稳妥。
2. **去品牌化命名**（可选，风险递增）：
   - 低风险：`goblin` → 自定义名（重命名场景 + 8 处 `ext_resource` 路径 + spawner 预载 + 体素资产名）。
   - 高风险：重命名 5 个 autoload（需同步 `project.godot` uid 注册 + 全仓调用 + 大量测试），建议分批 + 每批跑全量测试。
3. **snare_trap**：若确认不再规划该陷阱，删除 3 文件并同步删 `trap_variety_test.test_snare_trap_*` 与 `dungeon_lighting_helper` 名匹配分支。
4. 其余活跃派生系统保留——它们已是本游戏不可分割的部分。

## 六、决策执行结果（2026-07-17，用户拍板后）

用户初选"全部彻底清理"，执行前补充取证推翻了两项前提，最终结论如下：

| 项 | 决策 | 执行 |
|---|---|---|
| **snare_trap** | 删除 | ✅ 已删 `snare_trap.gd/.uid/.tscn`；改 `trap_variety_test.gd`（去 `test_snare_trap_*`）、`dungeon_lighting_helper.gd:46`、`procedural_dungeon_test.gd:502`（去 `SnareTrap` 名匹配）。全仓复检 `snare_trap/SnareTrap` **零残留** |
| **mit-license 署名** | 移除 | ✅ `Copyright (c) 2026 Nicolas Bize` → `Copyright (c) 2026 Lantern Tavern`。⚖️ 已书面告知：仍用派生代码却移除原声明严格违反 MIT，法律风险自担 |
| **goblin 重命名** | ❌ 不做 | 取证发现 **goblin 是本项目一等原生生物种族**（`01-世界观设定` 列为 5 大怪物种族之一，有命名 NPC「格鲁姆」、口味/酿酒/赠礼/员工特质/口耳台词/声望系统，~90 文件 + 本地化 + 体素资产依赖）。与课程继承无关，重命名 = 毁项目自身设计。用户知情后确认保留 |
| **5 autoload 重命名** | ❌ 不做 | `GameState/GameEvents/FxHelper/HitStopServer/AudioManager` 是 Godot 社区通用单例名，非课程可识别品牌，重命名零去残留收益、纯高风险。用户知情后确认保留 |

**最终核心结论**：课程"残留"的本质是**派生关系**（已由许可证署名决策处理），而非通用词命名。所有课程专属死残留（dropped_key/goblin 占位材质/base_room/GridMap 旧系统/snare_trap 等）已全部清除；活跃派生系统与项目原生内容（goblin 种族、通用单例）予以保留。项目对 goblins-den-course 的**可清理残留已清理完毕**。

---

## 第七节：二次复核（2026-07-17 多轮核查）

用户要求"再检查几遍，确保没有原项目残留"。执行 4 轮取证 + 1 轮 headless 实跑：

**第 1 轮 — 全仓关键词扫描（代码/文档/资源）**
- `nicolas` / `bize` / `goblins-den` / `goblin's den` / `GoblinDen` → 仅命中本审计报告自身（`reports/course_inheritance_audit_report.md`），**代码零命中**。
- `dropped_key` / `base_room` / `goblin_mat` / `snare_trap` / `SnareTrap` → 命中处均为 `goblin_ear`/`goblin_tooth` 项目原生酿酒材料 ID（有 `brewing_materials.md` 佐证）与 `docs/gdscript_codemap.json` 陈旧条目；**无任何活跃代码引用**。

**第 2 轮 — 文件/目录存在性 Glob**
- `goblin_mat* / goblin_ear_mat / goblin_tooth_mat / snare_trap*` 文件 → **不存在**（已删干净）。
- `dropped_key* / base_room* / Key* / key*` → **不存在**。
- `scenes/collectibles/`、`scenes/rooms/`、`*gridmap*` / `*GridMap*` → **目录与文件均不存在**。

**第 3 轮 — 易混淆词排除（`tutorial` / `episode` / `goblin_den`）**
- 全部命中为项目**原生教程系统**（`tutorial_tavern_coordinator` / `tutorial_hint_overlay` / `new_game_intro` 等）与 gdUnit4 自带文档，**与课程无关**。

**第 4 轮 — 修复发现的唯一真残留**
- `docs/gdscript_codemap.json` 因删 snare_trap 后未重跑而**陈旧**（仍指向已删 `snare_trap.gd/.tscn`）。已重跑 `tools/gdscript_codemap.py`（扫描 481 个 .gd，较前次 482 少 1，数量吻合），重生成后两个 codemap 文件均**零命中** `snare_trap/dropped_key/goblin_mat/base_room`。

**第 5 轮 — headless 实跑加载验证（gold standard）**
- 加载 11 个核心场景/脚本（tavern/world/procedural_dungeon/goblin/troll/door/main_menu/new_game_intro/tutorial_tavern_coordinator/tutorial_hint_overlay/base_level）→ **全部 RESULT_OK**。
- `snare_trap.tscn` → **确认不存在**。
- 全程**无** `Resource file not found` / `SCRIPT ERROR` / 断裂引用。`any_fail=false`。

**复核结论**：经多轮交叉取证与实跑验证，项目对 goblins-den-course 的**可清理残留已确认清理干净**，无隐藏的死文件、死引用或陈旧文档指向原课程。仍保留的派生关系本身（活跃架构 + 已移除署名的 MIT 决策）为已知且已记录的决策项，非残留缺陷。
